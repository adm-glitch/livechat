# frozen_string_literal: true

# == Schema Information
#
# Table name: comments
#
#  id                                                         :bigint           not null, primary key
#  commentable_type                                           :string           not null
#  content(Conteúdo do comentário)                            :text             not null
#  deleted_at(Soft delete - data de exclusão lógica)          :datetime
#  edited_at(Data e hora da última edição)                    :datetime
#  is_private(Se o comentário é privado (interno) ou público) :boolean          default(TRUE), not null
#  metadata(Dados extras (menções, tags, etc))                :jsonb            not null
#  created_at                                                 :datetime         not null
#  updated_at                                                 :datetime         not null
#  account_id(Conta (tenant) do comentário)                   :bigint           not null
#  commentable_id(Recurso ao qual o comentário pertence)      :bigint           not null
#  user_id(Usuário autor do comentário)                       :bigint           not null
#
# Indexes
#
#  index_comments_on_account_created_at  (account_id,created_at)
#  index_comments_on_account_id          (account_id)
#  index_comments_on_commentable         (commentable_type,commentable_id)
#  index_comments_on_created_at          (created_at)
#  index_comments_on_deleted_at          (deleted_at)
#  index_comments_on_is_private          (is_private)
#  index_comments_on_user_created_at     (user_id,created_at)
#  index_comments_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#

# Modelo Comment representa um comentário/nota interna polimórfico
# Pode ser associado a diferentes recursos do CRM (Opportunity, Task, Contact, etc.)
class Comment < ApplicationRecord
  # Tipos de recursos que podem receber comentários
  VALID_COMMENTABLE_TYPES = %w[Opportunity Task Contact].freeze

  # Relacionamento polimórfico
  belongs_to :commentable, polymorphic: true

  # Relacionamentos obrigatórios
  belongs_to :account
  belongs_to :user

  # Validações
  validates :content, presence: true, length: { minimum: 1, maximum: 5000 }
  validates :commentable, presence: true
  validates :account, presence: true
  validates :user, presence: true
  validates :commentable_type, inclusion: { in: VALID_COMMENTABLE_TYPES }

  after_create :create_activity_log
  # Callbacks
  before_update :set_edited_at, if: :content_changed?

  # Scopes
  scope :for_commentable, ->(commentable) { where(commentable: commentable) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :private_comments, -> { where(is_private: true) }
  scope :public_comments, -> { where(is_private: false) }
  scope :edited, -> { where.not(edited_at: nil) }
  scope :exclude_deleted, -> { where(deleted_at: nil) }

  # Default scope para soft delete
  default_scope { exclude_deleted }

  # Métodos de instância

  # Verifica se o comentário foi editado
  def edited?
    edited_at.present?
  end

  # Extrai menções do conteúdo (formato: @username ou (mention://user/ID/name))
  def mentions
    return [] unless content.present?

    mentioned_users = []

    # Extrai menções no formato do Chatwoot: (mention://user/ID/name)
    user_mentions = content.scan(%r{\(mention://user/(\d+)/(.+?)\)}).map(&:first)
    user_mentions.each do |user_id|
      user = User.find_by(id: user_id)
      # Verifica se o usuário pertence à conta através de account_users
      mentioned_users << user if user && user.account_users.exists?(account_id: account_id)
    end

    mentioned_users.uniq
  end

  # Soft delete - marca como deletado sem remover do banco
  def soft_delete
    update(deleted_at: Time.current)
  end

  # Restaura um comentário deletado
  def restore
    update(deleted_at: nil)
  end

  # Métodos de classe

  # Retorna atividade recente de comentários
  def self.recent_activity(account_id, limit: 20)
    where(account_id: account_id)
      .includes(:user, :commentable)
      .recent
      .limit(limit)
  end

  private

  # Define edited_at quando conteúdo é alterado
  def set_edited_at
    self.edited_at = Time.current
  end

  # Cria log de atividade (pode ser estendido para integração com sistema de auditoria)
  def create_activity_log
    # TODO: Implementar integração com sistema de activity log se disponível
    # ActivityLog.create(
    #   account: account,
    #   user: user,
    #   action: 'comment_created',
    #   commentable: commentable
    # )
  end
end
