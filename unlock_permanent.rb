#!/usr/bin/env ruby

# astrachat - Script PERMANENTE para Chatwoot Enterprise (Swarm/Portainer)
# Execute dentro do container app (astrachat_astrachat):
# wget -qO- https://raw.githubusercontent.com/Eduardo-gato/astrachat/main/unlock_permanent.rb | bundle exec rails runner -
# Compatível com pipe via stdin (rails runner -). Não usa ARGV nem __FILE__.

require 'fileutils'

puts "🚀 === chatwoot-unlock - Desbloqueio PERMANENTE do Chatwoot Enterprise ==="
puts ""

# SQL para criar trigger permanente
# Nota: usa E'...\n' (escape string syntax do PostgreSQL) para garantir
# que \n seja interpretado como newline real, compatível com o formato
# YAML serializado pelo Rails (ActiveRecord::Coders::YAMLColumn).
sql_function = <<-SQL
-- Função que força valores enterprise
CREATE OR REPLACE FUNCTION force_enterprise_installation_configs()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.name = 'INSTALLATION_PRICING_PLAN' THEN
        NEW.serialized_value = to_jsonb(E'--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: enterprise\n'::text);
        NEW.locked = true;
    END IF;

    IF NEW.name = 'INSTALLATION_PRICING_PLAN_QUANTITY' THEN
        NEW.serialized_value = to_jsonb(E'--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: 9999999\n'::text);
        NEW.locked = true;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
SQL

sql_drop = "DROP TRIGGER IF EXISTS trg_force_enterprise_configs ON installation_configs;"

sql_create = <<-SQL
CREATE TRIGGER trg_force_enterprise_configs
BEFORE INSERT OR UPDATE ON installation_configs
FOR EACH ROW
EXECUTE FUNCTION force_enterprise_installation_configs();
SQL

begin
  puts "📊 Aplicando trigger permanente no PostgreSQL..."

  # Executa separadamente: pg adapter não aceita multi-statement em um único execute
  ActiveRecord::Base.connection.execute(sql_function)
  ActiveRecord::Base.connection.execute(sql_drop)
  ActiveRecord::Base.connection.execute(sql_create)

  puts "✅ Trigger criado com sucesso!"
  puts "   • Função: force_enterprise_installation_configs()"
  puts "   • Trigger: trg_force_enterprise_configs"
  puts ""

rescue => e
  puts "❌ Erro ao criar trigger: #{e.message}"
  puts "   Tentando método alternativo..."
  puts ""
end

# Atualiza registros atuais
begin
  puts "💾 Atualizando configurações no banco de dados..."

  plan = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
  plan.value = 'enterprise'
  plan.locked = true
  plan.save!
  puts "✅ Plano enterprise configurado e bloqueado"

  quantity = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')
  quantity.value = 9_999_999
  quantity.locked = true
  quantity.save!
  puts "✅ Quantidade de usuários configurada e bloqueada (9.999.999)"
  puts ""

rescue => e
  puts "❌ Erro nas configurações do banco: #{e.message}"
  puts ""
end

# Limpa cache Redis
begin
  if defined?(Redis::Alfred)
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
    puts '✅ Flag de alerta premium removida do Redis'
  end
rescue => e
  puts "⚠️  Erro ao limpar Redis: #{e.message}"
end

