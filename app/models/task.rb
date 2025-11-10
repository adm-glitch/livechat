# frozen_string_literal: true

# == Schema Information
#
# Table name: tasks
#
#  id                                                                              :bigint           not null, primary key
#  completed_at(Data e hora de conclusão da tarefa)                                :datetime
#  deleted_at(Soft delete - data de exclusão lógica)                               :datetime
#  description(Descrição detalhada da tarefa)                                      :text
#  due_date(Data e hora de vencimento da tarefa)                                   :datetime         not null
#  priority(Prioridade: 0=low, 1=medium, 2=high, 3=urgent)                         :integer          default("medium"), not null
#  result_notes(Notas após completar a tarefa)                                     :text
#  status(Status: 0=pending, 1=in_progress, 2=completed, 3=cancelled)              :integer          default("pending"), not null
#  task_type(Tipo de tarefa (ex: Ligação, Email, WhatsApp, Follow-up))             :string
#  title(Título da tarefa)                                                         :string(255)      not null
#  created_at                                                                      :datetime         not null
#  updated_at                                                                      :datetime         not null
#  account_id(Conta (tenant) da tarefa)                                            :bigint           not null
#  assigned_to_id(Usuário responsável pela tarefa)                                 :bigint
#  contact_id(Contato relacionado (pode estar diretamente relacionado ao contato)) :bigint
#  created_by_id(Usuário que criou a tarefa)                                       :bigint
#  opportunity_id(Oportunidade associada à tarefa)                                 :bigint           not null
#
# Indexes
#
#  index_tasks_on_account_id          (account_id)
#  index_tasks_on_account_status      (account_id,status)
#  index_tasks_on_assigned_to_id      (assigned_to_id)
#  index_tasks_on_assigned_to_status  (assigned_to_id,status)
#  index_tasks_on_contact_id          (contact_id)
#  index_tasks_on_created_at          (created_at)
#  index_tasks_on_created_by_id       (created_by_id)
#  index_tasks_on_deleted_at          (deleted_at)
#  index_tasks_on_due_date_status     (due_date,status)
#  index_tasks_on_opportunity_id      (opportunity_id)
#  index_tasks_on_opportunity_status  (opportunity_id,status)
#  index_tasks_on_priority            (priority)
#  index_tasks_on_status              (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assigned_to_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (opportunity_id => opportunities.id)
#

# Modelo Task representa uma tarefa relacionada a uma oportunidade
# Tarefas são ações e follow-ups que precisam ser realizados para oportunidades
class Task < ApplicationRecord
  # Enums
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }
  enum status: { pending: 0, in_progress: 1, completed: 2, cancelled: 3 }

  # Relacionamentos obrigatórios
  belongs_to :opportunity
  belongs_to :account

  # Relacionamentos opcionais
  belongs_to :assigned_to, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :contact, optional: true

  # Relacionamentos has_many
  has_many :comments, as: :commentable, dependent: :destroy, class_name: 'Comment'

  # Validações
  validates :title, presence: true, length: { maximum: 255 }
  validates :opportunity, presence: true
  validates :account, presence: true
  validates :status, presence: true
  validates :priority, presence: true
  validates :due_date, presence: true
  validates :result_notes, presence: true, if: -> { completed? }
  validate :due_date_cannot_be_in_past, on: :create

  # Callbacks
  before_update :set_completed_at, if: -> { status_changed? && completed? }
  after_update :notify_assigned_user, if: :saved_change_to_assigned_to_id?

  # Scopes
  scope :pending, -> { where(status: :pending) }
  scope :completed, -> { where(status: :completed) }
  scope :overdue, -> { where('due_date < ? AND status != ?', Time.current, statuses[:completed]) }
  scope :due_today, -> { where(due_date: Time.current.all_day) }
  scope :due_this_week, -> { where(due_date: Time.current.all_week) }
  scope :assigned_to, ->(user_id) { where(assigned_to_id: user_id) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :exclude_deleted, -> { where(deleted_at: nil) }

  # Default scope para soft delete
  default_scope { exclude_deleted }

  # Métodos de instância

  # Verifica se a tarefa está atrasada
  def overdue?
    return false if completed? || cancelled?
    return false unless due_date.present?

    due_date < Time.current
  end

  # Marca a tarefa como concluída com notas
  def mark_as_completed(notes:)
    update(status: :completed, result_notes: notes, completed_at: Time.current)
  end

  # Marca a tarefa como cancelada
  def mark_as_cancelled
    update(status: :cancelled)
  end

  # Calcula quantos dias até o vencimento
  def days_until_due
    return nil unless due_date.present?

    (due_date.to_date - Time.current.to_date).to_i
  end

  # Soft delete - marca como deletado sem remover do banco
  def soft_delete
    update(deleted_at: Time.current)
  end

  # Restaura uma tarefa deletada
  def restore
    update(deleted_at: nil)
  end

  private

  # Define completed_at quando status muda para completed
  def set_completed_at
    self.completed_at = Time.current if completed? && completed_at.nil?
  end

  # Notifica usuário quando tarefa é atribuída
  def notify_assigned_user
    return unless assigned_to.present?
    return if assigned_to_id_was == assigned_to_id

    # TODO: Implementar notificação quando sistema de notificações estiver disponível
    # NotificationService.notify_task_assigned(self, assigned_to)
  end

  # Valida que data de vencimento não está no passado na criação
  def due_date_cannot_be_in_past
    return unless due_date.present?
    return unless due_date < Time.current

    errors.add(:due_date, 'não pode estar no passado')
  end
end
