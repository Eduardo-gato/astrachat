#!/usr/bin/env bash
#
# AstraChat — Assistente interativo para aplicar a imagem "enterprise"
# (multi-arch) no Docker Swarm, perguntando passo a passo.
#
# Requisitos: rodar num MANAGER do Swarm com docker.
#
# Uso (baixa E já executa). Tenta o espelho (Cloudflare R2) primeiro e cai pro
# GitHub se falhar:
#   bash <(curl -fsSL https://script.toky.top/apply-enterprise.sh || curl -fsSL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/apply-enterprise.sh)
#
# Dica: crie um atalho e digite só 'unlock':
#   alias unlock='bash <(curl -fsSL https://script.toky.top/apply-enterprise.sh || curl -fsSL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/apply-enterprise.sh)'
#
# Obs: NÃO use "curl ... | bash" — o pipe consome o stdin e as perguntas travam.
#
# Para o script se AUTO-APAGAR ao sair, baixe para arquivo:
#   (curl -fsSL https://script.toky.top/apply-enterprise.sh || curl -fsSL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/apply-enterprise.sh) -o apply-enterprise.sh && bash apply-enterprise.sh
# (com "bash <(curl ...)" não há arquivo, então nada é removido)
#
set -euo pipefail

# Endereços do assistente e do unlock (R2 primeiro, GitHub como fallback)
ASSIST_URL_R2="https://script.toky.top/apply-enterprise.sh"
ASSIST_URL_GH="https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/apply-enterprise.sh"
UNLOCK_URL_R2="https://script.toky.top/unlock_permanent.rb"
UNLOCK_URL_GH="https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb"
# Imagem baked (multi-arch) — é a que deve rodar. A base astraonline/astrachat
# só é usada na hora de BUILDAR (não é necessária para rodar).
ASTRACHAT_IMAGE="edwardbra/astrachat:enterprise"
ASTRACHAT_IMAGE_URL="https://hub.docker.com/r/edwardbra/astrachat"

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
progress_bar() { # progress_bar "rótulo" [passos]
  local __label="$1" __steps="${2:-24}" __i __j __bar __pct
  for ((__i = 0; __i <= __steps; __i++)); do
    __pct=$(( __i * 100 / __steps ))
    __bar=""
    for ((__j = 0; __j < __steps; __j++)); do
      if [ "$__j" -lt "$__i" ]; then __bar="${__bar}#"; else __bar="${__bar}."; fi
    done
    printf "\r${C_CYAN}%s${C_RESET} [%s] %3d%%" "$__label" "$__bar" "$__pct"
    sleep 0.04 2>/dev/null || sleep 0.1 2>/dev/null || true
  done
  printf "\n"
}

# remove o próprio script, se foi executado a partir de um arquivo
cleanup_self() {
  local __self="${BASH_SOURCE[0]:-}"
  if [ -n "$__self" ] && [ -f "$__self" ]; then
    case "$(basename "$__self")" in
      apply-enterprise.sh)
        rm -f -- "$__self" 2>/dev/null || true
        dim "Arquivo apply-enterprise.sh removido."
        ;;
    esac
  fi
}

# A qualquer momento, digitar sair/exit/quit/q encerra o assistente.
bye() {
  printf "\n"
  progress_bar "Encerrando" 24
  cleanup_self
  printf "\n${C_YELLOW}Saindo do assistente. Até logo!${C_RESET}\n"
  exit 0
}

is_exit() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    sair|exit|quit|q) return 0 ;;
    *) return 1 ;;
  esac
}

read_line() { # read_line VAR "prompt"
  local __var="$1" __prompt="$2" __val=""
  read -r -p "$__prompt" __val || bye
  if is_exit "$__val"; then bye; fi
  printf -v "$__var" '%s' "$__val"
}

