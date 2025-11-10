# frozen_string_literal: true

# Concern para gerenciar lógica de workflow de oportunidades
# Inclui métodos de transição de estágio e validações de workflow
module OpportunityWorkflow
  extend ActiveSupport::Concern

  included do
    # Validações específicas de workflow
    validate :validate_stage_transition, if: :stage_changed?
  end

  # Métodos de instância

  # Transiciona para um novo estágio com validação
  def transition_to(new_stage, performed_by: nil)
    return false unless can_transition_to?(new_stage)

    transaction do
      old_stage = stage
      self.stage = new_stage
      self.assigned_agent ||= performed_by if performed_by.present?

      if save
        create_stage_transition_record(old_stage, new_stage, performed_by)
        true
      else
        false
      end
    end
  end

  # Transiciona para próximo estágio válido
  def transition_to_next_stage(performed_by: nil)
    next_stage = next_valid_stage
    return false unless next_stage

    transition_to(next_stage, performed_by: performed_by)
  end

  # Retorna próximo estágio válido baseado no estágio atual
  def next_valid_stage
    case stage.to_sym
    when :new_lead
      :qualification
    when :qualification
      :scheduling_pending
    when :scheduling_pending
      :appointment_scheduled
    when :appointment_scheduled
      :appointment_confirmed
    when :appointment_confirmed
      :completed
    when :completed
      :follow_up
    end
  end

  # Retorna estágio anterior válido
  def previous_valid_stage
    case stage.to_sym
    when :qualification
      :new_lead
    when :scheduling_pending
      :qualification
    when :appointment_scheduled
      :scheduling_pending
    when :appointment_confirmed
      :appointment_scheduled
    when :completed
      :appointment_confirmed
    when :follow_up
      :completed
    end
  end

  # Verifica se pode transicionar para um novo estágio (versão estendida)
  def can_transition_to?(new_stage)
    new_stage_sym = new_stage.to_sym

    # Não pode transicionar para o mesmo estágio
    return false if new_stage_sym == stage.to_sym

    # Não pode transicionar se estiver fechada
    return false if closed?

    # Valida regras de workflow se WorkflowRule existir
    if defined?(WorkflowRule) && WorkflowRule.table_exists?
      workflow_rule = WorkflowRule.find_by(
        account: account,
        from_stage: stage,
        to_stage: new_stage_sym
      )

      return false if workflow_rule&.disabled?
    end

    true
  end

  # Retorna histórico de transições ordenado
  def transition_history
    stage_transitions.order(created_at: :desc)
  end

  # Retorna última transição
  def last_transition
    stage_transitions.order(created_at: :desc).first
  end

  # Verifica se está em um estágio específico
  def at_stage?(stage_name)
    stage.to_sym == stage_name.to_sym
  end

  # Retorna progresso percentual no funil
  def funnel_progress_percentage
    total_stages = self.class.stages.keys.length
    current_stage_index = self.class.stages[stage]
    ((current_stage_index + 1).to_f / total_stages * 100).round(2)
  end

  private

  # Valida transição de estágio
  def validate_stage_transition
    return unless stage_changed?
    return if new_record? # Não valida transição na criação inicial
    return if stage.blank? || stage_was.blank? # Não valida se stage está vazio

    # Usa stage_was para comparar com o stage anterior
    old_stage = stage_was
    new_stage = stage

    # Verifica se pode transicionar do stage anterior para o novo stage
    # Temporariamente restaura o stage anterior para validar
    temp_stage = stage
    self.stage = old_stage
    can_transition = can_transition_to?(new_stage)
    self.stage = temp_stage

    return if can_transition

    errors.add(:stage, 'transição inválida para este estágio')
  end

  # Cria registro de transição de estágio
  def create_stage_transition_record(from_stage, to_stage, performed_by)
    return unless defined?(StageTransition) && StageTransition.table_exists?

    stage_transitions.create!(
      from_stage: from_stage,
      to_stage: to_stage,
      performed_by: performed_by || Current.executed_by || assigned_agent,
      account: account
    )
  rescue StandardError => e
    Rails.logger.error "Erro ao criar transição de estágio: #{e.message}"
    # Não falha a transição principal se houver erro ao criar o registro
  end
end
