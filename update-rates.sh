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
SALARIOS_REVISADOS_EM = "2026-06-06"
# (cc, salarioMinimoMensal local, horasMensais, obs)
# Valores 2026 oficiais quando já anunciados; demais marcados como "2025 (pendente)".
SNAPSHOT = {
    # cc:   salario,    horas,  obs
    "BR": ( 1620,       220,    "R$ 1.620 (2026) · INPC + produtividade · CLT 220h/mês"),
    "US": ( 1257,       173,    "Federal US$ 7,25/h × 173 (sem mudança desde 2009)"),
    "CN": ( 2740,       174,    "Xangai 2026 ¥ 2.740 · 40h/sem"),
    "DE": ( 2405,       173,    "Mindestlohn 2026 € 13,90/h × 173 · 40h/sem"),
    "JP": ( 193000,     173,    "Média nacional ¥ 1.118/h × 173 (anúncios 2026) · 40h/sem"),
    "IN": ( 9750,       208,    "Mínimo federal não-qualificado (2025, pendente 2026) · 48h/sem"),
    "GB": ( 2199,       173,    "National Living Wage £ 12,71/h (abr/2026) · 40h/sem"),
    "FR": ( 1832,       152,    "SMIC € 12,05/h (revisão 2026) · 35h/sem"),
    "IT": ( 1300,       173,    "Sem mínimo legal nacional · convenção coletiva"),
    "CA": ( 3071,       173,    "Federal C$ 17,75/h × 173 (abr/2026) · 40h/sem"),
    "RU": ( 27093,      173,    "MROT 2026 ₽ 27.093 · 40h/sem"),
    "MX": ( 9515,       208,    "Zona geral MX$ 313/dia (2026) · 48h/sem"),
    "AU": ( 4322,       165,    "A$ 24,95/h × 165 (jul/2025 - vale 2026) · 38h/sem"),
    "KR": ( 2156880,    209,    "₩ 10.320/h × 209 · 40h/sem (2026)"),
    "ES": ( 1229,       173,    "SMI 2026 € 17.206/14 pagamentos · 40h/sem"),
    "ID": ( 5396760,    173,    "UMP Jacarta 2025 (2026 a anunciar dez/2025) · 40h/sem"),
    "NL": ( 2494,       156,    "€ 14,40/h (jan/2026) · 36h/sem média"),
    "TR": ( 26005,      195,    "Asgari ücret bruto (2025; revisão 2026 anunciada jan) · 45h/sem"),
    "SA": ( 4000,       208,    "Para nacionais · 48h/sem (sem mudança 2026)"),
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
