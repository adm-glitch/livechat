# frozen_string_literal: true

# == Schema Information
#
# Table name: opportunities
#
#  id                                                                                                                                            :bigint           not null, primary key
#  closed_at(Data de fechamento (won/lost/abandoned))                                                                                            :datetime
#  consent_metadata(Metadados de consentimento para marketing (LGPD))                                                                            :jsonb            not null
#  deleted_at(Soft delete - data de exclusão lógica)                                                                                             :datetime
#  description(Descrição detalhada da oportunidade)                                                                                              :text
#  estimated_value(Valor estimado do serviço)                                                                                                    :decimal(10, 2)
#  lost_reason(Motivo da perda (preenchido quando status = lost))                                                                                :text
#  priority(Prioridade: 0=low, 1=medium, 2=high, 3=urgent)                                                                                       :integer          default("medium"), not null
#  referral_source(Fonte de indicação (ex: Instagram, Google Ads, Indicação))                                                                    :string
#  service_type(Tipo de serviço (ex: Consulta Dermatológica, Procedimento Estético))                                                             :string
#  stage(Estágio: 0=new_lead, 1=qualification, 2=scheduling_pending, 3=appointment_scheduled, 4=appointment_confirmed, 5=completed, 6=follow_up) :integer          default("new_lead"), not null
#  status(Status: 0=open, 1=won, 2=lost, 3=abandoned)                                                                                            :integer          default("open"), not null
#  suggested_appointment_date(Data sugerida para agendamento)                                                                                    :date
#  title(Título da oportunidade)                                                                                                                 :string(255)      not null
#  created_at                                                                                                                                    :datetime         not null
#  updated_at                                                                                                                                    :datetime         not null
#  account_id(Conta (tenant) da oportunidade)                                                                                                    :bigint           not null
#  assigned_agent_id(Agente responsável pela oportunidade)                                                                                       :bigint
#  contact_id(Contato associado à oportunidade)                                                                                                  :bigint           not null
#  conversation_id(Conversa associada (pode ser criada manualmente))                                                                             :bigint
#  created_by_id(Usuário que criou a oportunidade)                                                                                               :bigint
#  opportunity_id(ID único da oportunidade gerado automaticamente)                                                                               :string(255)      not null
#
# Indexes
#
#  index_opportunities_on_account_id                     (account_id)
#  index_opportunities_on_account_id_and_opportunity_id  (account_id,opportunity_id) UNIQUE
#  index_opportunities_on_account_stage                  (account_id,stage)
#  index_opportunities_on_account_status                 (account_id,status)
#  index_opportunities_on_agent_status                   (assigned_agent_id,status)
#  index_opportunities_on_assigned_agent_id              (assigned_agent_id)
#  index_opportunities_on_contact_id                     (contact_id)
#  index_opportunities_on_conversation_id                (conversation_id)
#  index_opportunities_on_created_at                     (created_at)
#  index_opportunities_on_created_by_id                  (created_by_id)
#  index_opportunities_on_deleted_at                     (deleted_at)
#  index_opportunities_on_opportunity_id_unique          (opportunity_id) UNIQUE
#  index_opportunities_on_priority                       (priority)
#  index_opportunities_on_stage                          (stage)
#  index_opportunities_on_status                         (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assigned_agent_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (created_by_id => users.id)
#

