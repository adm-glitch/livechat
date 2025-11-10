# frozen_string_literal: true

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
    opportunities = filtered_opportunities.active
    opportunities = opportunities.where(assigned_agent_id: params[:assigned_agent_id]) if params[:assigned_agent_id].present?
    opportunities = opportunities.where(priority: params[:priority]) if params[:priority].present?

    # Aplica filtro de data range se fornecido
    if params[:start_date].present? && params[:end_date].present?
      opportunities = opportunities.where(created_at: Date.parse(params[:start_date])..Date.parse(params[:end_date]).end_of_day)
    end

    # Agrupa por stage
    stages_data = Opportunity.stages.keys.map do |stage_key|
      stage_opportunities = opportunities.where(stage: stage_key)
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

    totals = {
      count: opportunities.count,
      value: opportunities.sum(:estimated_value).to_f
    }

    render json: {
      stages: stages_data,
      totals: totals
    }
  end

  def pipeline_metrics
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current

    opportunities = Current.account.opportunities
                           .where(created_at: start_date..end_date.end_of_day)
                           .where.not(closed_at: nil)

    # Taxa de conversão
    total_closed = opportunities.count
    won_count = opportunities.where(status: :won).count
    conversion_rate = total_closed.positive? ? (won_count.to_f / total_closed * 100).round(2) : 0.0

    # Valor médio de negócios fechados
    won_opportunities = opportunities.where(status: :won).where.not(estimated_value: nil)
    average_deal_value = won_opportunities.any? ? won_opportunities.average(:estimated_value).to_f.round(2) : 0.0

    # Tempo médio de ciclo (em dias)
    cycle_times = opportunities.where.not(closed_at: nil).filter_map do |opp|
      (opp.closed_at.to_date - opp.created_at.to_date).to_i if opp.closed_at.present?
    end
    average_cycle_time_days = cycle_times.any? ? (cycle_times.sum.to_f / cycle_times.size).round(2) : 0.0

    # Por stage
    by_stage = Opportunity.stages.keys.index_with do |stage_key|
      stage_opps = opportunities.where(stage: stage_key)
      stage_cycle_times = stage_opps.filter_map do |opp|
        (opp.closed_at.to_date - opp.created_at.to_date).to_i if opp.closed_at.present?
      end
      avg_time = stage_cycle_times.any? ? (stage_cycle_times.sum.to_f / stage_cycle_times.size).round(2) : 0.0

      {
        count: stage_opps.count,
        avg_time_days: avg_time
      }
    end

    # Por fonte de indicação
    by_referral_source = opportunities.where.not(referral_source: nil)
                                      .group(:referral_source)
                                      .count

    render json: {
      conversion_rate: conversion_rate,
      average_deal_value: average_deal_value,
      average_cycle_time_days: average_cycle_time_days,
      by_stage: by_stage,
      by_referral_source: by_referral_source
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

    # Filtros
    opportunities = opportunities.by_stage(params[:stage]) if params[:stage].present?
    opportunities = opportunities.by_status(params[:status]) if params[:status].present?
    opportunities = opportunities.assigned_to(params[:assigned_agent_id]) if params[:assigned_agent_id].present?
    opportunities = opportunities.where(priority: params[:priority]) if params[:priority].present?

    # Date range filter
    if params[:start_date].present? && params[:end_date].present?
      opportunities = opportunities.where(created_at: Date.parse(params[:start_date])..Date.parse(params[:end_date]).end_of_day)
    end

    opportunities
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
end
