# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StageTransition do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) { create(:opportunity, account: account, contact: contact) }
  let(:user) { create(:user, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:opportunity) }
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:to_stage) }

    context 'when from_stage is nil' do
      it 'is valid for initial transition' do
        transition = build(:stage_transition, :initial_transition, opportunity: opportunity, account: account)
        expect(transition).to be_valid
      end
    end

    context 'when stages are the same' do
      it 'is invalid' do
        transition = build(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'new_lead')
        expect(transition).not_to be_valid
        expect(transition.errors[:to_stage]).to be_present
      end
    end

    context 'when to_stage is invalid' do
      it 'is invalid' do
        transition = build(:stage_transition, opportunity: opportunity, account: account, to_stage: 'invalid_stage')
        expect(transition).not_to be_valid
        expect(transition.errors[:to_stage]).to be_present
      end
    end

    context 'when from_stage is invalid' do
      it 'is invalid' do
        transition = build(:stage_transition, opportunity: opportunity, account: account, from_stage: 'invalid_stage', to_stage: 'qualification')
        expect(transition).not_to be_valid
        expect(transition.errors[:from_stage]).to be_present
      end
    end

    context 'when stages are valid' do
      it 'is valid' do
        transition = build(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
        expect(transition).to be_valid
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:opportunity) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:performed_by).class_name('User').optional }
  end

  describe 'scopes' do
    describe '.for_opportunity' do
      it 'returns transitions for specific opportunity' do
        # A oportunidade já tem uma transição inicial criada automaticamente
        initial_transition = opportunity.stage_transitions.first
        transition1 = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
        other_opportunity = create(:opportunity, account: account, contact: contact)
        create(:stage_transition, opportunity: other_opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')

        expect(described_class.for_opportunity(opportunity.id)).to contain_exactly(initial_transition, transition1)
      end
    end

    describe '.by_stage' do
      it 'filters by to_stage' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        transition1 = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'qualification',
                                  to_stage: 'scheduling_pending')

        expect(described_class.by_stage('qualification')).to contain_exactly(transition1)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        old_transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification',
                                                   created_at: 2.days.ago)
        new_transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'qualification',
                                                   to_stage: 'scheduling_pending', created_at: 1.day.ago)

        expect(described_class.recent.first).to eq(new_transition)
        expect(described_class.recent.last).to eq(old_transition)
      end
    end

    describe '.this_month' do
      it 'returns transitions created this month' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        this_month = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification',
                                               created_at: Time.current)
        last_month = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'qualification',
                                               to_stage: 'scheduling_pending', created_at: 2.months.ago)

        expect(described_class.this_month).to include(this_month)
        expect(described_class.this_month).not_to include(last_month)
      end
    end

    describe '.automated' do
      it 'returns automated transitions' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        automated = create(:stage_transition, :automated, opportunity: opportunity, account: account, from_stage: 'new_lead',
                                                          to_stage: 'qualification')
        create(:stage_transition, :manual, opportunity: opportunity, account: account, from_stage: 'qualification',
                                           to_stage: 'scheduling_pending')

        expect(described_class.automated).to contain_exactly(automated)
      end
    end

    describe '.manual' do
      it 'returns manual transitions' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        create(:stage_transition, :automated, opportunity: opportunity, account: account, from_stage: 'new_lead',
                                              to_stage: 'qualification')
        manual = create(:stage_transition, :manual, opportunity: opportunity, account: account, from_stage: 'qualification',
                                                    to_stage: 'scheduling_pending')

        expect(described_class.manual).to contain_exactly(manual)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create :calculate_transition_duration' do
      context 'when from_stage is nil' do
        it 'does not calculate duration' do
          transition = build(:stage_transition, :initial_transition, opportunity: opportunity, account: account)
          transition.save!
          expect(transition.transition_duration_seconds).to be_nil
        end
      end

      context 'when previous transition exists' do
        it 'calculates duration based on previous transition' do
          # Limpa transições iniciais e cria uma transição inicial manualmente
          opportunity.stage_transitions.destroy_all
          create(:stage_transition, :initial_transition, opportunity: opportunity, account: account, created_at: 1.day.ago)
          new_transition = build(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
          new_transition.save!

          expect(new_transition.transition_duration_seconds).to be_within(100).of(86_400) # ~1 dia
        end
      end

      context 'when no previous transition exists' do
        it 'does not calculate duration' do
          # Limpa transições iniciais para este teste
          opportunity.stage_transitions.destroy_all
          transition = build(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
          transition.save!
          expect(transition.transition_duration_seconds).to be_nil
        end
      end
    end
  end

  describe 'instance methods' do
    describe '#automated?' do
      it 'returns true for automated transitions' do
        transition = create(:stage_transition, :automated, opportunity: opportunity, account: account, from_stage: 'new_lead',
                                                           to_stage: 'qualification')
        expect(transition.automated?).to be true
      end

      it 'returns false for manual transitions' do
        transition = create(:stage_transition, :manual, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
        expect(transition.automated?).to be false
      end
    end

    describe '#duration_in_days' do
      it 'converts seconds to days' do
        transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification', transition_duration_seconds: 172_800) # 2 dias
        expect(transition.duration_in_days).to eq(2.0)
      end

      it 'returns nil when transition_duration_seconds is nil' do
        transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification',
                                               transition_duration_seconds: nil)
        expect(transition.duration_in_days).to be_nil
      end

      it 'rounds to 2 decimal places' do
        transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification', transition_duration_seconds: 100_000) # ~1.16 dias
        expect(transition.duration_in_days).to eq(1.16)
      end
    end
  end

  describe 'class methods' do
    describe '.average_time_in_stage' do
      it 'calculates average time in stage' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification', transition_duration_seconds: 86_400) # 1 dia
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification', transition_duration_seconds: 172_800) # 2 dias

        average = described_class.average_time_in_stage('qualification', account.id)
        expect(average).to eq(1.5) # (1 + 2) / 2 = 1.5 dias
      end

      it 'returns 0.0 when no transitions exist' do
        average = described_class.average_time_in_stage('qualification', account.id)
        expect(average).to eq(0.0)
      end

      it 'ignores transitions without duration' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification',
                                  transition_duration_seconds: nil)
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification',
                                  transition_duration_seconds: 86_400)

        average = described_class.average_time_in_stage('qualification', account.id)
        expect(average).to eq(1.0) # Apenas conta a que tem duração
      end
    end

    describe '.transition_count' do
      it 'counts transitions from one stage to another' do
        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'qualification', to_stage: 'scheduling_pending')

        count = described_class.transition_count('new_lead', 'qualification', account.id)
        expect(count).to eq(2)
      end

      it 'returns 0 when no transitions exist' do
        count = described_class.transition_count('new_lead', 'qualification', account.id)
        expect(count).to eq(0)
      end
    end

    describe '.conversion_funnel' do
      it 'returns funnel with transition counts by stage' do
        start_date = 1.month.ago
        end_date = Time.current

        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        create(:stage_transition, :initial_transition, opportunity: opportunity, account: account, created_at: 2.weeks.ago)
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification',
                                  created_at: 1.week.ago)
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification',
                                  created_at: 5.days.ago)

        funnel = described_class.conversion_funnel(account.id, start_date, end_date)

        expect(funnel['new_lead']).to eq(1)
        expect(funnel['qualification']).to eq(2)
        expect(funnel['scheduling_pending']).to eq(0)
      end

      it 'orders stages correctly' do
        start_date = 1.month.ago
        end_date = Time.current

        # Limpa transições iniciais para este teste
        opportunity.stage_transitions.destroy_all

        create(:stage_transition, :initial_transition, opportunity: opportunity, account: account, created_at: 2.weeks.ago)
        create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'completed', created_at: 1.week.ago)

        funnel = described_class.conversion_funnel(account.id, start_date, end_date)
        stages = funnel.keys.to_a

        expect(stages.first).to eq('new_lead')
        expect(stages.last).to eq('follow_up')
      end
    end
  end

  describe 'append-only behavior' do
    it 'allows creation' do
      transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
      expect(transition).to be_persisted
    end

    it 'does not prevent updates (Rails default behavior)' do
      transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
      transition.update(notes: 'Updated notes')
      expect(transition.notes).to eq('Updated notes')
    end

    # Nota: Para garantir comportamento append-only, considere adicionar validação ou callback
    # que previna updates após criação, ou usar gem como paper_trail
  end

  describe 'factory validation' do
    it 'creates valid stage transition object' do
      transition = create(:stage_transition, opportunity: opportunity, account: account, from_stage: 'new_lead', to_stage: 'qualification')
      expect(transition).to be_valid
      expect(transition.opportunity).to eq(opportunity)
      expect(transition.account).to eq(account)
    end

    it 'creates automated transition with traits' do
      transition = create(:stage_transition, :automated, opportunity: opportunity, account: account, from_stage: 'new_lead',
                                                         to_stage: 'qualification')
      expect(transition.automated?).to be true
    end

    it 'creates transition with notes' do
      transition = create(:stage_transition, :with_notes, opportunity: opportunity, account: account, from_stage: 'new_lead',
                                                          to_stage: 'qualification')
      expect(transition.notes).to be_present
    end
  end
end
