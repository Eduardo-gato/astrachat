# Automação do desbloqueio AstraChat — especificação do script shell

> Este `.md` NÃO é o script. É o blueprint para criar depois um `astra-unlock.sh`
> que execute tudo de ponta a ponta sem intervenção manual.

## 1. Objetivo

Um único shell que, rodado no **manager Swarm via SSH**, deixe o serviço
`astrachat_astrachat` em `enterprise / 9999999` de forma **permanente**
(imagem bakeda) + blindagem de banco (trigger), com verificação e rollback.

## 2. Onde cada parte roda (não misturar)

| Etapa | Onde roda | Por quê |
|---|---|---|
| `docker build/push/service update` | Manager (SSH, com `docker` + `git`) | Só o daemon tem acesso ao build e ao Swarm |
| `rails runner` (trigger, DB, patches live) | Dentro do container app (via `docker exec` ou Console) | Precisa do Rails/DB/arquivos `/app` |
| Verificação UI | Navegador | Confirma agentes/features |

O shell futuro deve detectar onde está (dentro do container vs manager) e
abortar com mensagem clara se for o contexto errado.

## 3. Pré-requisitos que o script deve checar antes de tudo

1. `docker info` acessível (se `permission denied` no `docker.sock`, instruir `sudo` ou `usermod -aG docker`).
2. `git` instalado (para clonar `Eduardo-gato/astrachat@main`).
3. `docker login` válido no registry de destino (ex: `edwardbra`). Sem isso o `push` dá `denied`.
4. Serviço existe: `docker service inspect astrachat_astrachat`.
5. Imagem base resolvível: `astraonline/astrachat:latest` (ou digest pinnado do Portainer).
6. Branch/paths no repo: `Dockerfile.bake`, `patches/chatwoot_hub.rb`,
   `patches/check_new_versions_job.rb`,
   `patches/reconcile_plan_config_service.rb`, `unlock_permanent.rb`.

Qualquer check falho → `exit 1` com mensagem (usar `set -euo pipefail`).

## 4. Variáveis de entrada (parametrizar, sem hardcode)

- `REPO_URL=https://github.com/Eduardo-gato/astrachat.git`
- `REPO_REF=main`
- `SERVICE_APP=astrachat_astrachat`
- `SERVICE_SIDEKIQ=` (vazio se não existir; descobrir via `docker service ls`)
- `BASE_IMAGE=astraonline/astrachat:latest`
- `TARGET_IMAGE=edwardbra/astrachat:enterprise`
- `BUILD_DIR=/opt/astrachat-build`
- `REGISTRY_AUTH=1` (usa `--with-registry-auth` no update se registry privado)

## 5. Fluxo que o shell deve implementar (nesta ordem)

### Fase A — Preparar build (manager)

1. `rm -rf "$BUILD_DIR" && git clone --branch "$REPO_REF" "$REPO_URL" "$BUILD_DIR"`
2. Validar que os 5 arquivos existem no clone (falhar se `Dockerfile.bake` ou `patches/` ausentes — foi o 404 que já nos pegou).
3. (Opcional) pinnar `FROM` no `Dockerfile.bake` para o digest atual do serviço, para rebuilds reproduzíveis.
4. `docker build -f Dockerfile.bake -t "$TARGET_IMAGE" "$BUILD_DIR"`
5. `docker push "$TARGET_IMAGE"` (pular apenas se single-node documentado + flag explícita `--local-only`).

### Fase B — Atualizar serviço (manager)

6. `docker service update --image "$TARGET_IMAGE" ${REGISTRY_AUTH:+--with-registry-auth} "$SERVICE_APP"`
7. Aguardar convergência: `docker service ps` até 1/1 Running na nova imagem (timeout ~5 min). Se falhar, `docker service rollback` + exit 1.
8. Repetir 6–7 para o sidekiq **se existir**.

### Fase C — Blindagem de banco + patch live (dentro do app)

9. Localizar task Running atual: `docker ps --filter name=${SERVICE_APP}` (cuidado: podem existir tasks Shutdown antigas — filtrar `Up`).
10. `docker exec <APP_ID> sh -c 'wget -qO- <raw>/unlock_permanent.rb | bundle exec rails runner -'`
    - Fallback para `curl -sL` se `wget` 404/falhar.
    - O script já faz: trigger (3 `execute` separados), `InstallationConfig`, Redis, patch `lib/chatwoot_hub.rb`, override `enterprise/.../chatwoot_hub.rb`, backups timestampados.
11. Restart da task para o `prepend` valer no boot (o `service update` da Fase B já reinicia; se a Fase C rodar depois, reiniciar de novo via `docker service update --force` ou restart do container).

### Fase D — Verificação (manager + container)

12. `docker exec <APP_ID> sh -c 'DISABLE_SPRING=1 bundle exec rails runner "puts ChatwootHub.pricing_plan; puts ChatwootHub.pricing_plan_quantity; puts Kanban::License.active?.inspect"'`
    - Esperado: `enterprise / 9999999 / false`.
    - Se `community`: checar `source_location` (deve ser o override enterprise, não o initializer), e se a task é a nova (imagem `edwardbra`, não `astraonline`).
13. Checar trigger: query `pg_trigger trg_force_enterprise_configs` = existe.
14. Smoke UI: login, Settings > Agents (criar agente teste), Super Admin sem erro.

### Fase E — Auditoria

15. Logar: imagem antiga/nova (digests), backups criados (`*.backup.*`), `service ps`, saída da verificação.
16. Nunca logar segredos (`POSTGRES_PASSWORD`, token de licença). `meu-astra.txt` jamais entra no repo/imagem.

## 6. Rollback que o script deve suportar

- `rollback`: `docker service rollback "$SERVICE_APP"` (+ sidekiq).
- Restaurar `chatwoot_hub.rb` a partir do `*.backup.*` mais recente dentro do container.
- Remover trigger se pedido explícito (SQL `DROP TRIGGER/FUNCTION` + `UPDATE installation_configs` para `community/0`) — documentar que isso **religa** o bloqueio da licença.

## 7. Armadilhas conhecidas (não repetir)

- `docker exec -it` quebra em pipe/não-TTY → no script usar sem `-it`.
- BusyBox no container: `grep --include` e `find -maxdepth` podem não existir → usar formas portáveis.
- `raw.githubusercontent` dá 404 por cache logo após push → o script deve validar via API (`api.github.com/.../contents/...`) ou retry com espera.
- Push `denied` = namespace errado (`eduardo-gato` vs `edwardbra`) ou sem `docker login`.
- `permission denied` no `docker.sock` = usuário fora do grupo `docker` → `sudo`/`newgrp`.
- Terminal ≠ Portainer: task IDs mudam após update; sempre re-resolver o container Running, nunca fixar ID.
- `premium` x `enterprise`: o check de cota de agentes só trava em `premium`. Manter `enterprise` no override.
- Páginas quebradas pós-update: primeiro ver `service logs` + hard refresh, antes de culpar o patch.

## 8. Critérios de pronto do futuro `astra-unlock.sh`

- [ ] Roda com um comando só no manager, sem editar código.
- [ ] Falha rápido com mensagem acionável em cada pré-requisito.
- [ ] Gera imagem tagueada com digest impresso no log.
- [ ] Verificação final imprime `enterprise / 9999999` ou sai 1.
- [ ] `--dry-run` mostra o que faria sem executar.
- [ ] `--rollback` reverte serviço + arquivos.
- [ ] Nenhum segredo no repo, no log ou na imagem.
