# frozen_string_literal: true

# Migration para permitir null em from_stage para primeira transição
# A primeira transição de uma oportunidade não tem estágio anterior
class AllowNullFromStageInStageTransitions < ActiveRecord::Migration[7.0]
  def change
    change_column_null :stage_transitions, :from_stage, true
  end
end
