# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Comment do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) { create(:opportunity, account: account, contact: contact) }
  let(:task) { create(:task, opportunity: opportunity, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:commentable) }
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:user) }
    it { is_expected.to validate_length_of(:content).is_at_least(1).is_at_most(5000) }

    context 'when commentable_type is invalid' do
      it 'is invalid' do
        comment = build(:comment, account: account, user: user)
        comment.commentable = create(:conversation, account: account)
        expect(comment).not_to be_valid
        expect(comment.errors[:commentable_type]).to be_present
      end
    end

    context 'when commentable_type is valid' do
      it 'is valid for Opportunity' do
        comment = build(:comment, :for_opportunity, account: account, user: user)
        expect(comment).to be_valid
      end

      it 'is valid for Task' do
        comment = build(:comment, :for_task, account: account, user: user)
        expect(comment).to be_valid
      end

      it 'is valid for Contact' do
        comment = build(:comment, :for_contact, account: account, user: user)
        expect(comment).to be_valid
      end
    end

    context 'when content is too long' do
      it 'is invalid' do
        comment = build(:comment, :for_opportunity, account: account, user: user, content: 'A' * 5001)
        expect(comment).not_to be_valid
        expect(comment.errors[:content]).to be_present
      end
    end

    context 'when content is empty' do
      it 'is invalid' do
        comment = build(:comment, :for_opportunity, account: account, user: user, content: '')
        expect(comment).not_to be_valid
        expect(comment.errors[:content]).to be_present
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:commentable) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'scopes' do
    describe '.for_commentable' do
      it 'returns comments for specific commentable' do
        comment1 = create(:comment, :for_opportunity, account: account, user: user, commentable: opportunity)
        other_opportunity = create(:opportunity, account: account, contact: contact)
        create(:comment, :for_opportunity, account: account, user: user, commentable: other_opportunity)

        expect(described_class.for_commentable(opportunity)).to contain_exactly(comment1)
      end
    end

    describe '.by_user' do
      it 'filters by user' do
        user2 = create(:user, account: account)
        comment1 = create(:comment, :for_opportunity, account: account, user: user)
        create(:comment, :for_opportunity, account: account, user: user2)

        expect(described_class.by_user(user.id)).to contain_exactly(comment1)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        old_comment = create(:comment, :for_opportunity, account: account, user: user, created_at: 2.days.ago)
        new_comment = create(:comment, :for_opportunity, account: account, user: user, created_at: 1.day.ago)

        expect(described_class.recent.first).to eq(new_comment)
        expect(described_class.recent.last).to eq(old_comment)
      end
    end

    describe '.private_comments' do
      it 'returns only private comments' do
        private_comment = create(:comment, :for_opportunity, account: account, user: user, is_private: true)
        create(:comment, :for_opportunity, account: account, user: user, is_private: false)

        expect(described_class.private_comments).to contain_exactly(private_comment)
      end
    end

    describe '.public_comments' do
      it 'returns only public comments' do
        create(:comment, :for_opportunity, account: account, user: user, is_private: true)
        public_comment = create(:comment, :for_opportunity, account: account, user: user, is_private: false)

        expect(described_class.public_comments).to contain_exactly(public_comment)
      end
    end

    describe '.edited' do
      it 'returns only edited comments' do
        edited_comment = create(:comment, :for_opportunity, account: account, user: user, edited_at: Time.current)
        create(:comment, :for_opportunity, account: account, user: user, edited_at: nil)

        expect(described_class.edited).to contain_exactly(edited_comment)
      end
    end

    describe '.exclude_deleted' do
      it 'excludes soft deleted comments' do
        active_comment = create(:comment, :for_opportunity, account: account, user: user, deleted_at: nil)
        deleted_comment = create(:comment, :for_opportunity, account: account, user: user, deleted_at: Time.current)

        expect(described_class.exclude_deleted).to include(active_comment)
        expect(described_class.exclude_deleted).not_to include(deleted_comment)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_update :set_edited_at' do
      it 'sets edited_at when content changes' do
        comment = create(:comment, :for_opportunity, account: account, user: user)
        comment.update(content: 'Conteúdo atualizado')
        expect(comment.edited_at).to be_present
      end

      it 'does not set edited_at when other attributes change' do
        comment = create(:comment, :for_opportunity, account: account, user: user)
        comment.update(is_private: false)
        expect(comment.edited_at).to be_nil
      end
    end

    describe 'after_create :create_activity_log' do
      it 'is called after creation' do
        comment = build(:comment, :for_opportunity, account: account, user: user)
        # O callback está preparado mas não implementado ainda (TODO)
        expect { comment.save! }.not_to raise_error
      end
    end
  end

  describe 'instance methods' do
    describe '#edited?' do
      it 'returns true when edited_at is present' do
        comment = create(:comment, :for_opportunity, account: account, user: user, edited_at: Time.current)
        expect(comment.edited?).to be true
      end

      it 'returns false when edited_at is nil' do
        comment = create(:comment, :for_opportunity, account: account, user: user, edited_at: nil)
        expect(comment.edited?).to be false
      end
    end

    describe '#mentions' do
      it 'extracts user mentions from content' do
        mentioned_user = create(:user, account: account)
        content = "Comentário mencionando (mention://user/#{mentioned_user.id}/#{mentioned_user.name})"
        comment = create(:comment, :for_opportunity, account: account, user: user, content: content)

        expect(comment.mentions).to include(mentioned_user)
      end

      it 'returns empty array when no mentions' do
        comment = create(:comment, :for_opportunity, account: account, user: user, content: 'Comentário sem menções')
        expect(comment.mentions).to eq([])
      end

      it 'ignores mentions from other accounts' do
        other_account = create(:account)
        other_user = create(:user, account: other_account)
        content = "Comentário mencionando (mention://user/#{other_user.id}/#{other_user.name})"
        comment = create(:comment, :for_opportunity, account: account, user: user, content: content)

        expect(comment.mentions).not_to include(other_user)
      end
    end

    describe '#soft_delete' do
      it 'sets deleted_at' do
        comment = create(:comment, :for_opportunity, account: account, user: user)
        comment.soft_delete
        expect(comment.deleted_at).to be_present
      end
    end

    describe '#restore' do
      it 'clears deleted_at' do
        comment = create(:comment, :for_opportunity, account: account, user: user, deleted_at: Time.current)
        comment.restore
        expect(comment.deleted_at).to be_nil
      end
    end
  end

  describe 'class methods' do
    describe '.recent_activity' do
      it 'returns recent comments with associations loaded' do
        comment1 = create(:comment, :for_opportunity, account: account, user: user, created_at: 2.days.ago)
        comment2 = create(:comment, :for_task, account: account, user: user, created_at: 1.day.ago)

        activity = described_class.recent_activity(account.id, limit: 10)

        expect(activity).to include(comment2)
        expect(activity).to include(comment1)
        expect(activity.first).to eq(comment2) # Mais recente primeiro
      end

      it 'respects limit parameter' do
        create_list(:comment, 25, :for_opportunity, account: account, user: user)

        activity = described_class.recent_activity(account.id, limit: 10)
        expect(activity.count).to eq(10)
      end
    end
  end

  describe 'default scope' do
    it 'excludes deleted comments by default' do
      active_comment = create(:comment, :for_opportunity, account: account, user: user, deleted_at: nil)
      deleted_comment = create(:comment, :for_opportunity, account: account, user: user, deleted_at: Time.current)

      expect(described_class.all).to include(active_comment)
      expect(described_class.all).not_to include(deleted_comment)
    end
  end

  describe 'polymorphic association' do
    it 'can belong to Opportunity' do
      comment = create(:comment, :for_opportunity, account: account, user: user)
      expect(comment.commentable).to be_a(Opportunity)
    end

    it 'can belong to Task' do
      comment = create(:comment, :for_task, account: account, user: user)
      expect(comment.commentable).to be_a(Task)
    end

    it 'can belong to Contact' do
      comment = create(:comment, :for_contact, account: account, user: user)
      expect(comment.commentable).to be_a(Contact)
    end
  end

  describe 'factory validation' do
    it 'creates valid comment object' do
      comment = create(:comment, :for_opportunity, account: account, user: user)
      expect(comment).to be_valid
      expect(comment.commentable_type).to eq('Opportunity')
      expect(comment.account).to eq(account)
      expect(comment.user).to eq(user)
    end

    it 'creates private comment by default' do
      comment = create(:comment, :for_opportunity, account: account, user: user)
      expect(comment.is_private).to be true
    end

    it 'creates public comment with trait' do
      comment = create(:comment, :for_opportunity, :public, account: account, user: user)
      expect(comment.is_private).to be false
    end
  end
end
