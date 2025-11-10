# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::OpportunitiesController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 20

  before_action :check_authorization, except: [:kanban, :pipeline_metrics, :move_stage, :mark_won, :mark_lost]
  before_action :check_authorization_for_custom_actions, only: [:kanban, :pipeline_metrics]
  before_action :set_current_page, only: [:index]
  before_action :fetch_opportunity, only: [:show, :update, :destroy, :move_stage, :mark_won, :mark_lost]
  before_action :check_authorization_for_member_actions, only: [:move_stage, :mark_won, :mark_lost]

  def index
    @opportunities = fetch_opportunities(filtered_opportunities)
    @opportunities_count = @opportunities.total_count
  end

  def show; end

  def create
    @opportunity = Current.account.opportunities.build(opportunity_params)
    @opportunity.created_by = current_user
    @opportunity.account = Current.account

    # Valida se conversation pertence ao account
    if params[:conversation_id].present?
      conversation = Current.account.conversations.find_by(id: params[:conversation_id])
      render json: { error: 'Conversation not found or does not belong to account' }, status: :unprocessable_entity and return unless conversation

      @opportunity.conversation = conversation
    end

    if @opportunity.save
      render :create, status: :created
    else
      render json: { error: 'Validation failed', message: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    # Não permite mudança de account_id ou contact_id
    update_params = opportunity_params.except(:account_id, :contact_id)

    # Valida conversation se fornecida
    if params[:conversation_id].present?
      conversation = Current.account.conversations.find_by(id: params[:conversation_id])
      render json: { error: 'Conversation not found or does not belong to account' }, status: :unprocessable_entity and return unless conversation

      update_params[:conversation_id] = conversation.id
    end

    if @opportunity.update(update_params)
      render :show
    else
      render json: { error: 'Validation failed', message: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @opportunity.soft_delete
    head :no_content
  end

  # Custom collection actions

  def kanban
    opportunities = apply_kanban_filters(filtered_opportunities.active)
    stages = build_kanban_stages(opportunities)

    render json: {
      stages: stages,
      totals: calculate_totals(opportunities)
    }
  end

  def pipeline_metrics
    start_date, end_date = parse_metrics_dates
    opportunities = closed_opportunities_in_range(start_date, end_date)

    render json: {
      conversion_rate: calculate_conversion_rate(opportunities),
      average_deal_value: calculate_average_deal_value(opportunities),
      average_cycle_time_days: calculate_average_cycle_time(opportunities),
      by_stage: group_opportunities_by_stage(opportunities),
      by_referral_source: group_opportunities_by_referral_source(opportunities)
    }
  end

  # Custom member actions

  def move_stage
    new_stage = params[:stage]
    render json: { error: 'Stage parameter is required' }, status: :unprocessable_entity and return if new_stage.blank?

    render json: { error: 'Invalid stage transition' }, status: :unprocessable_entity and return unless @opportunity.can_transition_to?(new_stage)

    @opportunity.update!(stage: new_stage)
    render :show
  end

  def mark_won
    @opportunity.mark_as_won
    render :show
  end

  def mark_lost
    reason = params[:reason]
    render json: { error: 'Reason is required' }, status: :unprocessable_entity and return if reason.blank?

    @opportunity.mark_as_lost(reason: reason)
    render :show
  end

  private

  def fetch_opportunities(scope)
    scope.includes(:contact, :assigned_agent, :conversation, :created_by)
         .order(updated_at: :desc)
         .page(@current_page)
         .per(RESULTS_PER_PAGE)
  end

  def filtered_opportunities
    opportunities = Current.account.opportunities
    opportunities = apply_basic_filters(opportunities)
    apply_date_range_filter(opportunities)
  end

  def fetch_opportunity
    @opportunity = Current.account.opportunities
                          .includes(:contact, :assigned_agent, :conversation, :created_by)
                          .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Opportunity not found' }, status: :not_found
  end

  def opportunity_params
    params.permit(
      :title, :description, :contact_id, :conversation_id, :assigned_agent_id,
      :service_type, :estimated_value, :suggested_appointment_date,
      :referral_source, :priority, :stage
    )
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def check_authorization
    authorize(Opportunity, "#{action_name}?")
  end

  def check_authorization_for_custom_actions
    authorize(Opportunity, :index?)
  end

  def check_authorization_for_member_actions
    return unless @opportunity

    authorize(@opportunity, :update?)
  end

  # Aplica filtros específicos para o kanban
  def apply_kanban_filters(opportunities)
    opportunities = opportunities.assigned_to(params[:assigned_agent_id]) if params[:assigned_agent_id].present?
    opportunities = opportunities.where(priority: params[:priority]) if params[:priority].present?
    apply_date_range_filter(opportunities)
  end

  # Constrói os dados de stages para o kanban
  def build_kanban_stages(opportunities)
    Opportunity.stages.keys.map { |stage_key| build_stage_data(opportunities, stage_key) }
  end

  # Constrói os dados de um stage específico
  def build_stage_data(opportunities, stage_key)
    stage_opportunities = opportunities.by_stage(stage_key)
                                       .order(priority: :desc, updated_at: :desc)
                                       .includes(:contact, :assigned_agent, :conversation, :created_by)

    {
      key: stage_key,
      name: I18n.t("opportunities.stages.#{stage_key}", default: stage_key.humanize),
      opportunities: stage_opportunities,
      count: stage_opportunities.count,
      total_value: stage_opportunities.sum(:estimated_value).to_f
    }
  end

  # Calcula os totais do kanban
  def calculate_totals(opportunities)
    {
      count: opportunities.count,
      value: opportunities.sum(:estimated_value).to_f
    }
  end

  # Parse das datas para métricas do pipeline
  def parse_metrics_dates
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
    [start_date, end_date]
  end

  # Retorna oportunidades fechadas no range de datas
  def closed_opportunities_in_range(start_date, end_date)
    Current.account.opportunities
           .where(created_at: start_date..end_date.end_of_day)
           .where.not(closed_at: nil)
  end

  # Calcula a taxa de conversão
  def calculate_conversion_rate(opportunities)
    total_closed = opportunities.count
    return 0.0 unless total_closed.positive?

    won_count = opportunities.where(status: :won).count
    (won_count.to_f / total_closed * 100).round(2)
  end

  # Calcula o valor médio de negócios fechados
  def calculate_average_deal_value(opportunities)
    won_opportunities = opportunities.where(status: :won).where.not(estimated_value: nil)
    return 0.0 unless won_opportunities.any?

    won_opportunities.average(:estimated_value).to_f.round(2)
  end

  # Calcula o tempo médio de ciclo em dias
  def calculate_average_cycle_time(opportunities)
    cycle_times = extract_cycle_times(opportunities)
    return 0.0 unless cycle_times.any?

    (cycle_times.sum.to_f / cycle_times.size).round(2)
  end

  # Extrai os tempos de ciclo das oportunidades
  def extract_cycle_times(opportunities)
    opportunities.filter_map do |opp|
      next if opp.closed_at.blank?

      (opp.closed_at.to_date - opp.created_at.to_date).to_i
    end
  end

  # Agrupa oportunidades por stage com métricas
  def group_opportunities_by_stage(opportunities)
    Opportunity.stages.keys.index_with do |stage_key|
      stage_opps = opportunities.where(stage: stage_key)
      stage_cycle_times = extract_cycle_times(stage_opps)
      avg_time = stage_cycle_times.any? ? (stage_cycle_times.sum.to_f / stage_cycle_times.size).round(2) : 0.0

      {
        count: stage_opps.count,
        avg_time_days: avg_time
      }
    end
  end

  # Agrupa oportunidades por fonte de indicação
  def group_opportunities_by_referral_source(opportunities)
    opportunities.where.not(referral_source: nil)
                 .group(:referral_source)
                 .count
  end

  # Aplica filtros básicos (stage, status, assigned_agent, priority)
  def apply_basic_filters(opportunities)
    opportunities = opportunities.by_stage(params[:stage]) if params[:stage].present?
    opportunities = opportunities.by_status(params[:status]) if params[:status].present?
    opportunities = opportunities.assigned_to(params[:assigned_agent_id]) if params[:assigned_agent_id].present?
    opportunities = opportunities.where(priority: params[:priority]) if params[:priority].present?
    opportunities
  end

  # Aplica filtro de range de datas
  def apply_date_range_filter(opportunities)
    return opportunities unless params[:start_date].present? && params[:end_date].present?

    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])
    opportunities.where(created_at: start_date..end_date.end_of_day)
  end
end
# rubocop:enable Metrics/ClassLength
