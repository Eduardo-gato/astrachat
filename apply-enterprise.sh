#!/usr/bin/env bash
#
# AstraChat — Assistente interativo para aplicar a imagem "enterprise" (baked)
# no Docker Swarm, perguntando passo a passo (arquitetura, imagem, serviço, ...).
#
# Requisitos: rodar num MANAGER do Swarm com docker + buildx.
#
# Uso (baixe e execute, NÃO use pipe em script interativo):
#   wget -qO apply-enterprise.sh https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/apply-enterprise.sh
#   bash apply-enterprise.sh
#
set -euo pipefail

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
C_RED='\033[31m'; C_CYAN='\033[36m'; C_DIM='\033[2m'
info()  { printf "${C_CYAN}%s${C_RESET}\n" "$*"; }
ok()    { printf "${C_GREEN}%s${C_RESET}\n" "$*"; }
warn()  { printf "${C_YELLOW}%s${C_RESET}\n" "$*"; }
err()   { printf "${C_RED}%s${C_RESET}\n" "$*" >&2; }
dim()   { printf "${C_DIM}%s${C_RESET}\n" "$*"; }
title() { printf "\n${C_BOLD}== %s ==${C_RESET}\n" "$*"; }

die() { err "$*"; exit 1; }

# --- helpers de prompt -------------------------------------------------------
ask() { # ask VAR "pergunta" "default"
  local __var="$1" __q="$2" __def="${3:-}" __ans=""
  if [ -n "$__def" ]; then
    read -r -p "$__q [$__def]: " __ans || true
    __ans="${__ans:-$__def}"
  else
    read -r -p "$__q: " __ans || true
  fi
  printf -v "$__var" '%s' "$__ans"
}

ask_choice() { # ask_choice VAR "pergunta" "a|b|c" "default"
  local __var="$1" __q="$2" __opts="$3" __def="${4:-}" __ans="" __o __i=0 __defnum=""
  local __words="${__opts//|/ }"
  echo "  Opções:"
  for __o in $__words; do
    __i=$((__i + 1))
    printf '    %s) %s\n' "$__i" "$__o"
    if [ "$__o" = "$__def" ]; then __defnum="$__i"; fi
  done
  while :; do
    read -r -p "$__q [${__defnum:-$__def}]: " __ans || true
    __ans="${__ans:-${__defnum:-$__def}}"
    if [ "$__ans" -eq "$__ans" ] 2>/dev/null; then
      __i=0
      for __o in $__words; do
        __i=$((__i + 1))
        if [ "$__ans" = "$__i" ]; then printf -v "$__var" '%s' "$__o"; return 0; fi
      done
    fi
    for __o in $__words; do
      if [ "$__ans" = "$__o" ]; then printf -v "$__var" '%s' "$__ans"; return 0; fi
    done
    warn "Opção inválida: '$__ans'. Digite o número ou o nome."
  done
}

confirm() { # confirm "pergunta" -> 0 sim / 1 não
  local __ans=""
  read -r -p "$1 [Y/n]: " __ans || true
  case "${__ans:-Y}" in y|Y|yes|YES|s|S) return 0;; *) return 1;; esac
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando '$1' não encontrado. $2"; }

# --- 0. boas-vindas ----------------------------------------------------------
clear 2>/dev/null || true
printf "${C_BOLD}"
cat <<'BANNER'
  ___         _          ___ _         _       _
 / _ \       | |        / __| |_  __ _| |_ ___| |_
