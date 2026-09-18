# chatwoot-unlock

Script para desbloquear funcionalidades enterprise do Chatwoot, removendo limitações da versão community.

> **⚠️ PROJETO EDUCACIONAL** - Este projeto é destinado **exclusivamente para fins de estudo**. O uso deste software **infringe os termos de uso do Chatwoot** e é **por sua conta e risco**. Leia a seção [Aviso Legal](#️-aviso-legal-e-isenção-de-responsabilidade) antes de prosseguir.

## ⚡ Uso Rápido

### 🐳 Docker/Portainer (Recomendado)

```bash
curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/docker-unlock.sh | bash
```

**📖 [Guia Completo Docker/Portainer](DOCKER.md)** - Inclui troubleshooting, métodos alternativos e instruções via Portainer Web UI

### 📦 Instalação Tradicional

Execute diretamente no container/servidor do Chatwoot:

```bash
wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
```

**Vantagens:**
- ✅ Configurações **permanentes** que não resetam
- ✅ Trigger PostgreSQL protege contra alterações
- ✅ Configurações marcadas como `locked`
- ✅ Proteção automática contra reversão

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
- Modifica `lib/chatwoot_hub.rb`
- Cria backup automático do arquivo original
- Atualiza valores padrão para enterprise

## 🔧 Funcionalidades Desbloqueadas

Após executar o script, seu Chatwoot terá:

- 🔓 **Usuários ilimitados** (9.999.999)
- 🏢 **Funcionalidades enterprise** ativadas
- 🚫 **Sem alertas** de limitação
- 💾 **Configurações persistentes**

## 📝 Detalhes Técnicos

### Arquivos e Componentes Modificados

- `installation_configs` (tabela PostgreSQL)
- Trigger `trg_force_enterprise_configs` (PostgreSQL)
- Função `force_enterprise_installation_configs()` (PostgreSQL)
- `lib/chatwoot_hub.rb` (fallbacks)
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

### Método 2: Manual via Docker CLI

```bash
# 1. Encontre o nome do container
docker ps | grep chatwoot

# 2. Execute o script no container
docker exec -it <NOME_DO_CONTAINER> bash -c "wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -"

# 3. Reinicie o container
docker restart <NOME_DO_CONTAINER>
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

### Método 4: SQL Direto no PostgreSQL

Se preferir executar SQL diretamente no banco de dados:

```bash
# 1. Conecte ao container do PostgreSQL
docker exec -it <CONTAINER_POSTGRES> psql -U postgres -d chatwoot_production

# 2. Execute o script SQL
\i unlock_permanent.sql
```

Ou baixe e execute:
```bash
wget https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.sql
docker exec -i <CONTAINER_POSTGRES> psql -U postgres -d chatwoot_production < unlock_permanent.sql
```

**⚠️ Nota:** Este método só cria o trigger. Você ainda precisa atualizar o `chatwoot_hub.rb` manualmente no container do Chatwoot.

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

1. Reinicie o container do Chatwoot
2. Acesse a interface web
3. Verifique se as limitações foram removidas

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
