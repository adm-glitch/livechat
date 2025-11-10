# frozen_string_literal: true

FactoryBot.define do
  factory :comment do
    sequence(:content) { |n| "Comentário #{n} sobre a oportunidade" }
    is_private { true }
    metadata { {} }

    association :account
    association :user

    trait :for_opportunity do
      after(:build) do |comment|
        comment.commentable ||= create(:opportunity, account: comment.account)
      end
    end

    trait :for_task do
      after(:build) do |comment|
        opportunity = create(:opportunity, account: comment.account)
        comment.commentable ||= create(:task, account: comment.account, opportunity: opportunity)
      end
    end

    trait :for_contact do
      after(:build) do |comment|
        comment.commentable ||= create(:contact, account: comment.account)
      end
    end

    trait :private do
      is_private { true }
    end

    trait :public do
      is_private { false }
    end

    trait :edited do
      edited_at { Time.current }
      after(:build) do |comment|
        comment.content = "#{comment.content} [Editado]"
      end
    end

    trait :with_mentions do
      content { 'Comentário mencionando @usuario1 e @usuario2' }
      metadata do
        {
          mentions: [1, 2]
        }
      end
    end

    trait :with_metadata do
      metadata do
        {
          tags: %w[importante follow-up],
          source: 'web_app'
        }
      end
    end

    trait :deleted do
      deleted_at { Time.current }
    end

    trait :long_content do
      content { 'A' * 1000 }
    end

    # Factory para criar comentário completo
    factory :comment_complete do
      for_opportunity
      with_metadata
      edited
      content { 'Comentário completo com todos os campos preenchidos' }
    end
  end
end
