# frozen_string_literal: true

json.array! @opportunities do |opportunity|
  json.partial! 'api/v1/accounts/opportunities/show', opportunity: opportunity
end

