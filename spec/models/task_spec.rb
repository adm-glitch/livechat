# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Task do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) { create(:opportunity, account: account, contact: contact) }
  let(:user) { create(:user, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:opportunity) }
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:priority) }
    it { is_expected.to validate_presence_of(:due_date) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }

    context 'when status is completed' do
      it 'requires result_notes' do
        task = build(:task, opportunity: opportunity, account: account, status: :completed, result_notes: nil)
        expect(task).not_to be_valid
        expect(task.errors[:result_notes]).to be_present
      end

      it 'is valid with result_notes' do
        task = build(:task, opportunity: opportunity, account: account, status: :completed, result_notes: 'Concluído')
        expect(task).to be_valid
      end
    end

    context 'when due_date is in the past on create' do
      it 'is invalid' do
        task = build(:task, opportunity: opportunity, account: account, due_date: 1.day.ago)
        expect(task).not_to be_valid
        expect(task.errors[:due_date]).to be_present
      end
    end

    context 'when due_date is in the future' do
      it 'is valid' do
        task = build(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now)
        expect(task).to be_valid
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:opportunity) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:assigned_to).class_name('User').optional }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to belong_to(:contact).optional }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:priority).with_values(low: 0, medium: 1, high: 2, urgent: 3) }
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, in_progress: 1, completed: 2, cancelled: 3) }
  end

  describe 'scopes' do
    describe '.pending' do
      it 'returns only pending tasks' do
        pending_task = create(:task, opportunity: opportunity, account: account, status: :pending)
        create(:task, opportunity: opportunity, account: account, status: :completed, result_notes: 'Done')
        create(:task, opportunity: opportunity, account: account, status: :cancelled)

        expect(described_class.pending).to contain_exactly(pending_task)
      end
    end

    describe '.completed' do
      it 'returns only completed tasks' do
        completed_task = create(:task, opportunity: opportunity, account: account, status: :completed, result_notes: 'Done')
        create(:task, opportunity: opportunity, account: account, status: :pending)
        create(:task, opportunity: opportunity, account: account, status: :in_progress)

        expect(described_class.completed).to contain_exactly(completed_task)
      end
    end

    describe '.overdue' do
      it 'returns overdue tasks that are not completed' do
        # Cria tarefa com data futura e depois atualiza para o passado
        overdue_task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now, status: :pending)
        overdue_task.update_column(:due_date, 1.day.ago)

        completed_task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now, status: :completed,
                                       result_notes: 'Done')
        completed_task.update_column(:due_date, 1.day.ago)

        create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now, status: :pending)

        expect(described_class.overdue).to contain_exactly(overdue_task)
      end
    end

    describe '.due_today' do
      it 'returns tasks due today' do
        today_task = create(:task, opportunity: opportunity, account: account, due_date: Time.current.end_of_day)
        create(:task, opportunity: opportunity, account: account, due_date: 1.day.from_now)
        # Cria com data futura e atualiza para o passado
        past_task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now)
        past_task.update_column(:due_date, 1.day.ago)

        expect(described_class.due_today).to include(today_task)
      end
    end

    describe '.due_this_week' do
      it 'returns tasks due this week' do
        this_week_task = create(:task, opportunity: opportunity, account: account, due_date: Time.current.end_of_week)
        create(:task, opportunity: opportunity, account: account, due_date: 2.weeks.from_now)

        expect(described_class.due_this_week).to include(this_week_task)
      end
    end

    describe '.assigned_to' do
      it 'returns tasks assigned to user' do
        assigned_task = create(:task, opportunity: opportunity, account: account, assigned_to: user)
        create(:task, opportunity: opportunity, account: account, assigned_to: nil)

        expect(described_class.assigned_to(user.id)).to contain_exactly(assigned_task)
      end
    end

    describe '.by_priority' do
      it 'filters by priority' do
        high_task = create(:task, opportunity: opportunity, account: account, priority: :high)
        create(:task, opportunity: opportunity, account: account, priority: :medium)

        expect(described_class.by_priority(:high)).to contain_exactly(high_task)
      end
    end

    describe '.exclude_deleted' do
      it 'excludes soft deleted tasks' do
        active_task = create(:task, opportunity: opportunity, account: account, deleted_at: nil)
        deleted_task = create(:task, opportunity: opportunity, account: account, deleted_at: Time.current)

        expect(described_class.exclude_deleted).to include(active_task)
        expect(described_class.exclude_deleted).not_to include(deleted_task)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_update :set_completed_at' do
      it 'sets completed_at when status changes to completed' do
        task = create(:task, opportunity: opportunity, account: account, status: :pending)
        task.update(status: :completed, result_notes: 'Done')
        expect(task.completed_at).to be_present
      end

      it 'does not override existing completed_at' do
        completed_time = 1.hour.ago
        task = create(:task, opportunity: opportunity, account: account, status: :completed, completed_at: completed_time, result_notes: 'Done')
        task.update(description: 'Updated')
        expect(task.completed_at).to be_within(1.second).of(completed_time)
      end
    end

    describe 'after_update :notify_assigned_user' do
      it 'is called when assigned_to_id changes' do
        task = create(:task, opportunity: opportunity, account: account, assigned_to: nil)
        expect(task).to receive(:notify_assigned_user)
        task.update(assigned_to: user)
      end

      it 'is not called when assigned_to_id does not change' do
        task = create(:task, opportunity: opportunity, account: account, assigned_to: user)
        expect(task).not_to receive(:notify_assigned_user)
        task.update(description: 'Updated')
      end
    end
  end

  describe 'instance methods' do
    describe '#overdue?' do
      it 'returns true for overdue pending tasks' do
        task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now, status: :pending)
        task.update_column(:due_date, 1.day.ago)
        expect(task.overdue?).to be true
      end

      it 'returns false for completed tasks' do
        task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now, status: :completed, result_notes: 'Done')
        task.update_column(:due_date, 1.day.ago)
        expect(task.overdue?).to be false
      end

      it 'returns false for cancelled tasks' do
        task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now, status: :cancelled)
        task.update_column(:due_date, 1.day.ago)
        expect(task.overdue?).to be false
      end

      it 'returns false for future tasks' do
        task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now, status: :pending)
        expect(task.overdue?).to be false
      end
    end

    describe '#mark_as_completed' do
      it 'updates status to completed with notes' do
        task = create(:task, opportunity: opportunity, account: account, status: :pending)
        task.mark_as_completed(notes: 'Tarefa concluída')
        expect(task.status).to eq('completed')
        expect(task.result_notes).to eq('Tarefa concluída')
        expect(task.completed_at).to be_present
      end
    end

    describe '#mark_as_cancelled' do
      it 'updates status to cancelled' do
        task = create(:task, opportunity: opportunity, account: account, status: :pending)
        task.mark_as_cancelled
        expect(task.status).to eq('cancelled')
      end
    end

    describe '#days_until_due' do
      it 'calculates days until due date' do
        task = create(:task, opportunity: opportunity, account: account, due_date: 5.days.from_now)
        expect(task.days_until_due).to eq(5)
      end

      it 'returns negative number for overdue tasks' do
        task = create(:task, opportunity: opportunity, account: account, due_date: 1.week.from_now)
        task.update_column(:due_date, 3.days.ago)
        expect(task.days_until_due).to eq(-3)
      end

      it 'returns nil if due_date is not present' do
        task = build(:task, opportunity: opportunity, account: account, due_date: nil)
        expect(task.days_until_due).to be_nil
      end
    end

    describe '#soft_delete' do
      it 'sets deleted_at' do
        task = create(:task, opportunity: opportunity, account: account)
        task.soft_delete
        expect(task.deleted_at).to be_present
      end
    end

    describe '#restore' do
      it 'clears deleted_at' do
        task = create(:task, opportunity: opportunity, account: account, deleted_at: Time.current)
        task.restore
        expect(task.deleted_at).to be_nil
      end
    end
  end

  describe 'default scope' do
    it 'excludes deleted tasks by default' do
      active_task = create(:task, opportunity: opportunity, account: account, deleted_at: nil)
      deleted_task = create(:task, opportunity: opportunity, account: account, deleted_at: Time.current)

      expect(described_class.all).to include(active_task)
      expect(described_class.all).not_to include(deleted_task)
    end
  end

  describe 'factory validation' do
    it 'creates valid task object' do
      task = create(:task, opportunity: opportunity, account: account)
      expect(task).to be_valid
      expect(task.title).to be_present
      expect(task.opportunity).to eq(opportunity)
      expect(task.account).to eq(account)
    end

    it 'creates completed task with traits' do
      task = create(:task, :completed, opportunity: opportunity, account: account)
      expect(task.status).to eq('completed')
      expect(task.completed_at).to be_present
      expect(task.result_notes).to be_present
    end

    it 'creates overdue task with traits' do
      task = create(:task, :overdue, opportunity: opportunity, account: account)
      task.reload # Recarrega para garantir que temos o due_date atualizado
      expect(task.overdue?).to be true
    end
  end
end
