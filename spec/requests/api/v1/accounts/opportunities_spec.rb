# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Opportunities', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:other_account_user) { create(:user, account: other_account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe 'GET /api/v1/accounts/:account_id/opportunities' do
    context 'when authenticated' do
      before do
        create_list(:opportunity, 5, account: account, contact: contact)
        create_list(:opportunity, 3, account: other_account)
      end

      it 'returns opportunities for the account' do
        get "/api/v1/accounts/#{account.id}/opportunities",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq(5)
      end

      it 'filters by stage' do
        create(:opportunity, account: account, contact: contact, stage: :qualification)

        get "/api/v1/accounts/#{account.id}/opportunities",
            params: { stage: 'qualification' },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq(1)
        expect(json_response.first['stage']).to eq('qualification')
      end

      it 'filters by status' do
        create(:opportunity, account: account, contact: contact, status: :won)

        get "/api/v1/accounts/#{account.id}/opportunities",
            params: { status: 'won' },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq(1)
        expect(json_response.first['status']).to eq('won')
      end

      it 'filters by assigned_agent_id' do
        opportunity = create(:opportunity, account: account, contact: contact, assigned_agent: agent)

        get "/api/v1/accounts/#{account.id}/opportunities",
            params: { assigned_agent_id: agent.id },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq(opportunity.id)
      end

      it 'filters by priority' do
        create(:opportunity, account: account, contact: contact, priority: :high)

        get "/api/v1/accounts/#{account.id}/opportunities",
            params: { priority: 'high' },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq(1)
        expect(json_response.first['priority']).to eq('high')
      end

      it 'filters by date range' do
        old_opportunity = create(:opportunity, account: account, contact: contact, created_at: 2.months.ago)
        new_opportunity = create(:opportunity, account: account, contact: contact, created_at: 1.week.ago)

        get "/api/v1/accounts/#{account.id}/opportunities",
            params: {
              start_date: 1.month.ago.to_date.to_s,
              end_date: Date.current.to_s
            },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        opportunity_ids = json_response.map { |o| o['id'] }
        expect(opportunity_ids).to include(new_opportunity.id)
        expect(opportunity_ids).not_to include(old_opportunity.id)
      end

      it 'paginates results' do
        create_list(:opportunity, 25, account: account, contact: contact)

        get "/api/v1/accounts/#{account.id}/opportunities",
            params: { page: 1 },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq(20) # RESULTS_PER_PAGE
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/opportunities"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user from different account' do
      it 'returns only opportunities from their account' do
        create_list(:opportunity, 3, account: account, contact: contact)
        create_list(:opportunity, 2, account: other_account)

        get "/api/v1/accounts/#{account.id}/opportunities",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq(3)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/opportunities/:id' do
    let(:opportunity) { create(:opportunity, account: account, contact: contact) }

    context 'when authenticated' do
      it 'returns the opportunity' do
        get "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['id']).to eq(opportunity.id)
        expect(json_response['title']).to eq(opportunity.title)
      end

      it 'includes nested associations' do
        opportunity.update(assigned_agent: agent, conversation: conversation)

        get "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['contact']).to be_present
        expect(json_response['assigned_agent']).to be_present
        expect(json_response['conversation']).to be_present
      end
    end

    context 'when opportunity not found' do
      it 'returns 404' do
        get "/api/v1/accounts/#{account.id}/opportunities/999999",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
        json_response = response.parsed_body
        expect(json_response['error']).to eq('Opportunity not found')
      end
    end

    context 'when opportunity from different account' do
      let(:other_opportunity) { create(:opportunity, account: other_account) }

      it 'returns 404' do
        get "/api/v1/accounts/#{account.id}/opportunities/#{other_opportunity.id}",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/opportunities' do
    context 'when authenticated' do
      let(:valid_params) do
        {
          title: 'Nova Oportunidade',
          description: 'Descrição da oportunidade',
          contact_id: contact.id,
          service_type: 'Consulta Dermatológica',
          estimated_value: 500.00,
          priority: 'high',
          stage: 'new_lead'
        }
      end

      it 'creates an opportunity' do
        post "/api/v1/accounts/#{account.id}/opportunities",
             params: valid_params,
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:created)
        json_response = response.parsed_body
        expect(json_response['title']).to eq('Nova Oportunidade')
        expect(json_response['created_by']['id']).to eq(admin.id)
      end

      it 'sets created_by to current_user' do
        post "/api/v1/accounts/#{account.id}/opportunities",
             params: valid_params,
             headers: admin.create_new_auth_token

        opportunity = Opportunity.last
        expect(opportunity.created_by).to eq(admin)
      end

      it 'associates conversation if provided' do
        post "/api/v1/accounts/#{account.id}/opportunities",
             params: valid_params.merge(conversation_id: conversation.id),
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:created)
        opportunity = Opportunity.last
        expect(opportunity.conversation).to eq(conversation)
      end

      it 'rejects conversation from different account' do
        other_conversation = create(:conversation, account: other_account)

        post "/api/v1/accounts/#{account.id}/opportunities",
             params: valid_params.merge(conversation_id: other_conversation.id),
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('Conversation not found')
      end

      it 'returns validation errors' do
        post "/api/v1/accounts/#{account.id}/opportunities",
             params: { title: '' },
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to be_present
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/opportunities",
             params: { title: 'Test' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/opportunities/:id' do
    let(:opportunity) { create(:opportunity, account: account, contact: contact) }

    context 'when authenticated' do
      it 'updates the opportunity' do
        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
              params: { title: 'Updated Title', priority: 'urgent' },
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['title']).to eq('Updated Title')
        expect(json_response['priority']).to eq('urgent')
      end

      it 'does not allow changing account_id' do
        original_account_id = opportunity.account_id

        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
              params: { account_id: other_account.id },
              headers: admin.create_new_auth_token

        opportunity.reload
        expect(opportunity.account_id).to eq(original_account_id)
      end

      it 'does not allow changing contact_id' do
        original_contact_id = opportunity.contact_id
        new_contact = create(:contact, account: account)

        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
              params: { contact_id: new_contact.id },
              headers: admin.create_new_auth_token

        opportunity.reload
        expect(opportunity.contact_id).to eq(original_contact_id)
      end

      it 'returns validation errors' do
        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
              params: { title: '' },
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to be_present
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
              params: { title: 'Test' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/opportunities/:id' do
    let(:opportunity) { create(:opportunity, account: account, contact: contact) }

    context 'when authenticated' do
      it 'soft deletes the opportunity' do
        delete "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
               headers: admin.create_new_auth_token

        expect(response).to have_http_status(:no_content)
        opportunity.reload
        expect(opportunity.deleted_at).to be_present
      end

      it 'does not appear in index after deletion' do
        delete "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}",
               headers: admin.create_new_auth_token

        get "/api/v1/accounts/#{account.id}/opportunities",
            headers: admin.create_new_auth_token

        json_response = response.parsed_body
        opportunity_ids = json_response.map { |o| o['id'] }
        expect(opportunity_ids).not_to include(opportunity.id)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/opportunities/kanban' do
    context 'when authenticated' do
      before do
        create(:opportunity, account: account, contact: contact, stage: :new_lead, status: :open)
        create(:opportunity, account: account, contact: contact, stage: :qualification, status: :open)
        create(:opportunity, account: account, contact: contact, stage: :new_lead, status: :won) # Não deve aparecer
      end

      it 'returns kanban structure' do
        get "/api/v1/accounts/#{account.id}/opportunities/kanban",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['stages']).to be_an(Array)
        expect(json_response['totals']).to be_present
      end

      it 'only includes open opportunities' do
        get "/api/v1/accounts/#{account.id}/opportunities/kanban",
            headers: admin.create_new_auth_token

        json_response = response.parsed_body
        total_count = json_response['stages'].sum { |s| s['count'] }
        expect(total_count).to eq(2) # Apenas as 2 abertas
      end

      it 'filters by assigned_agent_id' do
        create(:opportunity, account: account, contact: contact, assigned_agent: agent, status: :open)

        get "/api/v1/accounts/#{account.id}/opportunities/kanban",
            params: { assigned_agent_id: agent.id },
            headers: admin.create_new_auth_token

        json_response = response.parsed_body
        total_count = json_response['stages'].sum { |s| s['count'] }
        expect(total_count).to eq(1)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/opportunities/kanban"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/opportunities/pipeline_metrics' do
    context 'when authenticated' do
      before do
        create(:opportunity, account: account, contact: contact, status: :won, estimated_value: 1000, created_at: 10.days.ago, closed_at: 5.days.ago)
        create(:opportunity, account: account, contact: contact, status: :lost, lost_reason: 'Test reason', created_at: 15.days.ago,
                             closed_at: 10.days.ago)
        create(:opportunity, account: account, contact: contact, status: :won, estimated_value: 2000, created_at: 20.days.ago, closed_at: 15.days.ago)
      end

      it 'returns pipeline metrics' do
        get "/api/v1/accounts/#{account.id}/opportunities/pipeline_metrics",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['conversion_rate']).to be_a(Numeric)
        expect(json_response['average_deal_value']).to be_a(Numeric)
        expect(json_response['average_cycle_time_days']).to be_a(Numeric)
        expect(json_response['by_stage']).to be_a(Hash)
        expect(json_response['by_referral_source']).to be_a(Hash)
      end

      it 'calculates conversion rate correctly' do
        get "/api/v1/accounts/#{account.id}/opportunities/pipeline_metrics",
            headers: admin.create_new_auth_token

        json_response = response.parsed_body
        # 2 won out of 3 closed = 66.67%
        expect(json_response['conversion_rate']).to eq(66.67)
      end

      it 'uses default date range (last 30 days)' do
        create(:opportunity, account: account, contact: contact, status: :won, created_at: 35.days.ago, closed_at: 30.days.ago)

        get "/api/v1/accounts/#{account.id}/opportunities/pipeline_metrics",
            headers: admin.create_new_auth_token

        json_response = response.parsed_body
        # Não deve incluir a oportunidade antiga
        expect(json_response['conversion_rate']).to eq(66.67)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/opportunities/pipeline_metrics"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/opportunities/:id/move_stage' do
    let(:opportunity) { create(:opportunity, account: account, contact: contact, stage: :new_lead) }

    context 'when authenticated' do
      it 'moves opportunity to new stage' do
        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/move_stage",
              params: { stage: 'qualification' },
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['stage']).to eq('qualification')
        opportunity.reload
        expect(opportunity.stage).to eq('qualification')
      end

      it 'creates stage transition' do
        expect do
          patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/move_stage",
                params: { stage: 'qualification' },
                headers: admin.create_new_auth_token
        end.to change { opportunity.stage_transitions.count }.by(1)
      end

      it 'returns error for invalid transition' do
        opportunity.update(status: :won)

        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/move_stage",
              params: { stage: 'qualification' },
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('Invalid stage transition')
      end

      it 'returns error when stage parameter is missing' do
        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/move_stage",
              params: {},
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('Stage parameter is required')
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/move_stage",
              params: { stage: 'qualification' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/opportunities/:id/mark_won' do
    let(:opportunity) { create(:opportunity, account: account, contact: contact, status: :open) }

    context 'when authenticated' do
      it 'marks opportunity as won' do
        post "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/mark_won",
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['status']).to eq('won')
        opportunity.reload
        expect(opportunity.status).to eq('won')
        expect(opportunity.closed_at).to be_present
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/mark_won"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/opportunities/:id/mark_lost' do
    let(:opportunity) { create(:opportunity, account: account, contact: contact, status: :open) }

    context 'when authenticated' do
      it 'marks opportunity as lost with reason' do
        post "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/mark_lost",
             params: { reason: 'Paciente desistiu' },
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['status']).to eq('lost')
        opportunity.reload
        expect(opportunity.status).to eq('lost')
        expect(opportunity.lost_reason).to eq('Paciente desistiu')
        expect(opportunity.closed_at).to be_present
      end

      it 'returns error when reason is missing' do
        post "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/mark_lost",
             params: {},
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('Reason is required')
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/opportunities/#{opportunity.id}/mark_lost",
             params: { reason: 'Test' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
