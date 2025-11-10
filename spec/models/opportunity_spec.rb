# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Opportunity do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:user) { create(:user, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:contact) }
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:stage) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:opportunity_id) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
    it { is_expected.to validate_numericality_of(:estimated_value).is_greater_than_or_equal_to(0).allow_nil }

    context 'when status is lost' do
      it 'requires lost_reason' do
        opportunity = build(:opportunity, account: account, contact: contact, status: :lost, lost_reason: nil)
        expect(opportunity).not_to be_valid
        expect(opportunity.errors[:lost_reason]).to be_present
      end

      it 'is valid with lost_reason' do
        opportunity = build(:opportunity, account: account, contact: contact, status: :lost, lost_reason: 'Paciente desistiu')
        expect(opportunity).to be_valid
      end
    end

    context 'when suggested_appointment_date is in the past' do
      it 'is invalid' do
        opportunity = build(:opportunity, account: account, contact: contact, suggested_appointment_date: 1.day.ago)
        expect(opportunity).not_to be_valid
        expect(opportunity.errors[:suggested_appointment_date]).to be_present
      end
    end

    context 'when suggested_appointment_date is in the future' do
      it 'is valid' do
        opportunity = build(:opportunity, account: account, contact: contact, suggested_appointment_date: 1.week.from_now)
        expect(opportunity).to be_valid
      end
    end

    context 'when opportunity_id uniqueness' do
      it 'validates uniqueness within account scope' do
        create(:opportunity, account: account, opportunity_id: 'OPP-12345678')
        duplicate = build(:opportunity, account: account, opportunity_id: 'OPP-12345678')
        expect(duplicate).not_to be_valid
      end

      it 'allows same opportunity_id in different accounts' do
        account2 = create(:account)
        create(:opportunity, account: account, opportunity_id: 'OPP-12345678')
        duplicate = build(:opportunity, account: account2, opportunity_id: 'OPP-12345678')
        expect(duplicate).to be_valid
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:contact) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:conversation).optional }
    it { is_expected.to belong_to(:assigned_agent).class_name('User').optional }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to have_many(:tasks).dependent(:destroy) }
    it { is_expected.to have_many(:stage_transitions).dependent(:destroy) }
    it { is_expected.to have_many(:comments).dependent(:destroy) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(open: 0, won: 1, lost: 2, abandoned: 3) }
    it { is_expected.to define_enum_for(:priority).with_values(low: 0, medium: 1, high: 2, urgent: 3) }

    it {
      expect(subject).to define_enum_for(:stage).with_values(
        new_lead: 0,
        qualification: 1,
        scheduling_pending: 2,
        appointment_scheduled: 3,
        appointment_confirmed: 4,
        completed: 5,
        follow_up: 6
      )
    }
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only open opportunities' do
        open_opp = create(:opportunity, account: account, status: :open)
        create(:opportunity, account: account, status: :won)
        create(:opportunity, :lost, account: account)

        expect(described_class.active).to contain_exactly(open_opp)
      end
    end

    describe '.by_stage' do
      it 'filters by stage' do
        create(:opportunity, account: account, stage: :new_lead)
        opp2 = create(:opportunity, account: account, stage: :qualification)
        create(:opportunity, account: account, stage: :scheduling_pending)

        expect(described_class.by_stage(:qualification)).to contain_exactly(opp2)
      end
    end

    describe '.by_status' do
      it 'filters by status' do
        create(:opportunity, account: account, status: :open)
        opp2 = create(:opportunity, account: account, status: :won)
        create(:opportunity, :lost, account: account)

        expect(described_class.by_status(:won)).to contain_exactly(opp2)
      end
    end

    describe '.high_priority' do
      it 'returns high and urgent priorities' do
        high = create(:opportunity, account: account, priority: :high)
        urgent = create(:opportunity, account: account, priority: :urgent)
        create(:opportunity, account: account, priority: :medium)

        expect(described_class.high_priority).to contain_exactly(high, urgent)
      end
    end

    describe '.assigned_to' do
      it 'returns opportunities assigned to agent' do
        agent = create(:user, account: account)
        assigned = create(:opportunity, account: account, assigned_agent: agent)
        create(:opportunity, account: account, assigned_agent: nil)

        expect(described_class.assigned_to(agent.id)).to contain_exactly(assigned)
      end
    end

    describe '.unassigned' do
      it 'returns unassigned opportunities' do
        agent = create(:user, account: account)
        unassigned = create(:opportunity, account: account, assigned_agent: nil)
        create(:opportunity, account: account, assigned_agent: agent)

        expect(described_class.unassigned).to include(unassigned)
      end
    end

    describe '.this_month' do
      it 'returns opportunities created this month' do
        this_month = create(:opportunity, account: account, created_at: Time.current)
        last_month = create(:opportunity, account: account, created_at: 2.months.ago)

        expect(described_class.this_month).to include(this_month)
        expect(described_class.this_month).not_to include(last_month)
      end
    end

    describe '.this_week' do
      it 'returns opportunities created this week' do
        this_week = create(:opportunity, account: account, created_at: Time.current)
        last_week = create(:opportunity, account: account, created_at: 2.weeks.ago)

        expect(described_class.this_week).to include(this_week)
        expect(described_class.this_week).not_to include(last_week)
      end
    end

    describe '.exclude_deleted' do
      it 'excludes soft deleted opportunities' do
        active = create(:opportunity, account: account, deleted_at: nil)
        deleted = create(:opportunity, account: account, deleted_at: Time.current)

        expect(described_class.exclude_deleted).to include(active)
        expect(described_class.exclude_deleted).not_to include(deleted)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation :generate_opportunity_id' do
      it 'generates opportunity_id on create' do
        opportunity = build(:opportunity, account: account, contact: contact, opportunity_id: nil)
        opportunity.save!
        expect(opportunity.opportunity_id).to be_present
        expect(opportunity.opportunity_id).to match(/^OPP-[A-Z0-9]{8}$/)
      end

      it 'does not override existing opportunity_id' do
        opportunity = create(:opportunity, account: account, opportunity_id: 'OPP-CUSTOM01')
        expect(opportunity.opportunity_id).to eq('OPP-CUSTOM01')
      end
    end

    describe 'after_create :create_initial_stage_transition' do
      it 'creates initial stage transition' do
        opportunity = create(:opportunity, account: account, stage: :new_lead)
        expect(opportunity.stage_transitions.count).to eq(1)
        transition = opportunity.stage_transitions.first
        expect(transition.from_stage).to be_nil
        expect(transition.to_stage).to eq('new_lead')
      end
    end

    describe 'after_update :handle_stage_change' do
      it 'creates stage transition record when stage changes' do
        opportunity = create(:opportunity, account: account, stage: :new_lead)
        opportunity.update(stage: :qualification)
        expect(opportunity.stage_transitions.count).to eq(2)
        transition = opportunity.stage_transitions.last
        expect(transition.from_stage).to eq('new_lead')
        expect(transition.to_stage).to eq('qualification')
      end
    end

    describe 'after_update :handle_status_change' do
      it 'sets closed_at when status changes to won' do
        opportunity = create(:opportunity, account: account, status: :open)
        opportunity.update(status: :won)
        expect(opportunity.closed_at).to be_present
      end

      it 'sets closed_at when status changes to lost' do
        opportunity = create(:opportunity, account: account, status: :open, lost_reason: 'Test')
        opportunity.update(status: :lost)
        expect(opportunity.closed_at).to be_present
      end

      it 'clears closed_at when status changes back to open' do
        opportunity = create(:opportunity, account: account, status: :won, closed_at: Time.current)
        opportunity.update(status: :open)
        expect(opportunity.closed_at).to be_nil
      end
    end
  end

  describe 'instance methods' do
    describe '#days_in_current_stage' do
      it 'returns 0 for new opportunities' do
        opportunity = create(:opportunity, account: account)
        expect(opportunity.days_in_current_stage).to eq(0)
      end

      it 'calculates days since last transition' do
        opportunity = create(:opportunity, account: account)
        transition_time = 5.days.ago

        # Limpa a transição inicial criada automaticamente
        opportunity.stage_transitions.destroy_all

        # Cria uma transição inicial com created_at no passado
        create(:stage_transition,
               :initial_transition,
               opportunity: opportunity,
               account: account,
               created_at: transition_time)

        # Atualiza o stage para criar uma nova transição
        opportunity.update(stage: :qualification)

        # Verifica que temos duas transições
        expect(opportunity.stage_transitions.count).to eq(2)

        # A última transição deve ser a de qualification
        last_transition = StageTransition.unscoped.where(opportunity_id: opportunity.id).order(created_at: :desc).first
        expect(last_transition.to_stage).to eq('qualification')

        # Recarrega a oportunidade
        opportunity.reload

        # O método deve calcular baseado na última transição (qualification)
        # que foi criada agora, então a diferença deve ser 0 dias
        # Mas queremos testar com a transição anterior, então vamos atualizar a última transição
        StageTransition.where(id: last_transition.id).update_all(created_at: transition_time)

        # Recarrega tudo
        opportunity.reload

        # Agora deve calcular 5 dias desde a última transição
        expect(opportunity.days_in_current_stage).to eq(5)
      end
    end

    describe '#mark_as_won' do
      it 'updates status to won and sets closed_at' do
        opportunity = create(:opportunity, account: account, status: :open)
        opportunity.mark_as_won
        expect(opportunity.status).to eq('won')
        expect(opportunity.closed_at).to be_present
      end
    end

    describe '#mark_as_lost' do
      it 'updates status to lost with reason' do
        opportunity = create(:opportunity, account: account, status: :open)
        opportunity.mark_as_lost(reason: 'Paciente desistiu')
        expect(opportunity.status).to eq('lost')
        expect(opportunity.lost_reason).to eq('Paciente desistiu')
        expect(opportunity.closed_at).to be_present
      end
    end

    describe '#mark_as_abandoned' do
      it 'updates status to abandoned' do
        opportunity = create(:opportunity, account: account, status: :open)
        opportunity.mark_as_abandoned
        expect(opportunity.status).to eq('abandoned')
        expect(opportunity.closed_at).to be_present
      end
    end

    describe '#can_transition_to?' do
      it 'returns false for same stage' do
        opportunity = create(:opportunity, account: account, stage: :new_lead)
        expect(opportunity.can_transition_to?(:new_lead)).to be false
      end

      it 'returns false if closed' do
        opportunity = create(:opportunity, account: account, status: :won)
        expect(opportunity.can_transition_to?(:qualification)).to be false
      end

      it 'returns true for valid transition' do
        opportunity = create(:opportunity, account: account, stage: :new_lead)
        expect(opportunity.can_transition_to?(:qualification)).to be true
      end
    end

    describe '#soft_delete' do
      it 'sets deleted_at' do
        opportunity = create(:opportunity, account: account)
        opportunity.soft_delete
        expect(opportunity.deleted_at).to be_present
      end
    end

    describe '#restore' do
      it 'clears deleted_at' do
        opportunity = create(:opportunity, account: account, deleted_at: Time.current)
        opportunity.restore
        expect(opportunity.deleted_at).to be_nil
      end
    end

    describe '#closed?' do
      it 'returns true for won status' do
        opportunity = create(:opportunity, account: account, status: :won)
        expect(opportunity.closed?).to be true
      end

      it 'returns true for lost status' do
        opportunity = create(:opportunity, account: account, status: :lost, lost_reason: 'Test')
        expect(opportunity.closed?).to be true
      end

      it 'returns false for open status' do
        opportunity = create(:opportunity, account: account, status: :open)
        expect(opportunity.closed?).to be false
      end
    end
  end

  describe 'class methods' do
    describe '.conversion_rate' do
      it 'calculates conversion rate correctly' do
        start_date = 1.month.ago
        end_date = Time.current

        create(:opportunity, account: account, status: :won, created_at: 2.weeks.ago, closed_at: 1.week.ago)
        create(:opportunity, account: account, status: :won, created_at: 3.weeks.ago, closed_at: 2.weeks.ago)
        create(:opportunity, account: account, status: :lost, created_at: 2.weeks.ago, closed_at: 1.week.ago, lost_reason: 'Test')

        rate = described_class.conversion_rate(account.id, start_date, end_date)
        expect(rate).to eq(66.67)
      end

      it 'returns 0.0 when no opportunities' do
        rate = described_class.conversion_rate(account.id, 1.month.ago, Time.current)
        expect(rate).to eq(0.0)
      end
    end

    describe '.average_deal_value' do
      it 'calculates average deal value' do
        create(:opportunity, account: account, status: :won, estimated_value: 500.00)
        create(:opportunity, account: account, status: :won, estimated_value: 1000.00)
        create(:opportunity, account: account, status: :open, estimated_value: 750.00)

        average = described_class.average_deal_value(account.id)
        expect(average).to eq(750.00)
      end

      it 'returns 0.0 when no won opportunities' do
        average = described_class.average_deal_value(account.id)
        expect(average).to eq(0.0)
      end
    end

    describe '.by_referral_source' do
      it 'groups opportunities by referral source' do
        create(:opportunity, account: account, referral_source: 'Instagram')
        create(:opportunity, account: account, referral_source: 'Instagram')
        create(:opportunity, account: account, referral_source: 'Google Ads')

        result = described_class.by_referral_source(account.id)
        expect(result['Instagram']).to eq(2)
        expect(result['Google Ads']).to eq(1)
      end
    end
  end

  describe 'default scope' do
    it 'excludes deleted opportunities by default' do
      active = create(:opportunity, account: account, deleted_at: nil)
      deleted = create(:opportunity, account: account, deleted_at: Time.current)

      expect(described_class.all).to include(active)
      expect(described_class.all).not_to include(deleted)
    end
  end

  describe 'workflow concern methods' do
    describe '#transition_to' do
      it 'transitions to new stage' do
        opportunity = create(:opportunity, account: account, stage: :new_lead)
        expect(opportunity.can_transition_to?(:qualification)).to be true
        result = opportunity.transition_to(:qualification, performed_by: user)
        expect(result).to be true
        expect(opportunity.reload.stage).to eq('qualification')
      end

      it 'returns false for invalid transition' do
        opportunity = create(:opportunity, account: account, status: :won)
        result = opportunity.transition_to(:qualification)
        expect(result).to be false
      end
    end

    describe '#next_valid_stage' do
      it 'returns next stage for new_lead' do
        opportunity = create(:opportunity, account: account, stage: :new_lead)
        expect(opportunity.next_valid_stage).to eq(:qualification)
      end

      it 'returns nil for follow_up' do
        opportunity = create(:opportunity, account: account, stage: :follow_up)
        expect(opportunity.next_valid_stage).to be_nil
      end
    end

    describe '#funnel_progress_percentage' do
      it 'calculates progress percentage' do
        opportunity = create(:opportunity, account: account, stage: :qualification)
        # qualification is stage 1 out of 7 stages (0-6)
        # (1+1)/7 * 100 = 28.57%
        expect(opportunity.funnel_progress_percentage).to eq(28.57)
      end
    end
  end
end