| |_| |_ _ __| |_ __ _  | (__| ' \/ _` |  _/ _ \  _|
 \___/|_| |_|_|\__,_|   \___|_||_\__,_|\__\___/\__|
         AstraChat — aplicar imagem enterprise (baked)
BANNER
printf "${C_RESET}\n"
dim "Este assistente vai: montar a imagem bakeda (multi/single-arch) e atualizar o serviço."
dim "Cada passo mostra um default entre [ ]. Aperte ENTER para aceitar."
echo

# --- 1. checagens de ambiente ------------------------------------------------
title "1) Ambiente"
need_cmd docker "Instale o Docker neste host (ou rode num manager do Swarm)."
docker info >/dev/null 2>&1 || die "Sem acesso ao daemon do Docker (permissão? rode com sudo ou entre no grupo docker)."
ok "Docker acessível."

SWARM_STATE="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo none)"
if [ "$SWARM_STATE" = "active" ]; then
  NODE_ROLE="$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo false)"
  if [ "$NODE_ROLE" = "true" ]; then
    ok "Swarm ativo e este nó é MANAGER."
  else
    warn "Swarm ativo, mas este nó NÃO é manager — 'docker service update' vai falhar."
    confirm "Continuar mesmo assim?" || die "Abortado."
  fi
else
  warn "Swarm não está ativo neste nó ($SWARM_STATE)."
  dim "Sem Swarm, o assistente só faz build/push (não atualiza serviço)."
fi
echo

# --- 2. contexto do repo -----------------------------------------------------
title "2) Código-fonte (Dockerfile.bake + patches/)"
REPO_URL_DEFAULT="https://github.com/Eduardo-gato/astrachat.git"
REPO_REF_DEFAULT="main"

dim "O assistente precisa da pasta do projeto (com 'Dockerfile.bake' e 'patches/') para montar a imagem."
dim ""
dim "  atual = usa a pasta onde você está rodando agora (deve conter os arquivos do repo)"
dim "  clone = baixa automaticamente do GitHub (precisa de git + internet)"
dim ""

if [ -f "./Dockerfile.bake" ] && [ -d "./patches" ]; then
  CTX="$(pwd)"
  ok "Encontrei Dockerfile.bake e patches/ aqui: $CTX"
  ask_choice SOURCE "Como quer obter o código?" "atual|clone" "atual"
else
  warn "Não achei Dockerfile.bake/patches/ na pasta atual: $(pwd)"
  dim "Dica: rode o assistente dentro de um clone do repo, ou escolha 'clone' abaixo."
  ask_choice SOURCE "Como quer obter o código?" "atual|clone" "clone"
fi

if [ "$SOURCE" = "atual" ]; then
  CTX="$(pwd)"
  dim "Usando a pasta atual como contexto: $CTX"
else
  dim "Exemplo de URL: https://github.com/Eduardo-gato/astrachat.git"
  ask REPO_URL "URL do repositório" "$REPO_URL_DEFAULT"
  dim "Exemplo de branch/tag: main  (ou uma tag, ex.: v4.17.1)"
  ask REPO_REF "Branch/tag" "$REPO_REF_DEFAULT"
  BUILD_DIR="${TMPDIR:-/tmp}/astrachat-build"
  info "Clonando $REPO_URL ($REPO_REF) em $BUILD_DIR ..."
  rm -rf "$BUILD_DIR"
  need_cmd git "Instale o git ou use a opção 'atual' apontando para um clone local."
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$BUILD_DIR"
  CTX="$BUILD_DIR"
fi

[ -f "$CTX/Dockerfile.bake" ] || die "Dockerfile.bake não encontrado em $CTX."
[ -d "$CTX/patches" ] || die "Diretório patches/ não encontrado em $CTX."
ok "Contexto OK: $CTX"
echo

# --- 3. imagens --------------------------------------------------------------
title "3) Imagens"
ask BASE_IMAGE "Imagem BASE (FROM)" "astraonline/astrachat:latest"
ask TARGET_IMAGE "Imagem de DESTINO (será criada)" "edwardbra/astrachat:enterprise"
echo

# --- 4. arquitetura ----------------------------------------------------------
title "4) Arquitetura"
dim "amd64  = servidores x86_64 (Intel/AMD)"
dim "arm64  = ARM (ex.: Oracle Ampere, Raspberry, Apple)"
dim "both   = manifest multi-arch (funciona nos dois; build mais lento)"
ask_choice ARCH "Qual arquitetura?" "amd64|arm64|both" "both"

case "$ARCH" in
  both)    PLATFORMS="linux/amd64,linux/arm64" ;;
  amd64)   PLATFORMS="linux/amd64" ;;
  arm64)   PLATFORMS="linux/arm64" ;;
esac

# normaliza a arquitetura do host (docker reporta x86_64/aarch64)
HOST_ARCH_RAW="$(docker info --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
case "$HOST_ARCH_RAW" in
  x86_64|amd64)      HOST_ARCH="amd64" ;;
  aarch64|arm64*)    HOST_ARCH="arm64" ;;
  *)                 HOST_ARCH="$HOST_ARCH_RAW" ;;
esac
info "Arquitetura deste host: $HOST_ARCH (detectada como '$HOST_ARCH_RAW')"

# cross-build só é necessário se pediu multi-arch OU uma arch diferente do host
if [ "$ARCH" = "both" ]; then
  CROSS=1
  CROSS_WHY="multi-arch (você pediu amd64 + arm64)"
elif [ "$HOST_ARCH" != "$ARCH" ]; then
  CROSS=1
  CROSS_WHY="você pediu $ARCH, mas o host é $HOST_ARCH"
else
  CROSS=0
  CROSS_WHY="a arquitetura pedida é a do host ($HOST_ARCH)"
fi

if [ "$CROSS" = "1" ]; then
  warn "Cross-build NECESSÁRIO: $CROSS_WHY."
  dim "Isso significa gerar imagem para uma arquitetura diferente da deste host — o BuildKit usa QEMU."
else
  ok "Sem cross-build: $CROSS_WHY. (não precisa de QEMU)"
fi
echo