ask() { # ask VAR "pergunta" "default"
  local __var="$1" __q="$2" __def="${3:-}" __ans=""
  if [ -n "$__def" ]; then
    read_line __ans "$__q [$__def]: "
    __ans="${__ans:-$__def}"
  else
    read_line __ans "$__q: "
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
    read_line __ans "$__q [${__defnum:-$__def}]: "
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

ask_secret() { # como ask, mas mostra só os últimos 4 chars do default
  local __var="$1" __q="$2" __def="${3:-}" __ans=""
  if [ -n "$__def" ]; then
    read_line __ans "$__q [detectada: ****${__def: -4}]: "
    __ans="${__ans:-$__def}"
  else
    read_line __ans "$__q: "
  fi
  printf -v "$__var" '%s' "$__ans"
}

confirm() { # confirm "pergunta" -> 0 sim / 1 não
  local __ans=""
  read_line __ans "$1 [Y/n]: "
  case "${__ans:-Y}" in y|Y|yes|YES|s|S) return 0;; *) return 1;; esac
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando '$1' não encontrado. $2"; }

blink_hint() { # blink_hint "texto" [vezes]
  local __msg="$1" __n="${2:-3}" __i __len
  __len=${#__msg}
  for ((__i = 0; __i < __n; __i++)); do
    printf "\r${C_YELLOW}${C_BOLD}%s${C_RESET}" "$__msg"
    sleep 0.45 2>/dev/null || sleep 1
    printf "\r%*s\r" "$__len" ""
    sleep 0.3 2>/dev/null || sleep 1
  done
  printf "${C_YELLOW}${C_BOLD}%s${C_RESET}\n" "$__msg"
}

trap 'printf "\n"; bye' INT

# --- 0. boas-vindas ----------------------------------------------------------
clear 2>/dev/null || true
printf "${C_BOLD}"
cat <<'BANNER'
              _            _       ____ _           _
  _   _ _ __ | | ___   ___| | __  / ___| |__   __ _| |_
 | | | | '_ \| |/ _ \ / __| |/ / | |   | '_ \ / _` | __|
 | |_| | | | | | (_) | (__|   <  | |___| | | | (_| | |_
  \__,_|_| |_|_|\___/ \___|_|\_\  \____|_| |_|\__,_|\__|
           unlock Chat — AstraChat enterprise
BANNER
printf "${C_RESET}\n"
dim "Este assistente vai: atualizar o serviço do AstraChat com a imagem"
dim "enterprise (multi-arch) e, opcionalmente, rodar o unlock."
dim "Cada passo mostra um default entre [ ]. Aperte ENTER para aceitar."
echo
warn "Testado na versão do AstraChat: v4.17.1-0.0.2"
echo
blink_hint "Para sair do assistente a qualquer momento, digite: sair  (ou exit / q)" 3
echo

# --- detecta AstraChat/Chatwoot (imagem baixada + serviço/container) ----------
detect_astrachat() {
  ASTRACHAT_SERVICES=""
  ASTRACHAT_IMAGES=""
  if [ "$SWARM_STATE" = "active" ]; then
    ASTRACHAT_SERVICES="$(docker service ls --format '{{.Name}}' 2>/dev/null | grep -iE 'astrachat|chatwoot' || true)"
  fi
  if [ -z "$ASTRACHAT_SERVICES" ]; then
    ASTRACHAT_SERVICES="$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -iE 'astrachat|chatwoot' || true)"
  fi
  ASTRACHAT_IMAGES="$(docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -iE 'astrachat|chatwoot' || true)"
}

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
  dim "Sem Swarm não dá pra atualizar o serviço — rode num manager."
fi

# AstraChat/Chatwoot instalado? Só continua DEPOIS de baixar/instalar.
detect_astrachat
while [ -z "$ASTRACHAT_SERVICES" ]; do
  warn "AstraChat/Chatwoot NÃO está instalado/rodando neste nó."
  dim "O assistente só continua DEPOIS de baixar e subir o AstraChat."
  dim ""
  dim "Imagem baked (multi-arch, atualizada): ${ASTRACHAT_IMAGE}"
  dim "    ${ASTRACHAT_IMAGE_URL}"
  dim ""

  # 1) baixar a imagem
  if [ -z "$ASTRACHAT_IMAGES" ]; then
    if confirm "Deseja baixar a imagem agora (docker pull ${ASTRACHAT_IMAGE})?"; then
      info "Baixando ${ASTRACHAT_IMAGE} ..."
      if docker pull "${ASTRACHAT_IMAGE}"; then
        ok "Imagem baixada com sucesso."
      else
        warn "Falha no docker pull (verifique internet/login no registry)."
      fi
    fi
  else
    dim "Imagem já baixada: ${ASTRACHAT_IMAGES}"
  fi

  # 2) subir a stack
  dim ""
  if [ "$SWARM_STATE" = "active" ]; then
    if confirm "Deseja subir a stack do AstraChat agora (docker stack deploy)?"; then
      dim "Arquivo da stack: caminho local ou URL."
      dim "Ex.: ./docker-compose.yml   ou   https://script.toky.top/astrachat-stack.yml"
      ask STACK_SRC "Arquivo da stack" "./docker-compose.yml"
      ask STACK_NAME "Nome da stack" "astrachat"

      STACK_FILE="$STACK_SRC"
      if printf '%s' "$STACK_SRC" | grep -qE '^https?://'; then
        STACK_FILE="${TMPDIR:-/tmp}/astrachat-stack.yml"
        info "Baixando a stack de ${STACK_SRC} ..."
        if curl -fsSL "$STACK_SRC" -o "$STACK_FILE" || wget -qO "$STACK_FILE" "$STACK_SRC"; then
          ok "Stack baixada."
        else
          warn "Falha ao baixar a stack."
          STACK_FILE=""
        fi
      fi

      if [ -n "$STACK_FILE" ] && [ -f "$STACK_FILE" ]; then
        info "docker stack deploy -c ${STACK_FILE} ${STACK_NAME}"
        if docker stack deploy -c "$STACK_FILE" "$STACK_NAME"; then
          ok "Stack '${STACK_NAME}' enviada. Aguardando serviços subirem..."
          for _ in $(seq 1 12); do
            sleep 5
            detect_astrachat
            if [ -n "$ASTRACHAT_SERVICES" ]; then break; fi
          done
          docker stack services "$STACK_NAME" 2>/dev/null || true
        else
          warn "Falha no docker stack deploy."
        fi
      else
        warn "Arquivo da stack não encontrado: ${STACK_SRC}"
      fi
    fi
  else
    dim "(Sem Swarm ativo não dá pra subir stack — suba o container manualmente.)"
  fi

  # 3) re-verificar
  dim ""
  read_line _ "Pressione ENTER p/ verificar de novo (ou 'sair'): "
  detect_astrachat
done
ok "AstraChat/Chatwoot instalado — encontrei:"
printf '%s\n' "$ASTRACHAT_SERVICES" | sed 's/^/    - /'
echo

# --- 2. imagem ---------------------------------------------------------------
title "2) Imagem"
dim "Imagem enterprise (multi-arch) que será aplicada no serviço."
ask TARGET_IMAGE "Imagem a aplicar" "edwardbra/astrachat:enterprise"
echo

# --- 3. serviço --------------------------------------------------------------
title "3) Serviço do Swarm"
if [ "$SWARM_STATE" = "active" ]; then
  # prefere o serviço da aplicação (exclui db/redis/proxy/worker)
  DETECTED="$(printf '%s\n' "$ASTRACHAT_SERVICES" | grep -viE 'postgres|redis|proxy|db|sidekiq|worker' | head -n1 || true)"
  if [ -z "$DETECTED" ]; then
    DETECTED="$(printf '%s\n' "$ASTRACHAT_SERVICES" | head -n1 || true)"
  fi
  if [ -n "$DETECTED" ]; then ok "Serviço da aplicação detectado: $DETECTED"; fi
  ask SERVICE "Nome do serviço" "${DETECTED:-astrachat_astrachat}"
else
  SERVICE=""
fi
echo

# --- 4. ação ----------------------------------------------------------------
title "4) O que fazer?"
dim "  update   = atualizar o serviço com a imagem (pull + rolling update)"
dim "  rollback = reverter o serviço para a revisão anterior"
dim ""
ask_choice ACTION "Ação" "update|rollback" "update"
echo

# --- 5. registry: só baixar (pull) ------------------------------------------
title "5) Registry: só BAIXAR (pull) — NÃO precisa de login"
dim "Não há build/push: a imagem é apenas baixada pelos nós do Swarm."
dim "  • Imagem PÚBLICA → baixa sem senha. Nada a fazer aqui."
dim "  • Imagem PRIVADA → os nós precisam de credencial; o script usa"
dim "    --with-registry-auth (reaproveita o login feito no manager)."
echo

# --- 6. unlock (rails runner) -----------------------------------------------
RUN_UNLOCK=0
WIDGET_SRC=""; WIDGET_KEY=""
if [ "$ACTION" = "update" ]; then
  title "6) Unlock do Chatwoot (roda DENTRO do container do Chatwoot)"
  dim "Aqui é a stack do CHATWOOT. O unlock aplica:"
  dim "  • trigger no PostgreSQL, override enterprise, All features, etc."
  dim ""

  if confirm "Rodar o unlock_permanent.rb agora?"; then
    RUN_UNLOCK=1
    dim "Fonte: espelho R2 com fallback pro GitHub."

    dim ""
    dim "--- Widget de chamadas: AstraCalls / WaCalls ---"
    dim "ATENÇÃO: AstraCalls/WaCalls é uma STACK SEPARADA do Chatwoot"
    dim "(ex.: serviços 'astracalls_wacalls', 'astracalls_proxy',"
    dim "'astracalls_postgres-wacalls'), com o environment dela:"
    dim "    WACALLS_PUBLIC_IP=auto"
    dim "    WACALLS_UDP_PORT=50000"
    dim "    WACALLS_MAX_CALLS=8"
    dim "    WACALLS_API_KEY=troque-esta-chave      # chave-mestra"
    dim "    WACALLS_PG_NAMESPACE=wacalls"
    dim "O widget.js é servido por ESSA stack; a chave vem do environment dela"
    dim "(use WACALLS_WIDGET_KEY, se existir; senão a WACALLS_API_KEY)."
    dim "Aqui só gravamos o <script> no Chatwoot apontando para essa stack."
    dim ""

    # a stack AstraCalls tem vários serviços: servidor, proxy (socat/Traefik) e postgres
    AC_SVCS="$(docker service ls --format '{{.Name}}' 2>/dev/null | grep -iE 'astracall|wacalls' || true)"
    AC_SERVER="$(printf '%s\n' "$AC_SVCS" | grep -viE 'postgres|proxy|socat' | head -n1 || true)"
    AC_PROXY="$(printf '%s\n' "$AC_SVCS" | grep -iE 'proxy|socat' | head -n1 || true)"
    if [ -n "$AC_SVCS" ]; then
      ok "Stack AstraCalls/WaCalls detectada (stack separada):"
      printf '%s\n' "$AC_SVCS" | sed 's/^/    - /'
    else
      dim "(Não achei serviços 'astracall/wacalls' no Swarm — informe a URL manualmente.)"
    fi

    # host público pelo label do Traefik no serviço proxy
    AC_HOST=""
    if [ -n "$AC_PROXY" ]; then
      AC_HOST="$(docker service inspect "$AC_PROXY" --format '{{json .Spec.Labels}}' 2>/dev/null | grep -oE 'Host\(`[^`]+`\)' | head -n1 | sed -E 's/Host\(`([^`]+)`\)/\1/' || true)"
    fi

    # chave do environment do servidor AstraCalls (widget > mestra)
    AC_KEY=""
    if [ -n "$AC_SERVER" ]; then
      AC_KEY="$(docker service inspect "$AC_SERVER" --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^WACALLS_WIDGET_KEY=' | head -n1 | cut -d= -f2- || true)"
      if [ -z "$AC_KEY" ]; then
        AC_KEY="$(docker service inspect "$AC_SERVER" --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^WACALLS_API_KEY=' | head -n1 | cut -d= -f2- || true)"
      fi
    fi

    if confirm "Injetar o widget do AstraCalls no dashboard (DASHBOARD_SCRIPTS)?"; then
      URL_DEF="https://seudominio.com.br/widget.js"
      if [ -n "$AC_HOST" ]; then
        URL_DEF="https://${AC_HOST}/widget.js"
        ok "Host público detectado no Traefik: $AC_HOST"
      fi
      ask WIDGET_SRC "URL do widget.js (da stack AstraCalls)" "$URL_DEF"
      dim "Chave: WACALLS_WIDGET_KEY (recomendada) ou WACALLS_API_KEY (mestra), da stack AstraCalls."
      ask_secret WIDGET_KEY "Chave do AstraCalls" "$AC_KEY"
    fi
  fi
  echo
fi

# --- 7. resumo ---------------------------------------------------------------
title "Resumo"
printf '  %-22s %s\n' "Ação:"          "$ACTION"
printf '  %-22s %s\n' "Imagem:"        "$TARGET_IMAGE"
if [ -n "$SERVICE" ]; then printf '  %-22s %s\n' "Serviço:" "$SERVICE"; fi
printf '  %-22s %s\n' "Rodar unlock:"  "$([ "$RUN_UNLOCK" = 1 ] && echo sim || echo não)"
if [ "$RUN_UNLOCK" = 1 ]; then printf '  %-22s %s\n' "Widget AstraCalls:" "$WIDGET_SRC"; fi
echo

confirm "Confirma e executa?" || die "Abortado pelo usuário."

# --- 8. execução -------------------------------------------------------------
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
  title "Rodando unlock_permanent.rb (dentro do container)"
  local cid
  cid="$(docker ps --filter "name=${SERVICE}." --filter status=running --format '{{.ID}}' 2>/dev/null | head -n1 || true)"
  [ -n "$cid" ] || { warn "Container não encontrado; unlock não executado."; return 0; }

  local url ran=0
  for url in "$UNLOCK_URL_R2" "$UNLOCK_URL_GH"; do
    info "Fonte: $url"
    # baixa no container (wget e, se falhar, curl); só executa se baixou
    if docker exec "$cid" sh -c "wget -qO /tmp/unlock.rb '$url' || curl -fsSL '$url' -o /tmp/unlock.rb"; then
      docker exec \
        -e ASTRACALLS_WIDGET_SRC="$WIDGET_SRC" \
        -e ASTRACALLS_WIDGET_KEY="$WIDGET_KEY" \
        "$cid" sh -c "bundle exec rails runner /tmp/unlock.rb" \
        || warn "unlock_permanent.rb retornou erro (veja a saída acima)."
      ran=1
      break
    fi
    warn "Não baixou de $url — tentando o próximo."
  done
  [ "$ran" = 1 ] || warn "Falha ao baixar o unlock_permanent.rb (R2 e GitHub)."
  echo
}

do_rollback() {
  [ -n "$SERVICE" ] || die "Serviço não definido."
  title "Rollback do serviço '$SERVICE'"
  docker service rollback "$SERVICE"
  echo
}

case "$ACTION" in
  update)   do_update; do_verify; do_unlock ;;
  rollback) do_rollback ;;
esac

title "Concluído"
ok "Tudo certo."
dim "Verifique na UI: Super Admin > Settings (plano) e App Config > internal (Dashboard Scripts)."
echo
progress_bar "Finalizando" 24
cleanup_self
echo
ok "Concluído. Até logo!"
