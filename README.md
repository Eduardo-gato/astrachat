# chatwoot-unlock

Script para desbloquear funcionalidades enterprise do Chatwoot, removendo limitações da versão community.

> **⚠️ PROJETO EDUCACIONAL** - Este projeto é destinado **exclusivamente para fins de estudo**. O uso deste software **infringe os termos de uso do Chatwoot** e é **por sua conta e risco**. Leia a seção [Aviso Legal](#️-aviso-legal-e-isenção-de-responsabilidade) antes de prosseguir.

## ⚡ Uso Rápido

### 📦 wget (dentro do container do Chatwoot)

O método mais direto. Execute **dentro do container/app** do Chatwoot (onde o `bundle exec rails` funciona):

```bash
wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
```

Se o container não tiver `wget`, use `curl`:

```bash
curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
```

Depois **reinicie o container** para o override enterprise entrar em vigor.

### 🐳 Docker/Portainer (Recomendado)

```bash
curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/docker-unlock.sh | bash
```

**📖 [Guia Completo Docker/Portainer](DOCKER.md)** - Inclui troubleshooting, métodos alternativos e instruções via Portainer Web UI

### 🧙 Assistente interativo (`apply-enterprise.sh`)

Para aplicar a imagem "enterprise" no Swarm de forma guiada (pergunta arquitetura, imagem, serviço, etc.):

Baixa e já executa (mantendo o terminal livre para as perguntas):

```bash
bash <(curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/apply-enterprise.sh)
```

Dica — crie um atalho e depois digite só `unlock`:

```bash
alias unlock='bash <(curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/apply-enterprise.sh)'
```

O assistente pergunta passo a passo (**amd64 / arm64 / both**), monta a imagem com
`buildx`, dá push, atualiza o serviço e — opcionalmente — roda o `unlock_permanent.rb`
dentro do container. Também oferece rollback.

> Rode num **manager do Swarm** com `docker` + `buildx`. Não use `curl -sL URL | bash`:
> o pipe consome o `stdin` e as perguntas travam.

### 🧩 Com o widget de chamadas (AstraCalls)

O widget é servido pelo **seu** servidor AstraCalls (não pelo Chatwoot). Defina a
URL e a chave **antes** de rodar para injetar o botão de telefone no dashboard
(via `DASHBOARD_SCRIPTS`):

```bash
export ASTRACALLS_WIDGET_SRC=https://seudominio.com.br/widget.js

# Recomendado: chave de widget (WACALLS_WIDGET_KEY) — escopo limitado
export ASTRACALLS_WIDGET_KEY=sua_widget_key

# Alternativa: chave-mestra (WACALLS_API_KEY) — acesso total, evite expor
# export ASTRACALLS_API_KEY=sua_api_key

wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
```

> **Sobre a chave (AstraCalls):**
> - `WACALLS_WIDGET_KEY` → chave de **widget** (recomendada): só resolve contato,
>   recebe eventos e opera chamadas. É a que fica visível no DOM/rede.
> - `WACALLS_API_KEY` → chave-**mestra**: acesso total (lista/apaga sessões, envia
>   mensagens). Use só se a de widget não estiver configurada.
>
> O script aceita `ASTRACALLS_WIDGET_KEY` **ou** `ASTRACALLS_API_KEY`.

**Vantagens:**
- ✅ Configurações **permanentes** que não resetam
- ✅ Trigger PostgreSQL protege contra alterações
- ✅ Plano `enterprise` forçado por override (prepend) após restart
- ✅ Todas as "All features" (EE) habilitadas nas contas
- ✅ Widget do AstraCalls (botão de telefone) no dashboard, via `DASHBOARD_SCRIPTS`

## 🎯 O que o script faz

**Proteção com Trigger PostgreSQL:**
- Cria função `force_enterprise_installation_configs()` no banco
- Cria trigger `trg_force_enterprise_configs` que intercepta INSERT/UPDATE
- Força valores enterprise automaticamente em **qualquer** tentativa de alteração
- Marca configurações como `locked = true`

**Configurações do Banco de Dados:**
- Define o plano como `enterprise`
- Configura limite de usuários para 9.999.999
- Remove alertas de limitação do Redis

**Atualização de Fallbacks:**
- Modifica `lib/chatwoot_hub.rb` (remove guards e atualiza valores padrão)
- Cria backup automático do arquivo original

**Override enterprise (prepend):**
- Sobrescreve `enterprise/lib/enterprise/chatwoot_hub.rb` forçando
  `pricing_plan = 'enterprise'` e `pricing_plan_quantity = 9_999_999`
- Passa por cima do wrapper `Kanban::License` que devolve `community`
- **Só vale após reiniciar o container** (o `prepend` é carregado no boot)

**Habilitação das "All features" (EE):**
- Liga todos os flags enterprise nas contas (`advanced_assignment`, `audit_logs`,
  `companies`, `custom_roles`, `saml`, `sla`, `channel_voice`, etc.)
- Feito via model (`Account#enable_features!`), já que no Super Admin os
  checkboxes vêm com `disabled="disabled"`

**Widget de chamadas (AstraCalls) — opcional:**
- Se `ASTRACALLS_WIDGET_SRC` e `ASTRACALLS_WIDGET_KEY` estiverem definidos, grava
  o `<script>` em `DASHBOARD_SCRIPTS` (`InstallationConfig`) e limpa o cache
- Adiciona o ícone de telefone nas conversas do dashboard

## 🔧 Funcionalidades Desbloqueadas

Após executar o script, seu Chatwoot terá:

- 🔓 **Usuários ilimitados** (9.999.999)
- 🏢 **Funcionalidades enterprise** ativadas
- ✨ **"All features" (EE) ligadas** nas contas (SLA, SAML, Audit Logs, Companies, Custom Roles, Voice Channel, etc.)
- 🚫 **Sem alertas** de limitação
- 💾 **Configurações persistentes**
- ☎️ **Widget de chamadas** (AstraCalls) no dashboard — opcional

## 📝 Detalhes Técnicos

### Arquivos e Componentes Modificados

- `installation_configs` (tabela PostgreSQL)
- Trigger `trg_force_enterprise_configs` (PostgreSQL)
- Função `force_enterprise_installation_configs()` (PostgreSQL)
- `lib/chatwoot_hub.rb` (fallbacks)
- `enterprise/lib/enterprise/chatwoot_hub.rb` (override `pricing_plan`)
- Feature flags das contas (`Account#feature_*` — "All features")
- `InstallationConfig` `DASHBOARD_SCRIPTS` (widget AstraCalls, opcional)
- Cache Redis (limpeza de alertas)

### Configurações Aplicadas
```ruby
INSTALLATION_PRICING_PLAN = 'enterprise'
INSTALLATION_PRICING_PLAN_QUANTITY = 9999999
```

### Trigger PostgreSQL

O trigger garante que qualquer tentativa de alterar as configurações será automaticamente revertida:

```sql
CREATE TRIGGER trg_force_enterprise_configs
BEFORE INSERT OR UPDATE ON installation_configs
FOR EACH ROW
EXECUTE FUNCTION force_enterprise_installation_configs();
```

### Backups Automáticos
O script cria backups automáticos antes de modificar arquivos:
```
lib/chatwoot_hub.rb.backup.YYYYMMDD_HHMMSS
```

## 🐳 Instalação Docker/Portainer

### Método 1: Script Automático (Recomendado)

No host onde o Docker está instalado:

```bash
curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/docker-unlock.sh | bash
```

O script detecta automaticamente o container do Chatwoot e executa o desbloqueio.

### Método 2: wget/curl via Docker CLI

```bash
# 1. Encontre o nome do container
docker ps | grep chatwoot

# 2. Execute o script no container (wget ou curl)
docker exec -it <NOME_DO_CONTAINER> bash -c "wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -"

# 3. Reinicie o container
docker restart <NOME_DO_CONTAINER>
```

Com o widget AstraCalls, passe as variáveis:

```bash
docker exec -it <NOME_DO_CONTAINER> bash -c "export ASTRACALLS_WIDGET_SRC=https://seudominio.com.br/widget.js ASTRACALLS_WIDGET_KEY=sua_widget_key && wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -"
```

### Método 3: Via Portainer Web UI

1. Acesse o Portainer
2. Vá em **Containers** → Selecione o container do Chatwoot
3. Clique em **>_ Console**
4. Selecione **Command: /bin/bash** e clique em **Connect**
5. Execute no terminal:
   ```bash
   wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
   ```
6. Volte aos containers e clique em **Restart** no container do Chatwoot

### Método 4: Imagem "baked" (permanente no Docker Swarm)

No Swarm o patch em arquivo se perde num reschedule. Para fixar de verdade, faça
um build da imagem com os patches aplicados (`Dockerfile.bake` + `patches/`) e
atualize o serviço:

```bash
docker build -f Dockerfile.bake -t <SEU_REGISTRY>/astrachat:enterprise .
docker push <SEU_REGISTRY>/astrachat:enterprise
docker service update --image <SEU_REGISTRY>/astrachat:enterprise <SERVICO_APP>
```

## 🐳 Compatibilidade

- ✅ Container Docker do Chatwoot
- ✅ Docker Compose
- ✅ Portainer / Portainer CE
- ✅ Instalações Rails padrão
- ✅ Versões recentes do Chatwoot

## ⚠️ AVISO LEGAL E ISENÇÃO DE RESPONSABILIDADE

**⚠️ LEIA ATENTAMENTE ANTES DE USAR ⚠️**

### 🔴 Uso por Conta e Risco

- Este projeto é fornecido **"COMO ESTÁ"**, sem garantias de qualquer tipo
- O uso deste software é **inteiramente por sua conta e risco**
- Os desenvolvedores **NÃO se responsabilizam** por qualquer dano, perda de dados, problemas legais ou consequências decorrentes do uso

### 📚 Finalidade Educacional

- Este projeto foi desenvolvido **exclusivamente para fins educacionais e de estudo**
- Destinado ao aprendizado de Ruby, PostgreSQL, triggers e administração de sistemas
- **NÃO é recomendado para uso em ambientes de produção**

### ⚖️ Violação dos Termos de Uso

- Esta ferramenta **modifica e contorna limitações comerciais** do Chatwoot
- O uso deste script **INFRINGE os Termos de Serviço** do Chatwoot
- Pode violar direitos de propriedade intelectual e licenças de software
- **Use apenas em ambientes de testes/desenvolvimento isolados**

### 🚫 Responsabilidades

**O usuário é o único responsável por:**
- Verificar a legalidade do uso em sua jurisdição
- Respeitar os termos de licença do Chatwoot
- Arcar com quaisquer consequências legais
- Problemas técnicos causados pela modificação

### ✅ Recomendação Oficial

**Para uso comercial legítimo:**
- Adquira uma licença Enterprise oficial do Chatwoot
- Visite: [https://www.chatwoot.com/pricing](https://www.chatwoot.com/pricing)
- Suporte o desenvolvimento de software open-source

---

**Ao usar este software, você concorda que leu, entendeu e aceita todos os termos acima.**

## 🔄 Após a Execução

1. **Reinicie o container** do Chatwoot (obrigatório para o override `prepend`)
2. Acesse a interface web
3. Verifique o plano e as features:

```bash
# plano enterprise e limite
DISABLE_SPRING=1 bundle exec rails runner "puts ChatwootHub.pricing_plan; puts ChatwootHub.pricing_plan_quantity"

# features EE de uma conta
DISABLE_SPRING=1 bundle exec rails runner "a=Account.find(1); p a.enabled_features.slice('companies','saml','sla','channel_voice','audit_logs')"
```

Esperado: `enterprise` / `9999999` e as features EE como `true`.

> **Widget AstraCalls:** o ícone de telefone aparece nas conversas do inbox
> configurado. Ele exige um **microfone** no navegador do agente — sem dispositivo
> de áudio o widget retorna `Requested device not found`.

## 🛡️ Como funciona a proteção permanente?

A versão permanente usa **triggers do PostgreSQL** que interceptam qualquer operação de INSERT ou UPDATE na tabela `installation_configs`:

1. **Trigger ativo 24/7**: Monitora modificações na tabela
2. **Reescrita automática**: Qualquer valor diferente de `enterprise` é automaticamente sobrescrito
3. **Lock de configuração**: Marca registros como `locked = true`
4. **Persistência garantida**: Mesmo reinícios ou atualizações do Chatwoot não removem o trigger

**Exemplo prático:**
```sql
-- Alguém tenta alterar para 'community'
UPDATE installation_configs SET value = 'community' WHERE name = 'INSTALLATION_PRICING_PLAN';

-- O trigger intercepta e força de volta para 'enterprise'
-- Resultado final: value = 'enterprise' ✅
```

## 🗑️ Como remover o desbloqueio permanente?

Se precisar reverter as mudanças permanentes:

```sql
-- Remover trigger
DROP TRIGGER IF EXISTS trg_force_enterprise_configs ON installation_configs;

-- Remover função
DROP FUNCTION IF EXISTS force_enterprise_installation_configs();

-- Restaurar valores originais
UPDATE installation_configs
SET serialized_value = to_jsonb(E'--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: community\n'::text),
    locked = false
WHERE name = 'INSTALLATION_PRICING_PLAN';

UPDATE installation_configs
SET serialized_value = to_jsonb(E'--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: 0\n'::text),
    locked = false
WHERE name = 'INSTALLATION_PRICING_PLAN_QUANTITY';
```

## 👨‍💻 Projeto

**chatwoot-unlock** - Projeto educacional open-source

---

### 🌟 Repositório: [Eduardo-gato/astrachat](https://github.com/Eduardo-gato/astrachat)
