# 🐳 Guia Rápido - Docker & Portainer

## ⚡ Início Rápido (1 comando)

```bash
curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/docker-unlock.sh | bash
```

**Pronto!** O script detecta automaticamente seu container e aplica o desbloqueio permanente.

---

## 📋 Passo a Passo - Portainer Web UI

### Opção 1: Via Console do Container (Mais Fácil)

1. **Acesse o Portainer** → Entre no seu painel
2. **Containers** → Clique no container do Chatwoot
3. **Console** → Clique no ícone `>_`
4. **Connect** → Selecione `/bin/bash` e clique em **Connect**
5. **Cole e execute:**
   ```bash
   wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
   ```
6. **Restart** → Volte para a lista de containers e reinicie o Chatwoot

### Opção 2: Via Exec Console

1. **Containers** → Selecione o container do Chatwoot
2. **Quick actions** → Clique em **Exec Console**
3. **Cole e execute:**
   ```bash
   wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
   ```
4. **Restart** o container

---

## 🖥️ Linha de Comando (SSH/Terminal)

### Se você tem acesso SSH ao servidor:

```bash
# 1. Liste os containers
docker ps

# 2. Execute o desbloqueio (substitua CONTAINER_NAME)
docker exec -it CONTAINER_NAME bash -c "wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -"

# 3. Reinicie
docker restart CONTAINER_NAME
```

### Exemplo com nome comum de container:

```bash
docker exec -it chatwoot bash -c "wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -"
docker restart chatwoot
```

---

## 🔍 Como encontrar o nome do container?

### Via Docker CLI:
```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i chatwoot
```

### Via Portainer:
1. **Containers** → Veja a lista
2. Procure por container com imagem `chatwoot/chatwoot`

### Nomes comuns:
- `chatwoot`
- `chatwoot-web`
- `chatwoot_web`
- `chatwoot_chatwoot_1`
- `stack_chatwoot_1`

---

## 🗄️ Método Alternativo: SQL Direto no PostgreSQL

Se você prefere trabalhar diretamente no banco de dados:

### Via Docker CLI:

```bash
# 1. Baixe o script SQL
wget https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.sql

# 2. Execute no PostgreSQL (ajuste o nome do container)
docker exec -i postgres psql -U postgres -d chatwoot_production < unlock_permanent.sql
```

### Via Portainer (PostgreSQL Console):

1. Abra o console do container **PostgreSQL**
2. Execute:
   ```bash
   psql -U postgres -d chatwoot_production
   ```
3. Cole o conteúdo de `unlock_permanent.sql`

**⚠️ Importante:** Este método só cria o trigger no banco. Você ainda precisa:
- Atualizar o arquivo `chatwoot_hub.rb` no container do Chatwoot
- Limpar o cache Redis

**Recomendação:** Use o método Ruby (`unlock_permanent.rb`) que faz tudo automaticamente.

---

## 🔄 Após a Execução

### Reiniciar o container:

**Via Portainer:**
- Containers → Selecione o Chatwoot → **Restart**

**Via Docker CLI:**
```bash
docker restart chatwoot
```

**Via Docker Compose:**
```bash
docker-compose restart chatwoot
```

### Verificar se funcionou:

1. Aguarde ~30 segundos após o restart
2. Acesse a interface web do Chatwoot
3. Vá em **Settings** → **Account**
4. Verifique se não há limitações de usuários
5. Recursos enterprise devem estar disponíveis

---

## ❓ Troubleshooting

### "Container não encontrado"
- Verifique se o container está rodando: `docker ps`
- Tente listar todos os containers: `docker ps -a`
- Use o nome exato do container

### "wget: command not found"
```bash
# Use curl ao invés de wget
docker exec -it CONTAINER bash -c "curl -sL https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -"
```

### "bundle: command not found"
- Você está no container errado
- Certifique-se de estar no container do **Chatwoot**, não do PostgreSQL ou Redis

### Permissões negadas
```bash
# Tente sem -it se estiver em script automatizado
docker exec CONTAINER bash -c "wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -"
```

### Configurações voltaram ao normal
- O trigger PostgreSQL pode não ter sido criado
- Execute novamente o script
- Verifique se o trigger existe:
  ```bash
  docker exec -it postgres psql -U postgres -d chatwoot_production -c "SELECT tgname FROM pg_trigger WHERE tgname = 'trg_force_enterprise_configs';"
  ```

---

## 🛡️ Garantia de Persistência

Após executar o `unlock_permanent.rb`, as configurações são **permanentes** porque:

✅ **Trigger PostgreSQL ativo** - Bloqueia alterações na tabela
✅ **Configurações locked** - Marcadas como bloqueadas no Rails
✅ **Sobrevive a restarts** - Persiste após reiniciar containers
✅ **Sobrevive a updates** - Persiste após atualizar o Chatwoot

**Único cenário que remove:** Recriar o banco de dados do zero ou executar o script de remoção.

---

## 💡 Dicas

- **Backup antes:** Se quiser, faça backup do banco antes de executar
- **Teste em staging:** Se possível, teste primeiro em um ambiente de teste
- **Monitore logs:** Acompanhe os logs do container durante a execução
- **Script automático:** Use o `docker-unlock.sh` para automação completa

---

## 🌟 Suporte

Problemas ou dúvidas? Abra uma issue no repositório:
[github.com/Eduardo-gato/astrachat/issues](https://github.com/Eduardo-gato/astrachat/issues)
