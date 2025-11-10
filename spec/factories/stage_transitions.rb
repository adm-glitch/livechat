# frozen_string_literal: true

FactoryBot.define do
  factory :stage_transition do
    from_stage { 'new_lead' }
    to_stage { 'qualification' }
    notes { nil }
    metadata { {} }
    transition_duration_seconds { nil }

    association :opportunity
    association :account

    trait :automated do
      metadata { { automated: true, trigger: 'workflow_rule' } }
    end

    trait :manual do
      metadata { { automated: false } }
      after(:build) do |transition|
        transition.performed_by ||= create(:user, account: transition.account)
      end
    end

    trait :with_notes do
      notes { 'Transição realizada para qualificar necessidades do paciente' }
    end

    trait :initial_transition do
      from_stage { nil }
      to_stage { 'new_lead' }
    end

    trait :from_new_lead_to_qualification do
      from_stage { 'new_lead' }
      to_stage { 'qualification' }
    end

    trait :from_qualification_to_scheduling do
      from_stage { 'qualification' }
      to_stage { 'scheduling_pending' }
    end

    trait :from_scheduling_to_scheduled do
      from_stage { 'scheduling_pending' }
      to_stage { 'appointment_scheduled' }
    end

    trait :from_scheduled_to_confirmed do
      from_stage { 'appointment_scheduled' }
      to_stage { 'appointment_confirmed' }
    end

    trait :from_confirmed_to_completed do
      from_stage { 'appointment_confirmed' }
      to_stage { 'completed' }
    end

    trait :from_completed_to_follow_up do
      from_stage { 'completed' }
      to_stage { 'follow_up' }
    end

    trait :with_duration do
      transition_duration_seconds { 86_400 } # 1 dia em segundos
    end

    trait :with_long_duration do
      transition_duration_seconds { 604_800 } # 1 semana em segundos
    end

    # Factory para criar transição completa
    factory :stage_transition_complete do
      manual
      with_notes
      with_duration
      from_new_lead_to_qualification
    end
  end
end
