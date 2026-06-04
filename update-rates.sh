#!/usr/bin/env bash
# =============================================================
# update-rates.sh — atualiza as cotações (cotacaoBRL) em economias.json
# Busca câmbio em uma API pública gratuita (sem chave) e reescreve o JSON.
# Pensado para rodar no cron do servidor. Ex.: diariamente às 06:00:
#   0 6 * * * /root/quantoeutenhoquemefoder/update-rates.sh >> /var/log/qtqmf-rates.log 2>&1
#
# Também pode ser disparado "via URL" por um webhook/cron externo que faça:
#   curl -fsS https://SEU-WEBHOOK/  (que por sua vez executa este script)
# =============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON="$DIR/economias.json"

# Fonte primária e fallback (ambas gratuitas, base = BRL → 1 BRL vale X moeda)
API1="https://open.er-api.com/v6/latest/BRL"
API2="https://api.frankfurter.app/latest?from=BRL"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "[$(date -u +%FT%TZ)] buscando cotações..."
if ! curl -fsS --max-time 25 "$API1" -o "$TMP"; then
  echo "  API1 falhou, tentando API2..."
  curl -fsS --max-time 25 "$API2" -o "$TMP"
fi

# Atualiza o JSON com Python 3 (presente por padrão no Ubuntu).
python3 - "$JSON" "$TMP" <<'PY'
import json, sys, datetime

econ_path, rates_path = sys.argv[1], sys.argv[2]

with open(econ_path, encoding="utf-8") as f:
    econ = json.load(f)
with open(rates_path, encoding="utf-8") as f:
    api = json.load(f)

# Normaliza: queremos rates[MOEDA] = quantas unidades da moeda valem 1 BRL.
rates = api.get("rates") or api.get("conversion_rates") or {}
if not rates:
    sys.exit("resposta da API sem 'rates'")

atualizados = 0
for p in econ["paises"]:
    cur = p["moeda"]
    if cur == "BRL":
        p["cotacaoBRL"] = 1.0
        continue
    r = rates.get(cur)
    if r:                      # cotacaoBRL = reais por 1 unidade da moeda = 1 / (moeda por BRL)
        p["cotacaoBRL"] = round(1.0 / float(r), 6)
        atualizados += 1

econ["atualizadoEm"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

with open(econ_path, "w", encoding="utf-8") as f:
    json.dump(econ, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"  OK: {atualizados} moedas atualizadas em {econ['atualizadoEm']}")
PY

echo "[$(date -u +%FT%TZ)] concluído."
