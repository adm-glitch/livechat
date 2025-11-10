# frozen_string_literal: true

opportunity = local_assigns[:opportunity] || @opportunity

json.id opportunity.id
json.opportunity_id opportunity.opportunity_id
json.title opportunity.title
json.description opportunity.description
json.service_type opportunity.service_type
json.estimated_value opportunity.estimated_value&.to_f
json.suggested_appointment_date opportunity.suggested_appointment_date
json.referral_source opportunity.referral_source
json.status opportunity.status
json.priority opportunity.priority
json.stage opportunity.stage
json.created_at opportunity.created_at.to_i
json.updated_at opportunity.updated_at.to_i
json.closed_at opportunity.closed_at&.to_i

json.contact do
  json.id opportunity.contact.id
  json.name opportunity.contact.name
  json.email opportunity.contact.email
  json.phone_number opportunity.contact.phone_number
end

if opportunity.assigned_agent.present?
  json.assigned_agent do
    json.id opportunity.assigned_agent.id
    json.name opportunity.assigned_agent.name
    json.display_name opportunity.assigned_agent.display_name
    json.email opportunity.assigned_agent.email
    json.availability opportunity.assigned_agent.availability
  end
else
  json.assigned_agent nil
end

if opportunity.conversation.present?
  json.conversation do
    json.id opportunity.conversation.id
    json.display_id opportunity.conversation.display_id
    json.status opportunity.conversation.status
  end
else
  json.conversation nil
end

json.tasks_count opportunity.tasks.size
json.comments_count opportunity.comments.size

if opportunity.created_by.present?
  json.created_by do
    json.id opportunity.created_by.id
    json.name opportunity.created_by.name
    json.email opportunity.created_by.email
  end
else
  json.created_by nil
end

