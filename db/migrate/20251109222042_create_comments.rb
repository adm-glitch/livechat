# frozen_string_literal: true

# Migration para criar tabela de comentários polimórficos
# Comentários podem ser associados a diferentes recursos (Opportunity, Task, Contact, etc.)
class CreateComments < ActiveRecord::Migration[7.0]
  def change
    create_table :comments do |t|
      # Conteúdo do comentário
      t.text :content, null: false, comment: 'Conteúdo do comentário'

      # Relacionamento polimórfico
      t.references :commentable, polymorphic: true, null: false, index: true, comment: 'Recurso ao qual o comentário pertence'

      # Relacionamentos obrigatórios
      t.references :account, null: false, foreign_key: true, index: true, comment: 'Conta (tenant) do comentário'
      t.references :user, null: false, foreign_key: true, index: true, comment: 'Usuário autor do comentário'

      # Controle de visibilidade
      t.boolean :is_private, default: true, null: false, comment: 'Se o comentário é privado (interno) ou público'

      # Metadados e controle
      t.jsonb :metadata, default: {}, null: false, comment: 'Dados extras (menções, tags, etc)'
      t.datetime :edited_at, comment: 'Data e hora da última edição'
      t.datetime :deleted_at, comment: 'Soft delete - data de exclusão lógica'

      # Timestamps padrão
      t.timestamps null: false
    end

    # Índices compostos para performance
    # Nota: commentable_type e commentable_id já têm índice criado automaticamente pelo t.references polymorphic
    add_index :comments, [:account_id, :created_at], name: 'index_comments_on_account_created_at'
    add_index :comments, [:user_id, :created_at], name: 'index_comments_on_user_created_at'

    # Índices simples
    add_index :comments, :deleted_at, name: 'index_comments_on_deleted_at'
    add_index :comments, :created_at, name: 'index_comments_on_created_at'
    add_index :comments, :is_private, name: 'index_comments_on_is_private'
  end
end
