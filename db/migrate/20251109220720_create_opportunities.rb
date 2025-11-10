# frozen_string_literal: true

# Migration para criar tabela de oportunidades (leads) no funil de vendas de saúde
# Esta tabela representa leads no sistema CRM de clínicas de saúde
class CreateOpportunities < ActiveRecord::Migration[7.0]
  def change
    create_table :opportunities do |t|
      # Identificação única da oportunidade (gerado automaticamente)
      t.string :opportunity_id, null: false, limit: 255, comment: 'ID único da oportunidade gerado automaticamente'

      # Campos básicos
      t.string :title, null: false, limit: 255, comment: 'Título da oportunidade'
      t.text :description, comment: 'Descrição detalhada da oportunidade'

      # Campos específicos de saúde
      t.string :service_type, comment: 'Tipo de serviço (ex: Consulta Dermatológica, Procedimento Estético)'
      t.decimal :estimated_value, precision: 10, scale: 2, comment: 'Valor estimado do serviço'
      t.date :suggested_appointment_date, comment: 'Data sugerida para agendamento'
      t.string :referral_source, comment: 'Fonte de indicação (ex: Instagram, Google Ads, Indicação)'
      t.text :lost_reason, comment: 'Motivo da perda (preenchido quando status = lost)'

      # Metadados LGPD
      t.jsonb :consent_metadata, default: {}, null: false, comment: 'Metadados de consentimento para marketing (LGPD)'

      # Enums
      t.integer :status, default: 0, null: false, comment: 'Status: 0=open, 1=won, 2=lost, 3=abandoned'
      t.integer :priority, default: 1, null: false, comment: 'Prioridade: 0=low, 1=medium, 2=high, 3=urgent'
      t.integer :stage, default: 0, null: false,
                        comment: 'Estágio: 0=new_lead, 1=qualification, 2=scheduling_pending, 3=appointment_scheduled, 4=appointment_confirmed, 5=completed, 6=follow_up'

      # Timestamps de controle
      t.datetime :closed_at, comment: 'Data de fechamento (won/lost/abandoned)'
      t.datetime :deleted_at, comment: 'Soft delete - data de exclusão lógica'

      # Relacionamentos obrigatórios
      t.references :contact, null: false, foreign_key: true, index: true, comment: 'Contato associado à oportunidade'
      t.references :account, null: false, foreign_key: true, index: true, comment: 'Conta (tenant) da oportunidade'

      # Relacionamentos opcionais
      t.references :conversation, null: true, foreign_key: true, index: true, comment: 'Conversa associada (pode ser criada manualmente)'
      t.references :assigned_agent, null: true, foreign_key: { to_table: :users }, index: true, comment: 'Agente responsável pela oportunidade'
      t.references :created_by, null: true, foreign_key: { to_table: :users }, comment: 'Usuário que criou a oportunidade'

      # Timestamps padrão
      t.timestamps null: false
    end

    # Índices únicos
    add_index :opportunities, :opportunity_id, unique: true, name: 'index_opportunities_on_opportunity_id_unique'
    add_index :opportunities, [:account_id, :opportunity_id], unique: true, name: 'index_opportunities_on_account_id_and_opportunity_id'

    # Índices compostos para performance
    add_index :opportunities, [:account_id, :stage], name: 'index_opportunities_on_account_stage'
    add_index :opportunities, [:account_id, :status], name: 'index_opportunities_on_account_status'
    add_index :opportunities, [:assigned_agent_id, :status], name: 'index_opportunities_on_agent_status'

    # Índices simples para queries comuns
    # Nota: contact_id, account_id, conversation_id e assigned_agent_id já têm índices criados automaticamente pelo t.references
    add_index :opportunities, :deleted_at, name: 'index_opportunities_on_deleted_at'
    add_index :opportunities, :created_at, name: 'index_opportunities_on_created_at'
    add_index :opportunities, :status, name: 'index_opportunities_on_status'
    add_index :opportunities, :stage, name: 'index_opportunities_on_stage'
    add_index :opportunities, :priority, name: 'index_opportunities_on_priority'
  end
end
