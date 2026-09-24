#!/usr/bin/env bash
#
# r2-push.sh — sobe os arquivos do unlock para o Cloudflare R2 (bucket unlock-chat).
#
# Uso:
#   export CLOUDFLARE_API_TOKEN=seu_token_r2_edit
#   bash r2-push.sh
#
# Opcional:
#   R2_BUCKET=unlock-chat
#   R2_FILES="apply-enterprise.sh unlock_permanent.rb README.md"
#
# Gera também a URL pública (r2.dev) de cada arquivo, se o acesso público estiver ligado.
#
set -euo pipefail

CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-bff7ef9fff44366a3e51710d7d3856e3}"
R2_BUCKET="${R2_BUCKET:-unlock-chat}"
R2_FILES="${R2_FILES:-apply-enterprise.sh unlock_permanent.rb README.md}"
R2_PUBLIC_BASE="${R2_PUBLIC_BASE:-https://script.toky.top}"

: "${CLOUDFLARE_API_TOKEN:?Defina CLOUDFLARE_API_TOKEN (token com Workers R2 Storage: Edit)}"

API="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/r2/buckets/${R2_BUCKET}/objects"

echo "Bucket: ${R2_BUCKET}"
echo "Conta:  ${CLOUDFLARE_ACCOUNT_ID}"
echo

ok_count=0
err_count=0
for f in $R2_FILES; do
  if [ ! -f "$f" ]; then
    echo "pulando  $f (não encontrado)"
    continue
  fi

  code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: text/plain; charset=utf-8" \
    --data-binary "@${f}" "${API}/${f}")"

  if [ "$code" = "200" ]; then
    echo "OK       ${f}  ->  ${R2_PUBLIC_BASE}/${f}"
    ok_count=$((ok_count + 1))
  else
    echo "ERRO     ${f}  (HTTP ${code})"
    err_count=$((err_count + 1))
  fi
done

echo
echo "Enviados: ${ok_count} | Falhas: ${err_count}"
[ "$err_count" -eq 0 ] || exit 1
