require_relative "../test_helper"

class Test::Proxy::TestStreaming < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::RequestBodyStreaming

  def setup
    super
    setup_server
  end

  def test_streaming_responses
    request = Typhoeus::Request.new("http://127.0.0.1:9080/api/chunked?#{unique_test_id}", http_options)
    chunks = []
    chunk_timers = []
    request.on_body do |chunk|
      chunks << chunk
      chunk_timers << Time.now.utc
    end
    response = request.run

    assert_response_code(200, response)
    assert_equal("chunked", response.headers["Transfer-Encoding"])
    assert_equal(["hello", "salutations", "goodbye"], chunks)
    assert_operator(chunk_timers[1] - chunk_timers[0], :>, 0.4)
    assert_operator(chunk_timers[2] - chunk_timers[1], :>, 0.4)
  end

  def test_streaming_requests
    easy = make_streaming_body_request([
      {
        :data => "foo",
        :sleep => 0,
      },
      {
        :data => "bar",
        :sleep => 2,
      },
      {
        :data => "baz",
        :sleep => 2,
      },
      {
        :data => "qux",
        :sleep => 2,
      },
    ])

    assert_equal(200, easy.response_code)
    data = MultiJson.load(easy.response_body)
    assert_equal(["foo", "bar", "baz", "qux"], data.fetch("chunks"))
    assert_equal(4, data.fetch("chunk_time_gaps").length)
    assert_in_delta(0, data.fetch("chunk_time_gaps")[0], 0.3)
    assert_in_delta(2, data.fetch("chunk_time_gaps")[1], 0.3)
    assert_in_delta(2, data.fetch("chunk_time_gaps")[2], 0.3)
    assert_in_delta(2, data.fetch("chunk_time_gaps")[3], 0.3)
  end
end
