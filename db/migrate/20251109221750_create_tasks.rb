# frozen_string_literal: true

# Migration para criar tabela de tarefas relacionadas a oportunidades
# Tarefas são ações e follow-ups que precisam ser realizados para oportunidades
class CreateTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :tasks do |t|
      # Campos básicos
      t.string :title, null: false, limit: 255, comment: 'Título da tarefa'
      t.text :description, comment: 'Descrição detalhada da tarefa'
      t.string :task_type, comment: 'Tipo de tarefa (ex: Ligação, Email, WhatsApp, Follow-up)'

      # Datas importantes
      t.datetime :due_date, null: false, comment: 'Data e hora de vencimento da tarefa'
      t.datetime :completed_at, comment: 'Data e hora de conclusão da tarefa'

      # Notas e resultados
      t.text :result_notes, comment: 'Notas após completar a tarefa'

      # Enums
      t.integer :priority, default: 1, null: false, comment: 'Prioridade: 0=low, 1=medium, 2=high, 3=urgent'
      t.integer :status, default: 0, null: false, comment: 'Status: 0=pending, 1=in_progress, 2=completed, 3=cancelled'

      # Soft delete
      t.datetime :deleted_at, comment: 'Soft delete - data de exclusão lógica'

      # Relacionamentos obrigatórios
      t.references :opportunity, null: false, foreign_key: true, index: true, comment: 'Oportunidade associada à tarefa'
      t.references :account, null: false, foreign_key: true, index: true, comment: 'Conta (tenant) da tarefa'

      # Relacionamentos opcionais
      t.references :assigned_to, null: true, foreign_key: { to_table: :users }, index: true, comment: 'Usuário responsável pela tarefa'
      t.references :created_by, null: true, foreign_key: { to_table: :users }, comment: 'Usuário que criou a tarefa'
      t.references :contact, null: true, foreign_key: true, index: true,
                             comment: 'Contato relacionado (pode estar diretamente relacionado ao contato)'

      # Timestamps padrão
      t.timestamps null: false
    end

    # Índices compostos para performance
    add_index :tasks, [:opportunity_id, :status], name: 'index_tasks_on_opportunity_status'
    add_index :tasks, [:account_id, :status], name: 'index_tasks_on_account_status'
    add_index :tasks, [:assigned_to_id, :status], name: 'index_tasks_on_assigned_to_status'
    add_index :tasks, [:due_date, :status], name: 'index_tasks_on_due_date_status'

    # Índices simples para queries comuns
    add_index :tasks, :deleted_at, name: 'index_tasks_on_deleted_at'
    add_index :tasks, :created_at, name: 'index_tasks_on_created_at'
    add_index :tasks, :status, name: 'index_tasks_on_status'
    add_index :tasks, :priority, name: 'index_tasks_on_priority'
  end
end
