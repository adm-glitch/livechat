# frozen_string_literal: true

FactoryBot.define do
  factory :task do
    sequence(:title) { |n| "Tarefa #{n}" }
    description { 'Descrição da tarefa' }
    task_type { 'Ligação' }
    due_date { 1.week.from_now }
    priority { :medium }
    status { :pending }

    association :opportunity
    association :account

    trait :completed do
      status { :completed }
      completed_at { Time.current }
      result_notes { 'Tarefa concluída com sucesso' }
    end

    trait :overdue do
      due_date { 1.week.from_now } # Cria com data futura primeiro
      status { :pending }

      after(:create) do |task|
        task.update_column(:due_date, 1.day.ago) # Atualiza para o passado após criação
      end
    end

    trait :high_priority do
      priority { :high }
    end

    trait :urgent do
      priority { :urgent }
    end

    trait :low_priority do
      priority { :low }
    end

    trait :cancelled do
      status { :cancelled }
    end

    trait :in_progress do
      status { :in_progress }
    end

    trait :due_today do
      due_date { Time.current.end_of_day }
    end

    trait :due_this_week do
      due_date { Time.current.end_of_week }
    end

    trait :with_assigned_user do
      association :assigned_to, factory: :user, account: :account
    end

    trait :with_created_by do
      association :created_by, factory: :user, account: :account
    end

    trait :with_contact do
      association :contact, account: :account
    end

    trait :email_task do
      task_type { 'Email' }
      description { 'Enviar email de follow-up' }
    end

    trait :whatsapp_task do
      task_type { 'WhatsApp' }
      description { 'Enviar mensagem via WhatsApp' }
    end

    trait :call_task do
      task_type { 'Ligação' }
      description { 'Realizar ligação para agendamento' }
    end

    trait :follow_up_task do
      task_type { 'Follow-up' }
      description { 'Follow-up após consulta' }
    end

    # Factory para criar tarefa completa
    factory :task_complete do
      with_assigned_user
      with_created_by
      with_contact
      high_priority
      due_this_week
      description { 'Tarefa completa com todos os campos preenchidos' }
    end
  end
end
