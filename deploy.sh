#!/usr/bin/env bash
# =============================================================
# deploy.sh — quantoeutenhoquemefoder.com.br
# Commit + push para o GitHub e atualiza o container no servidor "joy".
# Uso: ./deploy.sh "mensagem do commit"
# =============================================================
set -euo pipefail

COMMIT_MSG="${1:-deploy: atualiza app}"
REMOTE="joy"
REMOTE_DIR="/root/quantoeutenhoquemefoder"
GITHUB_KEY="$HOME/.ssh/id_ed25519_precoja"
GITHUB_TOKEN="$(ssh "$REMOTE" "cat /root/.github_token 2>/dev/null || echo ''")"
REPO_URL="https://felipebevi:${GITHUB_TOKEN}@github.com/felipebevi/quantoeutenhoquemefoder.git"

echo "==== [1/3] Commit + push ===="
git add -A
git commit -m "$COMMIT_MSG" || echo "  Nada novo para commitar."
GIT_SSH_COMMAND="ssh -i $GITHUB_KEY -o IdentitiesOnly=yes" git push git@github.com:felipebevi/quantoeutenhoquemefoder.git main

echo "==== [2/3] Deploy no servidor $REMOTE ===="
ssh "$REMOTE" bash <<ENDSSH
set -euo pipefail
REMOTE_DIR="$REMOTE_DIR"
if [ -d "\$REMOTE_DIR/.git" ]; then
  cd "\$REMOTE_DIR" && git pull origin main
else
  git clone "$REPO_URL" "\$REMOTE_DIR" && cd "\$REMOTE_DIR"
fi
docker compose up --build -d
docker image prune -f
ENDSSH

echo "==== [3/3] Status ===="
ssh "$REMOTE" "docker ps --filter name=quantoeutenhoquemefoder-web --format 'table {{.Names}}\t{{.Status}}'"
echo "Deploy concluído: https://quantoeutenhoquemefoder.com.br"