# --- 5. buildx ---------------------------------------------------------------
BUILDER="multiarch"
title "5) Builder (buildx) — o que é e por que"
dim "O buildx é o construtor de imagens do Docker. Para gerar imagens de OUTRA"
dim "arquitetura (ou multi-arch) é preciso um builder dedicado (driver"
dim "docker-container), que roda um BuildKit isolado com suporte a multiplataforma."
docker buildx version >/dev/null 2>&1 || die "buildx não disponível (atualize o Docker ou instale o plugin buildx)."
info "Criando/usando o builder '$BUILDER'..."
docker buildx create --name "$BUILDER" --driver docker-container >/dev/null 2>&1 || true
docker buildx use "$BUILDER"
docker buildx inspect --bootstrap >/dev/null 2>&1 || warn "Falha ao inicializar o builder (siga mesmo assim)."
ok "Builder '$BUILDER' pronto e selecionado."
echo

if [ "$CROSS" = "1" ]; then
  title "5b) QEMU (emulação para cross-build)"
  dim "Como o host é $HOST_ARCH e você quer gerar para: $PLATFORMS"
  dim "o BuildKit precisa do QEMU (binfmt_misc) para 'rodar' binários da outra"
  dim "arquitetura durante o build. Sem isso, a plataforma diferente falha."
  dim "É seguro: apenas registra emuladores (não altera a imagem nem o host)."
  if confirm "Instalar/atualizar o QEMU (tonistiigi/binfmt)?"; then
    docker run --privileged --rm tonistiigi/binfmt --install amd64,arm64 || warn "Falha no binfmt; cross-build pode não funcionar."
    ok "QEMU registrado."
  else
    warn "QEMU não instalado — o build de $ARCH fora do host pode falhar."
  fi
  echo
else
  dim "(5b pulado: nenhuma arquitetura diferente do host foi pedida)"
  echo
fi

# --- 6. serviço --------------------------------------------------------------
title "6) Serviço do Swarm"
if [ "$SWARM_STATE" = "active" ]; then
  DETECTED="$(docker service ls --format '{{.Name}}' 2>/dev/null | grep -iE 'astrachat|chatwoot' | head -n1 || true)"
  ask SERVICE "Nome do serviço" "${DETECTED:-astrachat_astrachat}"
else
  SERVICE=""
fi
echo

# --- 7. ação ----------------------------------------------------------------
title "7) O que fazer?"
dim "  tudo     = build + push + atualizar serviço + verificar"
dim "  build    = só build + push"
dim "  update   = só atualizar o serviço com a imagem existente"
dim "  rollback = reverter o serviço para a revisão anterior"
dim ""
ask_choice ACTION "Ação" "tudo|build|update|rollback" "tudo"
echo

# --- 8. login no registry ----------------------------------------------------
if [ "$ACTION" = "update" ] || [ "$ACTION" = "rollback" ]; then
  title "8) Login no registry (pulado)"
  dim "Você escolheu '$ACTION' — não haverá push, então não precisa de login."
  dim "Os nós só baixam (pull); se a imagem é pública, baixam sem autenticação."
  echo
else
  title "8) Login no registry (necessário para PUSH)"
  REG_HOST="${TARGET_IMAGE%%/*}"
  if printf '%s' "$REG_HOST" | grep -q '[.:]'; then
    REG_HOST="${REG_HOST%%:*}"
  else
    REG_HOST="docker.io"
  fi
  dim "Atenção: ser 'pública' só dispensa senha para BAIXAR (pull)."
  dim "Enviar (push) SEMPRE exige login — só o dono publica na tag."
  dim "Registry detectado: $REG_HOST"
  if confirm "Fazer 'docker login' agora?"; then
    ask REG_USER "Usuário do registry" ""
    docker login "$REG_HOST" -u "$REG_USER" || warn "Login falhou (siga e tente o push)."
  else
    dim "OK — se você já logou antes, o push usa as credenciais salvas."
    dim "Se não, o push pode falhar com 'denied'."
  fi
  echo
fi

# --- 9. unlock (rails runner) -----------------------------------------------
RUN_UNLOCK=0
WIDGET_SRC=""; WIDGET_KEY=""
if [ "$ACTION" = "tudo" ] || [ "$ACTION" = "update" ]; then
  title "9) Rodar também o unlock_permanent.rb (dentro do container)?"
  dim "Aplica trigger no Postgres, override enterprise, All features, etc."
  if confirm "Rodar o unlock após atualizar o serviço?"; then
    RUN_UNLOCK=1
    ask UNLOCK_URL "URL do unlock_permanent.rb" "https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb"
    if confirm "Injetar o widget do AstraCalls no dashboard (DASHBOARD_SCRIPTS)?"; then
      ask WIDGET_SRC "ASTRACALLS_WIDGET_SRC" "https://seudominio.com.br/widget.js"
      ask WIDGET_KEY "ASTRACALLS_WIDGET_KEY (ou a API key)" ""
    fi
  fi
  echo
