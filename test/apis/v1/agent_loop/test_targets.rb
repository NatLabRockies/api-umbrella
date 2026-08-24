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
end
