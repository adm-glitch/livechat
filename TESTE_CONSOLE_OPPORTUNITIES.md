# Guia para testar o endpoint de Opportunities no Rails Console

# ============================================
# OPÇÃO 1: Usando DeviseTokenAuth (recomendado)
# ============================================

# 1. Criar ou buscar um account e user
account = Account.first || Account.create!(name: 'Test Account')
user = account.users.first
if user.nil?
  user = User.create!(
    email: 'test@example.com',
    password: 'Password1!',
    name: 'Test User'
  )
  user.skip_confirmation!
  user.save!
  # Vincular user ao account através de AccountUser
  AccountUser.create!(
    account: account,
    user: user,
    role: :administrator
  )
end

# 2. Criar um contact para associar à opportunity
contact = account.contacts.first || Contact.create!(
  name: 'Test Contact',
  email: 'contact@example.com',
  account: account
)

# 3. Criar algumas opportunities para testar
opportunity = Opportunity.create!(
  title: 'Test Opportunity',
  contact: contact,
  account: account,
  created_by: user
)

# 4. Testar o endpoint INDEX
app.get "/api/v1/accounts/#{account.id}/opportunities", 
        headers: user.create_new_auth_token

# Ver resposta
puts app.response.body
puts app.response.status

# ============================================
# OPÇÃO 2: Usando api_access_token
# ============================================

# Se o user já tem um access_token criado
app.get "/api/v1/accounts/#{account.id}/opportunities",
        headers: { 'api_access_token' => user.access_token.token }

# ============================================
# OPÇÃO 3: Criar access_token se não existir
# ============================================

# Criar access_token se não existir
unless user.access_token
  user.access_tokens.create!(token: SecureRandom.hex(32))
end

app.get "/api/v1/accounts/#{account.id}/opportunities",
        headers: { 'api_access_token' => user.access_token.token }

# ============================================
# Testar outros endpoints
# ============================================

# SHOW
app.get "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
        headers: user.create_new_auth_token

# CREATE
app.post "/api/v1/accounts/#{account.id}/opportunities",
         params: {
           title: 'Nova Oportunidade',
           description: 'Descrição',
           contact_id: contact.id,
           priority: 'high',
           stage: 'new_lead'
         },
         headers: user.create_new_auth_token

# UPDATE
app.patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
          params: { title: 'Título Atualizado' },
          headers: user.create_new_auth_token

# KANBAN
app.get "/api/v1/accounts/#{account.id}/opportunities/kanban",
        headers: user.create_new_auth_token

# PIPELINE METRICS
app.get "/api/v1/accounts/#{account.id}/opportunities/pipeline_metrics",
        headers: user.create_new_auth_token

# MOVE STAGE
app.patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/move_stage",
          params: { stage: 'qualification' },
          headers: user.create_new_auth_token

# MARK WON
app.post "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/mark_won",
         headers: user.create_new_auth_token

# MARK LOST
app.post "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/mark_lost",
         params: { reason: 'Paciente desistiu' },
         headers: user.create_new_auth_token

# DELETE
app.delete "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
           headers: user.create_new_auth_token

