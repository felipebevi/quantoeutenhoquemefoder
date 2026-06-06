#!/usr/bin/env bash
# =============================================================
# update-rates.sh — atualiza economias.json com:
#   1) cotacaoBRL  (câmbio do dia via open.er-api.com / frankfurter)
#   2) salarioMinimoMensal e horasMensais (snapshot curado abaixo)
#
# Por que snapshot manual? Não existe API pública gratuita com cobertura
# global confiável para salário mínimo. Wikidata só tem itens conceituais
# (P5658 não traz valor), Trading Economics fechou conta guest, DBpedia
# não cobre. Mantemos os valores aqui no script — uma fonte só, fácil de
# atualizar. Cron diário garante propagação no JSON sem rebuild.
#
# Para atualizar: edite o SNAPSHOT abaixo (codigo, salario, horas, obs)
# e bumpe SALARIOS_REVISADOS_EM. Commit + cron faz o resto.
#
# horasMensais segue a jornada legal típica do país:
#   X h/semana × 52 sem ÷ 12 meses
#   (Brasil: 220h por convenção CLT, que inclui DSR)
#
# Cron sugerido (diário 06:00):
#   0 6 * * * /root/precoemsuor/update-rates.sh >> /var/log/precoemsuor-rates.log 2>&1
# =============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON="$DIR/economias.json"

API1="https://open.er-api.com/v6/latest/BRL"
API2="https://api.frankfurter.app/latest?from=BRL"

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

echo "[$(date -u +%FT%TZ)] buscando cotações..."
if ! curl -fsS --max-time 25 "$API1" -o "$TMP"; then
  echo "  API1 falhou, tentando API2..."
  curl -fsS --max-time 25 "$API2" -o "$TMP"
fi

python3 - "$JSON" "$TMP" <<'PY'
import json, sys, datetime

econ_path, rates_path = sys.argv[1], sys.argv[2]
with open(econ_path, encoding="utf-8") as f: econ = json.load(f)
with open(rates_path, encoding="utf-8") as f: api  = json.load(f)

# ════════════════════════════════════════════════════════════════════════
# SNAPSHOT — fonte da verdade de salário mínimo e jornada por país.
# Atualizar quando salários mudarem (geralmente 1× por ano).
# ════════════════════════════════════════════════════════════════════════
SALARIOS_REVISADOS_EM = "2025-12-06"
# (cc, salarioMinimoMensal local, horasMensais, obs)
SNAPSHOT = {
    # cc:   salario,    horas,  obs
    "BR": ( 1518,       220,    "R$ 1.518 (2025) · CLT 220h/mês"),
    "US": ( 1257,       173,    "Federal US$ 7,25/h × 173 · 40h/sem"),
    "CN": ( 2690,       174,    "Xangai ¥ 2.690 · 40h/sem"),
    "DE": ( 2222,       173,    "€ 12,82/h × 173 · 40h/sem (2025)"),
    "JP": ( 183000,     173,    "¥ 1.055/h × 173 (média nacional) · 40h/sem"),
    "IN": ( 9750,       208,    "Mínimo federal não-qualificado · 48h/sem"),
    "GB": ( 2117,       173,    "National Living Wage £ 12,21/h (abr/2025)"),
    "FR": ( 1802,       152,    "SMIC bruto € 11,88/h · 35h/sem (2025)"),
    "IT": ( 1300,       173,    "Sem mínimo legal nacional · convenção coletiva"),
    "CA": ( 2998,       173,    "Federal C$ 17,30/h × 173 (abr/2025)"),
    "RU": ( 22440,      173,    "MROT 2025 · 40h/sem"),
    "MX": ( 8476,       208,    "Zona geral MX$ 278,80/dia · 48h/sem"),
    "AU": ( 4179,       165,    "A$ 24,10/h × 165 · 38h/sem (jul/2024)"),
    "KR": ( 2096270,    209,    "₩ 10.030/h × 209 · 40h/sem (2025)"),
    "ES": ( 1184,       173,    "SMI 14 pagamentos/ano · 40h/sem (2025)"),
    "ID": ( 5396760,    173,    "UMP Jacarta 2025 · 40h/sem (varia por província)"),
    "NL": ( 2436,       156,    "€ 14,06/h · 36h/sem média (2025)"),
    "TR": ( 26005,      195,    "Asgari ücret bruto · 45h/sem (2025)"),
    "SA": ( 4000,       208,    "Para nacionais · 48h/sem"),
    "CH": ( 4426,       182,    "Sem mínimo nacional (base Genebra CHF 24,48/h · 42h/sem)"),
}
# ════════════════════════════════════════════════════════════════════════

# ── Câmbio ──────────────────────────────────────────────────────────────
rates = api.get("rates") or api.get("conversion_rates") or {}
if not rates: sys.exit("resposta de câmbio sem 'rates'")
n_cur = 0
for p in econ["paises"]:
    if p["moeda"] == "BRL":
        p["cotacaoBRL"] = 1.0; continue
    r = rates.get(p["moeda"])
    if r:
        p["cotacaoBRL"] = round(1.0 / float(r), 6); n_cur += 1

# ── Salário mínimo e horas (do snapshot) ────────────────────────────────
n_wage, n_hrs = 0, 0
for p in econ["paises"]:
    snap = SNAPSHOT.get(p["codigo"])
    if not snap: continue
    sal, hrs, obs = snap
    if p.get("salarioMinimoMensal") != sal:
        p["salarioMinimoMensal"] = sal; n_wage += 1
    if p.get("horasMensais") != hrs:
        p["horasMensais"] = hrs; n_hrs += 1
    p["obs"] = obs

econ["atualizadoEm"]         = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
econ["salariosRevisadosEm"]  = SALARIOS_REVISADOS_EM

# Aviso se snapshot ficar velho (>365 dias)
rev = econ.get("salariosRevisadosEm")
warn = ""
try:
    dias = (datetime.date.today() - datetime.date.fromisoformat(rev)).days
    if dias > 365:
        warn = f" | ⚠ snapshot sem revisão há {dias} dias (editar SNAPSHOT no update-rates.sh)"
except (ValueError, TypeError): pass

with open(econ_path, "w", encoding="utf-8") as f:
    json.dump(econ, f, ensure_ascii=False, indent=2); f.write("\n")

print(f"  OK: {n_cur} cotações + {n_wage} salários + {n_hrs} horas atualizados em {econ['atualizadoEm']}{warn}")
PY

echo "[$(date -u +%FT%TZ)] concluído."
