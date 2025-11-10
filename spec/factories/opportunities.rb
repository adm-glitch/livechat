# frozen_string_literal: true

FactoryBot.define do
  factory :opportunity do
    sequence(:title) { |n| "Oportunidade #{n}" }
    description { 'Descrição da oportunidade de saúde' }
    service_type { 'Consulta Dermatológica' }
    estimated_value { 500.00 }
    referral_source { 'Instagram' }
    status { :open }
    priority { :medium }
    stage { :new_lead }
    consent_metadata { {} }

    association :contact
    association :account

    after(:build) do |opportunity|
      # Garante que o contact pertence ao mesmo account
      opportunity.contact ||= create(:contact, account: opportunity.account) if opportunity.account.present?
      opportunity.account ||= opportunity.contact.account if opportunity.contact.present?
    end

    trait :with_conversation do
      association :conversation, account: :account
    end

    trait :high_priority do
      priority { :high }
    end

    trait :urgent do
      priority { :urgent }
    end

    trait :won do
      status { :won }
      closed_at { Time.current }
    end

    trait :lost do
      status { :lost }
      closed_at { Time.current }
      lost_reason { 'Paciente desistiu' }
    end

    trait :abandoned do
      status { :abandoned }
      closed_at { Time.current }
    end

    trait :deleted do
      deleted_at { Time.current }
    end

    trait :with_assigned_agent do
      association :assigned_agent, factory: :user, account: :account
    end

    trait :with_created_by do
      association :created_by, factory: :user, account: :account
    end

    trait :at_qualification_stage do
      stage { :qualification }
    end

    trait :at_scheduling_pending_stage do
      stage { :scheduling_pending }
    end

    trait :at_appointment_scheduled_stage do
      stage { :appointment_scheduled }
      suggested_appointment_date { 1.week.from_now }
    end

    trait :at_appointment_confirmed_stage do
      stage { :appointment_confirmed }
      suggested_appointment_date { 1.week.from_now }
    end

    trait :at_completed_stage do
      stage { :completed }
    end

    trait :at_follow_up_stage do
      stage { :follow_up }
    end

    trait :with_future_appointment do
      suggested_appointment_date { 1.week.from_now }
    end

    trait :with_past_appointment do
      suggested_appointment_date { 1.week.ago }
    end

    trait :with_consent_metadata do
      consent_metadata do
        {
          marketing_consent: true,
          consent_date: Time.current.iso8601,
          consent_source: 'web_form'
        }
      end
    end

    # Factory para criar oportunidade completa
    factory :opportunity_complete do
      with_conversation
      with_assigned_agent
      with_created_by
      high_priority
      at_appointment_scheduled_stage
      with_future_appointment
      with_consent_metadata
    end
  end
end