fi

# --- 10. resumo --------------------------------------------------------------
title "Resumo"
printf '  %-22s %s\n' "Contexto:"      "$CTX"
printf '  %-22s %s\n' "Base:"          "$BASE_IMAGE"
printf '  %-22s %s\n' "Destino:"       "$TARGET_IMAGE"
printf '  %-22s %s\n' "Plataformas:"   "$PLATFORMS"
printf '  %-22s %s\n' "Cross-build:"   "$([ "$CROSS" = 1 ] && echo sim || echo não)"
printf '  %-22s %s\n' "Ação:"          "$ACTION"
if [ -n "$SERVICE" ]; then printf '  %-22s %s\n' "Serviço:" "$SERVICE"; fi
printf '  %-22s %s\n' "Rodar unlock:"  "$([ "$RUN_UNLOCK" = 1 ] && echo sim || echo não)"
if [ "$RUN_UNLOCK" = 1 ]; then printf '  %-22s %s\n' "Widget AstraCalls:" "$WIDGET_SRC"; fi
echo

confirm "Confirma e executa?" || die "Abortado pelo usuário."

# --- 11. execução ------------------------------------------------------------
do_build() {
  title "Build + push ($PLATFORMS)"
  docker buildx build \
    --builder "$BUILDER" \
    --platform "$PLATFORMS" \
    --build-arg "BASE_IMAGE=$BASE_IMAGE" \
    -f "$CTX/Dockerfile.bake" \
    -t "$TARGET_IMAGE" \
    --push "$CTX"
  ok "Imagem publicada: $TARGET_IMAGE"
  docker buildx imagetools inspect "$TARGET_IMAGE" 2>/dev/null || true
  echo
}

do_update() {
  [ -n "$SERVICE" ] || die "Serviço não definido."
  title "Atualizando serviço '$SERVICE'"
  docker service update \
    --image "$TARGET_IMAGE" \
    --with-registry-auth \
    --force \
    "$SERVICE"
  echo
  info "Aguardando convergência..."
  for _ in $(seq 1 60); do
    if docker service ps "$SERVICE" --filter desired-state=running --format '{{.CurrentState}}' 2>/dev/null | grep -q '^Running'; then
      ok "Serviço convergiu."
      break
    fi
    sleep 5
  done
  docker service ps "$SERVICE" --no-trunc | head -n 5
  echo
}

do_verify() {
  title "Verificação (pricing_plan)"
  local cid
  cid="$(docker ps --filter "name=${SERVICE}." --filter status=running --format '{{.ID}}' 2>/dev/null | head -n1 || true)"
  if [ -z "$cid" ]; then warn "Container em execução não encontrado; pule a verificação."; return 0; fi
  docker exec "$cid" sh -c 'DISABLE_SPRING=1 bundle exec rails runner "puts ChatwootHub.pricing_plan; puts ChatwootHub.pricing_plan_quantity"' 2>/dev/null \
    | grep -vE 'WARN|INFO|RubyLLM|ip_lookup' || true
  echo
}

do_unlock() {
  [ "$RUN_UNLOCK" = 1 ] || return 0
  title "Rodando unlock_permanent.rb"
  local cid
  cid="$(docker ps --filter "name=${SERVICE}." --filter status=running --format '{{.ID}}' 2>/dev/null | head -n1 || true)"
  [ -n "$cid" ] || { warn "Container não encontrado; unlock não executado."; return 0; }
  docker exec \
    -e ASTRACALLS_WIDGET_SRC="$WIDGET_SRC" \
    -e ASTRACALLS_WIDGET_KEY="$WIDGET_KEY" \
    "$cid" sh -c "wget -qO- '$UNLOCK_URL' | bundle exec rails runner -" \
    || docker exec -e ASTRACALLS_WIDGET_SRC="$WIDGET_SRC" -e ASTRACALLS_WIDGET_KEY="$WIDGET_KEY" \
         "$cid" sh -c "curl -sL '$UNLOCK_URL' | bundle exec rails runner -"
  echo
}

do_rollback() {
  [ -n "$SERVICE" ] || die "Serviço não definido."
  title "Rollback do serviço '$SERVICE'"
  docker service rollback "$SERVICE"
  echo
}

case "$ACTION" in
  tudo)     do_build; do_update; do_verify; do_unlock ;;
  build)    do_build ;;
  update)   do_update; do_verify; do_unlock ;;
  rollback) do_rollback ;;
esac

title "Concluído"
ok "Tudo certo."
dim "Verifique na UI: Super Admin > Settings (plano) e App Config > internal (Dashboard Scripts)."
echo
