# frozen_string_literal: true

# == Schema Information
#
# Table name: stage_transitions
#
#  id                                                                             :bigint           not null, primary key
#  from_stage(Estágio anterior (pode ser nil para primeira transição))            :string           not null
#  metadata(Dados adicionais (ex: automated: true))                               :jsonb            not null
#  notes(Motivo da mudança ou observações)                                        :text
#  to_stage(Novo estágio)                                                         :string           not null
#  transition_duration_seconds(Tempo que ficou no estágio anterior (em segundos)) :integer
#  created_at                                                                     :datetime         not null
#  updated_at                                                                     :datetime         not null
#  account_id(Conta (tenant) da transição)                                        :bigint           not null
#  opportunity_id(Oportunidade que teve a transição)                              :bigint           not null
#  performed_by_id(Usuário que realizou a transição)                              :bigint
#
# Indexes
#
#  index_stage_transitions_on_account_created_at      (account_id,created_at)
#  index_stage_transitions_on_account_id              (account_id)
#  index_stage_transitions_on_account_to_stage        (account_id,to_stage)
#  index_stage_transitions_on_created_at              (created_at)
#  index_stage_transitions_on_from_stage              (from_stage)
#  index_stage_transitions_on_opportunity_created_at  (opportunity_id,created_at)
#  index_stage_transitions_on_opportunity_id          (opportunity_id)
#  index_stage_transitions_on_performed_by_id         (performed_by_id)
#  index_stage_transitions_on_to_stage                (to_stage)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (opportunity_id => opportunities.id)
#  fk_rails_...  (performed_by_id => users.id)
#

# Modelo StageTransition representa uma transição de estágio em uma oportunidade
# Este modelo é append-only (nunca atualizar ou deletar) e usado para audit trail e analytics LGPD
class StageTransition < ApplicationRecord
  # Estágios válidos (deve corresponder ao enum do Opportunity)
  VALID_STAGES = %w[
    new_lead
    qualification
    scheduling_pending
    appointment_scheduled
    appointment_confirmed
    completed
    follow_up
  ].freeze

  # Relacionamentos obrigatórios
  belongs_to :opportunity
  belongs_to :account

  # Relacionamento opcional
  belongs_to :performed_by, class_name: 'User', optional: true

  # Validações
  validates :opportunity, presence: true
  validates :account, presence: true
  validates :from_stage, presence: true, allow_nil: true # nil é permitido para primeira transição
  validates :to_stage, presence: true
  validate :valid_stage_values
  validate :stages_must_be_different

  # Callbacks
  before_create :calculate_transition_duration

  # Scopes
  scope :for_opportunity, ->(opportunity_id) { where(opportunity_id: opportunity_id) }
  scope :by_stage, ->(stage) { where(to_stage: stage) }
  scope :recent, -> { order(created_at: :desc) }
  scope :this_month, -> { where(created_at: Time.current.all_month) }
  scope :automated, -> { where("metadata->>'automated' = 'true'") }
  scope :manual, -> { where("metadata->>'automated' IS NULL OR metadata->>'automated' = 'false'") }

  # Métodos de instância

  # Verifica se a transição foi automática
  def automated?
    metadata['automated'] == true || metadata['automated'] == 'true'
  end

  # Converte duração de segundos para dias
  def duration_in_days
    return nil if transition_duration_seconds.nil? || transition_duration_seconds.zero?

    (transition_duration_seconds.to_f / 86_400).round(2)
  end

  # Métodos de classe

  # Calcula tempo médio em um estágio específico
  def self.average_time_in_stage(stage, account_id)
    transitions = where(account_id: account_id, to_stage: stage.to_s)
                  .where.not(transition_duration_seconds: nil)

    return 0.0 if transitions.empty?

    average_seconds = transitions.average(:transition_duration_seconds)
    (average_seconds.to_f / 86_400).round(2) # Converte para dias
  end

  # Conta quantas transições ocorreram de um estágio para outro
  def self.transition_count(from_stage, to_stage, account_id)
    where(account_id: account_id, from_stage: from_stage.to_s, to_stage: to_stage.to_s).count
  end

  # Retorna funil de conversão com contagem de transições por estágio
  def self.conversion_funnel(account_id, start_date, end_date)
    transitions = where(account_id: account_id)
                  .where(created_at: start_date..end_date)
                  .group(:to_stage)
                  .count

    # Ordena por ordem dos estágios
    ordered_stages = VALID_STAGES
    ordered_transitions = {}

    ordered_stages.each do |stage|
      ordered_transitions[stage] = transitions[stage] || 0
    end

    ordered_transitions
  end

  private

  # Calcula duração da transição baseado na transição anterior
  def calculate_transition_duration
    # Não calcula se já foi definido explicitamente
    return if transition_duration_seconds.present?
    return if from_stage.blank? # Primeira transição não tem duração

    previous_transition = opportunity.stage_transitions
                                     .where(to_stage: from_stage)
                                     .order(created_at: :desc)
                                     .first

    return unless previous_transition&.created_at.present?

    duration = (created_at || Time.current) - previous_transition.created_at
    # Só define se a duração for positiva (pode ser negativa em testes com travel_to)
    self.transition_duration_seconds = duration.to_i if duration.positive?
  end

  # Valida que os estágios são válidos
  def valid_stage_values
    return if to_stage.blank?

    errors.add(:to_stage, "deve ser um dos seguintes: #{VALID_STAGES.join(', ')}") unless VALID_STAGES.include?(to_stage.to_s)

    return if from_stage.blank?

    return if VALID_STAGES.include?(from_stage.to_s)

    errors.add(:from_stage, "deve ser um dos seguintes: #{VALID_STAGES.join(', ')}")
  end

  # Valida que os estágios são diferentes
  def stages_must_be_different
    return if from_stage.blank? || to_stage.blank?
    return if from_stage != to_stage

    errors.add(:to_stage, 'deve ser diferente do estágio anterior')
  end
end
