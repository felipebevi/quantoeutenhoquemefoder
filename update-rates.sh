#!/usr/bin/env bash
# =============================================================
# update-rates.sh — atualiza câmbio (cotacaoBRL) em economias.json.
#
# Os salários mínimos mensais ficam em economias.json e são curados
# manualmente (campo "salariosRevisadosEm"). Não há API pública gratuita
# confiável com cobertura global para esse dado — tentei Wikidata (P5658
# devolve só itens conceituais, não valores), Trading Economics (conta
# guest descontinuada), DBpedia (cobertura zero p/ esses países), OECD
# (parcial). Quando a Wikipedia/IBGE/etc atualizarem, basta editar o
# JSON e bumpar "salariosRevisadosEm".
#
# Este script:
#   1) atualiza cotacaoBRL de cada moeda (open.er-api.com / frankfurter)
#   2) avisa se os salários estão sem revisão há > 365 dias
#
# Cron sugerido (diário 06:00):
#   0 6 * * * /root/quantoeutenhoquemefoder/update-rates.sh >> /var/log/qtqmf-rates.log 2>&1
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

rates = api.get("rates") or api.get("conversion_rates") or {}
if not rates: sys.exit("resposta de câmbio sem 'rates'")

n_cur = 0
for p in econ["paises"]:
    if p["moeda"] == "BRL":
        p["cotacaoBRL"] = 1.0; continue
    r = rates.get(p["moeda"])
    if r:
        p["cotacaoBRL"] = round(1.0 / float(r), 6); n_cur += 1

econ["atualizadoEm"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Aviso de salário desatualizado (>365 dias) — manutenção manual periódica.
rev = econ.get("salariosRevisadosEm")
warn = ""
if rev:
    try:
        dias = (datetime.date.today() - datetime.date.fromisoformat(rev)).days
        if dias > 365:
            warn = f" | ⚠ salários sem revisão há {dias} dias (rever economias.json)"
    except ValueError:
        pass

with open(econ_path, "w", encoding="utf-8") as f:
    json.dump(econ, f, ensure_ascii=False, indent=2); f.write("\n")

print(f"  OK: {n_cur} cotações atualizadas em {econ['atualizadoEm']}{warn}")
PY

echo "[$(date -u +%FT%TZ)] concluído."