# Atualiza fallback em lib/chatwoot_hub.rb
begin
  possible_paths = [
    '/app/lib/chatwoot_hub.rb',
    '/chatwoot/lib/chatwoot_hub.rb',
    File.join(Rails.root, 'lib', 'chatwoot_hub.rb'),
    './lib/chatwoot_hub.rb'
  ]

  hub_file = possible_paths.find { |path| File.exist?(path) }

  if hub_file
    puts "📁 Arquivo encontrado: #{hub_file}"

    # Backup
    backup_file = "#{hub_file}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    FileUtils.cp(hub_file, backup_file)
    puts "💾 Backup: #{backup_file}"

    # Ler e atualizar conteúdo
    content = File.read(hub_file)
    original = content.dup

    # 1. Remove guards "return ... unless ChatwootApp.enterprise?"
    # Crítico na v4.17.1: sem isso o método retorna community/0 antes de ler o banco,
    # pois a imagem community não tem a pasta enterprise/ e enterprise? é falso.
    content.gsub!(
      /^\s*return\s+['"]community['"]\s+unless\s+ChatwootApp\.enterprise\?.*$/,
      "    # astrachat patch: guard enterprise removido"
    )

    content.gsub!(
      /^\s*return\s+0\s+unless\s+ChatwootApp\.enterprise\?.*$/,
      "    # astrachat patch: guard enterprise removido"
    )

    # 2. Atualiza fallbacks (forma de bloco para evitar ambiguidade \1 + dígitos)
    content.gsub!(
      /(InstallationConfig\.find_by\(name:\s*['"]INSTALLATION_PRICING_PLAN['"]\)&?\.value\s*\|\|\s*)['"]community['"]/
    ) { "#{$1}'enterprise'" }

    content.gsub!(
      /(InstallationConfig\.find_by\(name:\s*['"]INSTALLATION_PRICING_PLAN_QUANTITY['"]\)&?\.value\s*\|\|\s*)0/
    ) { "#{$1}9999999" }

    if content != original
      File.write(hub_file, content)
      puts "✅ Fallbacks atualizados em #{hub_file}"
    else
      puts "ℹ️  Arquivo já estava atualizado"
    end
    puts ""
  end

rescue => e
  puts "⚠️  Erro ao atualizar arquivo: #{e.message}"
  puts ""
end

# Override enterprise (passa por cima do wrapper Kanban::License via prepend).
# Sem isso o pricing_plan continua 'community' mesmo com DB=enterprise,
# pois force_enterprise_plan.rb define: active? ? enterprise : community.
begin
  ent_hub = File.join(Rails.root, 'enterprise', 'lib', 'enterprise', 'chatwoot_hub.rb')

  enterprise_patch = <<-RUBY
module Enterprise::ChatwootHub
  ENTERPRISE_BASE_URL = 'https://hub.2.chatwoot.com'.freeze

  def base_url
    return ENV.fetch('CHATWOOT_HUB_URL', ENTERPRISE_BASE_URL) if Rails.env.development?

    ENTERPRISE_BASE_URL
  end

  # AstraChat live patch: força enterprise (bypassa Kanban::License.active?)
  def pricing_plan
    'enterprise'
  end

  def pricing_plan_quantity
    9_999_999
  end
end
  RUBY

  if File.exist?(ent_hub)
    backup_ent = "#{ent_hub}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    FileUtils.cp(ent_hub, backup_ent)
    puts "💾 Backup enterprise: #{backup_ent}"
    File.write(ent_hub, enterprise_patch)
    puts "✅ Override enterprise aplicado em #{ent_hub}"
    puts "🔄 Reinicie o container: o prepend só vale após o boot"
  else
    puts "ℹ️  Override enterprise pulado (sem pasta enterprise/)"
  end
  puts ""

rescue => e
  puts "⚠️  Erro no override enterprise: #{e.message}"
  puts ""
end

# Habilita TODAS as features "All features" (EE) em todas as contas.
# Essas flags ficam nos bit flags do Account (Featurable/FlagShihTzu), não no
# InstallationConfig. No Super Admin os checkboxes vêm com disabled="disabled"
# (gate de licença), então só dá para ligar via model.
begin
  puts "✨ Habilitando features enterprise (All features) nas contas..."

  ee_features = %w[
    advanced_assignment advanced_search audit_logs csat_review_notes
    captain_integration captain_document_auto_sync captain_integration_v2
    companies custom_roles custom_tools disable_branding
    conversation_required_attributes saml sla channel_voice
  ]

  Account.find_each do |account|
    applied = []
    ee_features.each do |name|
      setter = "feature_#{name}="
      next unless account.respond_to?(setter)

      account.public_send(setter, true)
      applied << name
    end

    next if applied.empty?

    account.save!
    puts "   • Conta #{account.id} (#{account.name}): #{applied.size} features habilitadas"
  end

  puts "✅ Features enterprise aplicadas"
  puts ""

rescue => e
  puts "⚠️  Erro ao habilitar features enterprise: #{e.message}"
  puts ""
end

# Injeta o widget do AstraCalls (botão de telefone na conversa) via DASHBOARD_SCRIPTS.
# O widget é servido pelo servidor AstraCalls, não pelo Chatwoot:
#   <script src="https://SEU-ASTRACALLS/widget.js" data-api-key="WACALLS_WIDGET_KEY"></script>
# DASHBOARD_SCRIPTS é uma InstallationConfig "locked" e o App Config > internal
# só aparece em plano enterprise — então gravamos direto no model.
# Configure nas variáveis do serviço:
#   ASTRACALLS_WIDGET_SRC=https://call.toky.top/widget.js
#   ASTRACALLS_WIDGET_KEY=<WACALLS_WIDGET_KEY>
begin
  puts "🧩 Configurando DASHBOARD_SCRIPTS (widget AstraCalls)..."

  widget_src = ENV['ASTRACALLS_WIDGET_SRC']
  widget_key = ENV['ASTRACALLS_WIDGET_KEY']

  if widget_src.present? && widget_key.present?
    script = %(<script src="#{widget_src}" data-api-key="#{widget_key}"></script>)

    config = InstallationConfig.where(name: 'DASHBOARD_SCRIPTS').first_or_initialize
    config.value = script
    config.locked = false
    config.save!

    GlobalConfig.clear_cache
    puts "   • Widget AstraCalls injetado no dashboard (#{widget_src})"
    puts "✅ DASHBOARD_SCRIPTS aplicado"
  else
    puts "ℹ️  Defina ASTRACALLS_WIDGET_SRC e ASTRACALLS_WIDGET_KEY — DASHBOARD_SCRIPTS não alterado"
  end
  puts ""

rescue => e
  puts "⚠️  Erro ao configurar DASHBOARD_SCRIPTS: #{e.message}"
  puts ""
end

# Verifica configurações finais
begin
  puts "🔍 Verificando configurações aplicadas:"

  configs = InstallationConfig.where(name: ['INSTALLATION_PRICING_PLAN', 'INSTALLATION_PRICING_PLAN_QUANTITY'])

  configs.each do |config|
    puts "   • #{config.name}: #{config.value} (locked: #{config.locked || false})"
  end

  # Verifica se o trigger existe
  # pg retorna 't'/'f' como string, ambas truthy em Ruby — comparar explicitamente
  trigger_check = ActiveRecord::Base.connection.execute(
    "SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_force_enterprise_configs') as exists"
  ).first

  trigger_val = trigger_check && trigger_check['exists']
  trigger_active = (trigger_val == true || trigger_val == 't' || trigger_val == 'true' || trigger_val == 1 || trigger_val == '1')

  if trigger_active
    puts "   • Trigger PostgreSQL: ✅ ATIVO"
  else
    puts "   • Trigger PostgreSQL: ⚠️  Não detectado"
  end

  # Status do wrapper (só vale após restart: prepend é carregado no boot)
  begin
    loc = ChatwootHub.method(:pricing_plan).source_location.inspect
    puts "   • pricing_plan em: #{loc}"
  rescue => e
    puts "   • pricing_plan em: ? (#{e.message})"
  end

  begin
    if ChatwootHub.respond_to?(:pricing_plan_without_license)
      puts "   • base (without_license): #{ChatwootHub.pricing_plan_without_license.inspect}"
    end
    puts "   • atual (neste processo, pré-restart): #{ChatwootHub.pricing_plan.inspect}"
  rescue => e
    puts "   • pricing atual: ? (#{e.message})"
  end

  begin
    puts "   • Kanban::License.active?: #{Kanban::License.active?.inspect}"
  rescue
    puts "   • Kanban::License: ausente"
  end

  begin
    Account.find_each do |account|
      enabled = %w[advanced_assignment audit_logs companies custom_roles saml sla channel_voice].select do |name|
        account.respond_to?("feature_#{name}?") && account.public_send("feature_#{name}?")
      end
      puts "   • Conta #{account.id} features EE ativas: #{enabled.size}/#{%w[advanced_assignment audit_logs companies custom_roles saml sla channel_voice].size} (#{enabled.join(', ')})"
    end
  rescue => e
    puts "   • Features EE: ? (#{e.message})"
  end

rescue => e
  puts "⚠️  Erro ao verificar: #{e.message}"
end

puts ""
puts "🎉 === Desbloqueio PERMANENTE concluído ==="
puts ""
puts "🔒 PROTEÇÃO ATIVA:"
puts "   • Trigger PostgreSQL monitora e força valores enterprise"
puts "   • Qualquer tentativa de alterar será revertida automaticamente"
puts "   • Configurações marcadas como 'locked'"
puts "   • Override enterprise (prepend) força enterprise após o restart"
puts "   • All features (EE) habilitadas em todas as contas"
puts ""
puts "🔄 Reinicie o container para aplicar todas as mudanças"
puts "   Depois: DISABLE_SPRING=1 bundle exec rails runner \"puts ChatwootHub.pricing_plan\""
puts "🌟 chatwoot-unlock - Educational Project"
puts ""
