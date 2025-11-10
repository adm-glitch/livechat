# frozen_string_literal: true

# Migration para criar tabela de transições de estágio (audit trail)
# Esta tabela rastreia todas as mudanças de estágio nas oportunidades para analytics e LGPD
class CreateStageTransitions < ActiveRecord::Migration[7.0]
  def change
    create_table :stage_transitions do |t|
      # Campos de transição
      t.string :from_stage, null: true, comment: 'Estágio anterior (pode ser nil para primeira transição)'
      t.string :to_stage, null: false, comment: 'Novo estágio'
      t.text :notes, comment: 'Motivo da mudança ou observações'

      # Metadados e analytics
      t.jsonb :metadata, default: {}, null: false, comment: 'Dados adicionais (ex: automated: true)'
      t.integer :transition_duration_seconds, comment: 'Tempo que ficou no estágio anterior (em segundos)'

      # Relacionamentos obrigatórios
      t.references :opportunity, null: false, foreign_key: true, index: true, comment: 'Oportunidade que teve a transição'
      t.references :account, null: false, foreign_key: true, index: true, comment: 'Conta (tenant) da transição'

      # Relacionamento opcional
      t.references :performed_by, null: true, foreign_key: { to_table: :users }, index: true, comment: 'Usuário que realizou a transição'

      # Timestamps padrão
      t.timestamps null: false
    end

    # Índices compostos para performance e analytics
    add_index :stage_transitions, [:opportunity_id, :created_at], name: 'index_stage_transitions_on_opportunity_created_at'
    add_index :stage_transitions, [:account_id, :to_stage], name: 'index_stage_transitions_on_account_to_stage'
    add_index :stage_transitions, [:account_id, :created_at], name: 'index_stage_transitions_on_account_created_at'

    # Índices simples
    add_index :stage_transitions, :created_at, name: 'index_stage_transitions_on_created_at'
    add_index :stage_transitions, :from_stage, name: 'index_stage_transitions_on_from_stage'
    add_index :stage_transitions, :to_stage, name: 'index_stage_transitions_on_to_stage'
  end
end
