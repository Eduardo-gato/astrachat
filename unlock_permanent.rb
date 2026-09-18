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
puts ""
puts "🔄 Reinicie o container para aplicar todas as mudanças"
puts "🌟 chatwoot-unlock - Educational Project"
puts ""
