require_relative "../../../test_helper"

class Test::Apis::V1::AgentLoop::TestTargets < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_creates_target_and_initial_assignment_event
    api_user = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets.json", http_options.deep_merge(admin_csrf_session(admin)).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :target => {
          :agent_id => api_user.id,
          :name => "Improve first response quality",
          :description => "Collect evidence and re-grade after review.",
          :responsibility_tier => "baseline",
          :metadata => {
            :domain => "support",
          },
        },
      }),
    }))

    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal("assigned", data["target"]["state"])
    assert_equal(api_user.id, data["target"]["agent_id"])
    assert_equal(1, data["events"].length)
    assert_equal("assigned", data["events"][0]["event_type"])
    assert_equal(1, AgentLoopTarget.count)
    assert_equal(1, AgentLoopEvent.count)
  end

  def test_requires_valid_lifecycle_transitions
    api_user = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    target = create_target(api_user, admin)

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets/#{target.id}/events.json", http_options.deep_merge(admin_csrf_session(admin)).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :event => {
          :event_type => "evidence",
          :summary => "Tried to skip the work step.",
        },
      }),
    }))

    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal("event_type", data["errors"][0]["field"])
    assert_equal("is not allowed for the target's current state", data["errors"][0]["message"])
  end

  def test_lists_targets_filtered_by_agent
    agent1 = FactoryBot.create(:api_user)
    agent2 = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    create_target(agent1, admin)
    create_target(agent2, admin)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets.json?agent_id=#{agent1.id}", http_options.deep_merge(admin_token(admin)))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["targets"].length)
    assert_equal(agent1.id, data["targets"][0]["agent_id"])
  end

  def test_lists_all_targets_without_filter
    agent1 = FactoryBot.create(:api_user)
    agent2 = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    create_target(agent1, admin)
    create_target(agent2, admin)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets.json", http_options.deep_merge(admin_token(admin)))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    # assert_equal(2, ...) since exactly 2 targets were created in this test
    assert_equal(2, data["targets"].length)
  end

  def test_shows_target
    api_user = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    target = create_target(api_user, admin)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets/#{target.id}.json", http_options.deep_merge(admin_token(admin)))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(target.id, data["target"]["id"])
    assert_equal(api_user.id, data["target"]["agent_id"])
    assert_equal("assigned", data["target"]["state"])
    assert_equal(0.0, data["target"]["reputation_score"])
    assert_equal(0.0, data["target"]["asset_value"])
    assert_equal(0, data["target"]["iteration_count"])
  end

  def test_lists_events_for_target
    api_user = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    target = create_target(api_user, admin)
    create_event(target, admin, {
      :event_type => "work",
      :summary => "Started working.",
    })

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets/#{target.id}/events.json", http_options.deep_merge(admin_token(admin)))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    # 2 events: the initial "assigned" event auto-created by create_target, plus the explicit "work" event
    assert_equal(2, data["events"].length)
    assert_equal("assigned", data["events"][0]["event_type"])
    assert_equal("work", data["events"][1]["event_type"])
  end

  def test_mentor_note_does_not_change_state
    api_user = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    target = create_target(api_user, admin)

    create_event(target, admin, {
      :event_type => "mentor_note",
      :summary => "Keep up the good work.",
    })

    target.reload
    assert_equal("assigned", target.state)
  end

  def test_deduplication_key_prevents_duplicate_events
    api_user = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    target = create_target(api_user, admin)
    create_event(target, admin, {
      :event_type => "work",
      :summary => "First attempt.",
      :deduplication_key => "unique-work-001",
    })

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets/#{target.id}/events.json", http_options.deep_merge(admin_csrf_session(admin)).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :event => {
          :event_type => "evidence",
          :summary => "Duplicate attempt.",
          :deduplication_key => "unique-work-001",
        },
      }),
    }))

    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal("deduplication_key", data["errors"][0]["field"])
  end

  def test_standings_ordering_with_multiple_agents
    agent1 = FactoryBot.create(:api_user, :first_name => "Low", :last_name => "Score")
    agent2 = FactoryBot.create(:api_user, :first_name => "High", :last_name => "Score")
    admin = FactoryBot.create(:admin)

    # agent1 gets a low score
    target1 = create_target(agent1, admin)
    run_full_grading_cycle(target1, admin, :score => 60, :reputation_delta => 5, :asset_value_delta => 1)

    # agent2 gets a high score
    target2 = create_target(agent2, admin)
    run_full_grading_cycle(target2, admin, :score => 90, :reputation_delta => 20, :asset_value_delta => 8)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/standings.json", http_options.deep_merge(admin_token(admin)))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(2, data["standings"].length)
    # higher reputation score comes first
    assert_equal(agent2.id, data["standings"][0]["agent_id"])
    assert_equal(20.0, data["standings"][0]["reputation_score"])
    assert_equal(agent1.id, data["standings"][1]["agent_id"])
    assert_equal(5.0, data["standings"][1]["reputation_score"])
  end

  def test_numeric_fields_are_numbers_in_json
    api_user = FactoryBot.create(:api_user)
    admin = FactoryBot.create(:admin)
    target = create_target(api_user, admin)
    create_event(target, admin, { :event_type => "work", :summary => "Work done." })
    create_event(target, admin, { :event_type => "evidence", :summary => "Evidence." })
    create_event(target, admin, {
      :event_type => "grade",
      :summary => "Graded.",
      :score => 80,
      :grade_label => "B",
      :reputation_delta => 10,
      :asset_value_delta => 2,
    })

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets/#{target.id}.json", http_options.deep_merge(admin_token(admin)))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_kind_of(Numeric, data["target"]["current_grade"])
    assert_kind_of(Numeric, data["target"]["reputation_score"])
    assert_kind_of(Numeric, data["target"]["asset_value"])
    assert_kind_of(Numeric, data["target"]["iteration_count"])
    assert_equal(80.0, data["target"]["current_grade"])
    assert_equal(10.0, data["target"]["reputation_score"])
    assert_equal(2.0, data["target"]["asset_value"])

    event_response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets/#{target.id}/events.json", http_options.deep_merge(admin_token(admin)))
    events_data = MultiJson.load(event_response.body)
    grade_event = events_data["events"].find { |e| e["event_type"] == "grade" }
    assert_kind_of(Numeric, grade_event["score"])
    assert_kind_of(Numeric, grade_event["reputation_delta"])
    assert_kind_of(Numeric, grade_event["asset_value_delta"])
    assert_equal(80.0, grade_event["score"])
    assert_equal(10.0, grade_event["reputation_delta"])
    assert_equal(2.0, grade_event["asset_value_delta"])
  end

  def test_grading_updates_target_and_standings
    api_user = FactoryBot.create(:api_user, :first_name => "Ada", :last_name => "Lovelace")
    admin = FactoryBot.create(:admin)
    target = create_target(api_user, admin)

    create_event(target, admin, {
      :event_type => "work",
      :summary => "Implemented the requested change.",
      :metadata => {
        :attempt => 1,
      },
    })
    create_event(target, admin, {
      :event_type => "evidence",
      :summary => "Attached benchmark and review notes.",
      :evidence => {
        :benchmarks => 2,
      },
    })
    create_event(target, admin, {
      :event_type => "grade",
      :summary => "Quality approved.",
      :score => 91,
      :grade_label => "A",
      :reputation_delta => 12,
      :asset_value_delta => 4,
    })
    create_event(target, admin, {
      :event_type => "responsibility_change",
      :summary => "Promoted to mentor-reviewed queue.",
      :responsibility_tier => "advanced",
    })
    create_event(target, admin, {
      :event_type => "re_evaluate",
      :summary => "Re-graded after follow-up iteration.",
      :score => 95,
      :grade_label => "A+",
      :reputation_delta => 5,
      :asset_value_delta => 3,
    })

    target.reload
    assert_equal("re_evaluated", target.state)
    assert_equal("advanced", target.responsibility_tier)
    assert_equal(BigDecimal("95.0"), target.current_grade)
    assert_equal(BigDecimal("17.0"), target.reputation_score)
    assert_equal(BigDecimal("7.0"), target.asset_value)
    assert_equal(1, target.iteration_count)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/standings.json", http_options.deep_merge(admin_token(admin)))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["standings"].length)
    assert_equal(api_user.id, data["standings"][0]["agent_id"])
    assert_equal("Ada", data["standings"][0]["first_name"])
    assert_equal(95.0, data["standings"][0]["average_grade"])
    assert_equal(17.0, data["standings"][0]["reputation_score"])
    assert_equal(7.0, data["standings"][0]["asset_value"])
  end

  private

  def create_target(api_user, admin)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets.json", http_options.deep_merge(admin_csrf_session(admin)).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :target => {
          :agent_id => api_user.id,
          :name => "Close the loop",
        },
      }),
    }))

    assert_response_code(201, response)
    AgentLoopTarget.order(:created_at).last
  end

  def create_event(target, admin, event)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/agent-loop/targets/#{target.id}/events.json", http_options.deep_merge(admin_csrf_session(admin)).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :event => event,
      }),
    }))

    assert_response_code(201, response)
    response
  end

  def run_full_grading_cycle(target, admin, opts = {})
    create_event(target, admin, { :event_type => "work", :summary => "Work done." })
    create_event(target, admin, { :event_type => "evidence", :summary => "Evidence attached." })
    create_event(target, admin, {
      :event_type => "grade",
      :summary => "Grade recorded.",
      :score => opts.fetch(:score, 75),
      :grade_label => "B",
      :reputation_delta => opts.fetch(:reputation_delta, 10),
      :asset_value_delta => opts.fetch(:asset_value_delta, 2),
    })
  end
end
