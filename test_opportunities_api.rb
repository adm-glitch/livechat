# frozen_string_literal: true

# Script para testar Opportunities API no Rails Console
# Execute: load 'test_opportunities_api.rb'
# OU no console interativo: load 'test_opportunities_api.rb'

puts '=' * 60
puts 'TESTE DA API DE OPPORTUNITIES'
puts '=' * 60

# Verificar se estamos no console interativo (com app helper)
def in_console?
  defined?(app) && app.respond_to?(:get)
rescue NameError
  false
end

# 1. Criar ou buscar account
account = Account.first
if account.nil?
  puts 'Criando account...'
  account = Account.create!(name: 'Test Account')
  puts "✓ Account criado: #{account.id}"
else
  puts "✓ Account encontrado: #{account.id} - #{account.name}"
end

# 2. Criar ou buscar user
user = account.users.first
if user.nil?
  puts 'Criando user...'
  user = User.create!(
    email: 'admin@test.com',
    password: 'Password1!',
    name: 'Admin User'
  )
  user.skip_confirmation!
  user.save!
  # Vincular user ao account através de AccountUser
  AccountUser.create!(
    account: account,
    user: user,
    role: :administrator
  )
  puts "✓ User criado: #{user.id} - #{user.email}"
else
  puts "✓ User encontrado: #{user.id} - #{user.email}"
end

# 3. Criar contact
contact = account.contacts.first
if contact.nil?
  puts 'Criando contact...'
  contact = Contact.create!(
    name: 'Test Contact',
    email: 'contact@test.com',
    account: account
  )
  puts "✓ Contact criado: #{contact.id}"
else
  puts "✓ Contact encontrado: #{contact.id}"
end

# 4. Criar opportunities de teste
puts "\nCriando opportunities de teste..."
3.times do |i|
  Opportunity.create!(
    title: "Oportunidade Teste #{i + 1}",
    description: "Descrição da oportunidade #{i + 1}",
    contact: contact,
    account: account,
    created_by: user,
    priority: [:low, :medium, :high][i],
    stage: [:new_lead, :qualification, :scheduling_pending][i]
  )
end
puts '✓ 3 opportunities criadas'

# 5. Preparar headers de autenticação
auth_headers = user.create_new_auth_token
puts "\n✓ Headers de autenticação preparados"

# 6. Testar apenas se estivermos no console interativo
if in_console?
  # 6. Testar INDEX
  puts "\n" + ('=' * 60)
  puts "TESTANDO: GET /api/v1/accounts/#{account.id}/opportunities"
  puts '=' * 60
  response = app.get "/api/v1/accounts/#{account.id}/opportunities", headers: auth_headers
  puts "Status: #{response}"
  puts "Body: #{app.response.body[0..500]}"
  puts '✓ Teste INDEX concluído'

  # 7. Testar SHOW
  opportunity = Opportunity.where(account: account).first
  if opportunity
    puts "\n" + ('=' * 60)
    puts "TESTANDO: GET /api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}"
    puts '=' * 60
    response = app.get "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}", headers: auth_headers
    puts "Status: #{response}"
    puts "Body: #{app.response.body[0..500]}"
    puts '✓ Teste SHOW concluído'
  end

  # 8. Testar KANBAN
  puts "\n" + ('=' * 60)
  puts "TESTANDO: GET /api/v1/accounts/#{account.id}/opportunities/kanban"
  puts '=' * 60
  response = app.get "/api/v1/accounts/#{account.id}/opportunities/kanban", headers: auth_headers
  puts "Status: #{response}"
  puts "Body: #{app.response.body[0..500]}"
  puts '✓ Teste KANBAN concluído'

  # 9. Testar PIPELINE METRICS
  puts "\n" + ('=' * 60)
  puts "TESTANDO: GET /api/v1/accounts/#{account.id}/opportunities/pipeline_metrics"
  puts '=' * 60
  response = app.get "/api/v1/accounts/#{account.id}/opportunities/pipeline_metrics", headers: auth_headers
  puts "Status: #{response}"
  puts "Body: #{app.response.body}"
  puts '✓ Teste PIPELINE_METRICS concluído'
else
  puts "\n" + ('=' * 60)
  puts 'AVISO: Script executado fora do console interativo'
  puts '=' * 60
  puts 'Para testar os endpoints, execute no Rails console interativo:'
  puts '  rails console'
  puts "  load 'test_opportunities_api.rb'"
  puts "\nOu teste manualmente com:"
  puts "  app.get \"/api/v1/accounts/#{account.id}/opportunities\", headers: auth_headers"
end

puts "\n" + ('=' * 60)
puts 'DADOS PREPARADOS!'
puts '=' * 60
puts "\nVariáveis disponíveis:"
puts "  - account: #{account.inspect}"
puts "  - user: #{user.inspect}"
puts "  - contact: #{contact.inspect}"
puts '  - auth_headers: Hash com headers de autenticação'
puts "\nPara testar manualmente no console:"
puts "  app.get \"/api/v1/accounts/#{account.id}/opportunities\", headers: auth_headers"
puts '  puts app.response.status'
puts '  puts app.response.body'
