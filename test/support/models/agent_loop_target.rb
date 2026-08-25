class AgentLoopTarget < ApplicationRecord
  self.table_name = "agent_loop_targets"

  has_many :agent_loop_events, :foreign_key => "target_id", :inverse_of => :agent_loop_target
end
