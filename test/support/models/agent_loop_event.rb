class AgentLoopEvent < ApplicationRecord
  self.table_name = "agent_loop_events"

  belongs_to :agent_loop_target, :foreign_key => "target_id", :inverse_of => :agent_loop_events
end