# Modelo Opportunity representa um lead no funil de vendas de saúde
# Cada oportunidade está associada a um contato e pode ter uma conversa relacionada
class Opportunity < ApplicationRecord
  include OpportunityWorkflow

  # Enums
  enum status: { open: 0, won: 1, lost: 2, abandoned: 3 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }
  enum stage: {
    new_lead: 0,              # Lead novo no sistema
    qualification: 1,         # Qualificando necessidades
    scheduling_pending: 2,   # Aguardando agendamento
    appointment_scheduled: 3, # Consulta agendada
    appointment_confirmed: 4,  # Paciente confirmou presença
    completed: 5,            # Atendimento realizado
    follow_up: 6             # Follow-up pós-atendimento
  }

  # Relacionamentos obrigatórios
  belongs_to :contact
  belongs_to :account

  # Relacionamentos opcionais
  belongs_to :conversation, optional: true
  belongs_to :assigned_agent, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  # Relacionamentos has_many
  has_many :tasks, dependent: :destroy
  has_many :stage_transitions, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy, class_name: 'Comment'

  # Validações
  validates :title, presence: true, length: { maximum: 255 }
  validates :contact, presence: true
  validates :account, presence: true
  validates :stage, presence: true
  validates :status, presence: true
  validates :opportunity_id, presence: true, uniqueness: { scope: :account_id }
  validate :opportunity_id_cannot_be_blank
  validates :estimated_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :lost_reason, presence: true, if: -> { status == 'lost' }
  validate :appointment_date_cannot_be_in_past, if: -> { suggested_appointment_date.present? }

  # Callbacks
  before_validation :generate_opportunity_id, on: :create
  after_create :create_initial_stage_transition
  before_update :store_previous_stage, if: :stage_changed?
  after_update :handle_stage_change, if: :saved_change_to_stage?
  after_update :handle_status_change, if: :saved_change_to_status?

  # Scopes
  scope :active, -> { where(status: :open) }
  scope :by_stage, ->(stage) { where(stage: stage) }
  scope :by_status, ->(status) { where(status: status) }
  scope :high_priority, -> { where(priority: [:high, :urgent]) }
  scope :assigned_to, ->(agent_id) { where(assigned_agent_id: agent_id) }
  scope :unassigned, -> { where(assigned_agent_id: nil) }
  scope :stale, -> { where('updated_at < ? AND status = ?', 3.days.ago, statuses[:open]) }
  scope :this_month, -> { where(created_at: Time.current.all_month) }
  scope :this_week, -> { where(created_at: Time.current.all_week) }
  scope :exclude_deleted, -> { where(deleted_at: nil) }

  # Default scope para soft delete
  default_scope { exclude_deleted }

  # Métodos de instância

  # Calcula quantos dias a oportunidade está no estágio atual
  def days_in_current_stage
    last_transition = StageTransition.unscoped.where(opportunity_id: id).order(created_at: :desc).first
    return 0 unless last_transition

    (Time.current.to_date - last_transition.created_at.to_date).to_i
  end

  # Marca a oportunidade como ganha
  def mark_as_won
    update(status: :won, closed_at: Time.current)
  end

  # Marca a oportunidade como perdida com motivo
  def mark_as_lost(reason:)
    update(status: :lost, closed_at: Time.current, lost_reason: reason)
  end

  # Marca a oportunidade como abandonada
  def mark_as_abandoned
    update(status: :abandoned, closed_at: Time.current)
  end

  # Verifica se pode transicionar para um novo estágio
  def can_transition_to?(new_stage)
    return false if stage.nil? || new_stage.nil?
    return false if new_stage.to_sym == stage.to_sym
    return false if closed?

    # Validações básicas de transição
    # Pode ser estendido com regras de negócio mais complexas
    true
  end

  # Soft delete - marca como deletado sem remover do banco
  def soft_delete
    update(deleted_at: Time.current)
  end

  # Restaura uma oportunidade deletada
  def restore
    update(deleted_at: nil)
  end

  # Verifica se está fechada (won, lost ou abandoned)
  def closed?
    won? || lost? || abandoned?
  end

  # Métodos de classe

  # Calcula taxa de conversão para um período
  def self.conversion_rate(account_id, start_date, end_date)
    opportunities = where(account_id: account_id)
                    .where(created_at: start_date..end_date)
                    .where.not(closed_at: nil)

    return 0.0 if opportunities.empty?

    won_count = opportunities.where(status: :won).count
    (won_count.to_f / opportunities.count * 100).round(2)
  end

  # Calcula valor médio de negócios fechados
  def self.average_deal_value(account_id)
    opportunities = where(account_id: account_id)
                    .where(status: :won)
                    .where.not(estimated_value: nil)

    return 0.0 if opportunities.empty?

    opportunities.average(:estimated_value).to_f.round(2)
  end

  # Agrupa oportunidades por fonte de indicação
  def self.by_referral_source(account_id)
    where(account_id: account_id)
      .where.not(referral_source: nil)
      .group(:referral_source)
      .count
  end

  private

  # Gera ID único da oportunidade antes da validação
  def generate_opportunity_id
    # Não gera se já existe, se for string vazia (explicitamente passada), ou se account_id não estiver definido
    return if opportunity_id.present?
    return if opportunity_id == '' # String vazia explicitamente passada
    return unless account_id.present? # Precisa de account_id para verificar unicidade

    loop do
      self.opportunity_id = "OPP-#{SecureRandom.alphanumeric(8).upcase}"
      break unless self.class.exists?(opportunity_id: opportunity_id, account_id: account_id)
    end
  end

  # Cria transição inicial para o estágio new_lead
  def create_initial_stage_transition
    stage_transitions.create!(
      from_stage: nil,
      to_stage: stage,
      performed_by: created_by,
      account: account
    )
  end

  # Armazena o estágio anterior antes da atualização
  def store_previous_stage
    @previous_stage = stage_was
  end

  # Manipula mudança de estágio
  def handle_stage_change
    return unless @previous_stage

    stage_transitions.create!(
      from_stage: @previous_stage,
      to_stage: stage,
      performed_by: Current.executed_by || assigned_agent,
      account: account
    )
  end

  # Manipula mudança de status
  def handle_status_change
    case status
    when 'won', 'lost', 'abandoned'
      self.closed_at = Time.current unless closed_at.present?
    when 'open'
      self.closed_at = nil
    end
  end

  # Valida que data de agendamento não está no passado
  def appointment_date_cannot_be_in_past
    return unless suggested_appointment_date.present?
    return unless suggested_appointment_date < Date.current

    errors.add(:suggested_appointment_date, 'não pode estar no passado')
  end

  # Valida que opportunity_id não pode ser string vazia
  def opportunity_id_cannot_be_blank
    return if opportunity_id.nil? # nil será tratado pela validação de presence
    return unless opportunity_id.respond_to?(:blank?)

    errors.add(:opportunity_id, 'não pode estar em branco') if opportunity_id.blank?
  end
end
