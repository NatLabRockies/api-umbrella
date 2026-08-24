require_relative "../../test_helper"

# Test connection collapsing behavior from the Traffic Server caching layer
# when a thundering herd of parallel requests are received for the same
# resource. This tests various different scenarios of thundering herds
# (cacheable requests, non-cacheable requests, stale cache, etc) for
# longer-running requests that will run in parallel.
#
# Note that in some cases, it may be okay for the exact behavior to change in
# the future (eg, better stale detection, or stale-while revalidate might be
# nice). So these tests aren't necessarily meant to be set in stone and might
# change in future Traffic Server upgrades (although care should be taken if
# the behavior does change). This attempts to at least document/test the
# current behavior for better reference.
class Test::Proxy::Caching::TestThunderingHerds < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Caching

  # When testing for collapsed connections, allow some leeway in our test
  # suite. So, for example, if we're making 50 concurrent requests, it's okay
  # for there maybe to be 5 requests that got through, instead of just 1. For
  # the most part, Traffic Server collapses things correctly, but there are
  # some timing edge-cases that lead to a few more connections leaking through
  # in the test suite. However, we're mainly interested in verifying that most
  # connections get collapsed, so some fuzziness/buffering is okay.
  COLLAPSED_CONNECTION_BUFFER = 5

  def setup
    super
    setup_server
  end

  def test_connection_collapsing_for_cacheable
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => true,
    })
  end

  def test_connection_collapsing_for_cacheable_precache_fresh
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => true,
      :precache => true,
    })
  end

  def test_connection_collapsing_for_cacheable_precache_stale
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => true,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_connection_collapsing_for_cacheable_streaming
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => true,
    })
  end

  def test_connection_collapsing_for_cacheable_streaming_precache_fresh
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => true,
      :precache => true,
    })
  end

  def test_connection_collapsing_for_cacheable_streaming_precache_stale
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => true,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_connection_collapsing_for_public_cacheable
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => true,
    })
  end

  def test_connection_collapsing_for_public_cacheable_precache_fresh
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => true,
      :precache => true,
    })
  end

  def test_connection_collapsing_for_public_cacheable_precache_stale
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => true,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_connection_collapsing_for_public_cacheable_streaming
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => true,
    })
  end

  def test_connection_collapsing_for_public_cacheable_streaming_precache_fresh
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => true,
      :precache => true,
    })
  end

  def test_connection_collapsing_for_public_cacheable_streaming_precache_stale
    assert_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => true,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_private_cacheable
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "private, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_private_cacheable_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "private, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_private_cacheable_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "private, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_private_cacheable_streaming
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "private, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_private_cacheable_streaming_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "private, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_private_cacheable_streaming_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "private, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_cache_disabled
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=0, private, must-revalidate",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_cache_disabled_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=0, private, must-revalidate",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_cache_disabled_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=0, private, must-revalidate",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_cache_disabled_streaming
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=0, private, must-revalidate",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_cache_disabled_streaming_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=0, private, must-revalidate",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_cache_disabled_streaming_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "max-age=0, private, must-revalidate",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_no_explicit_cache
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => nil,
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_no_explicit_cache_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => nil,
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_no_explicit_cache_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => nil,
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_no_explicit_cache_streaming
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => nil,
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_no_explicit_cache_streaming_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => nil,
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_no_explicit_cache_streaming_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => nil,
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_non_cacheable
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :method => "POST",
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_non_cacheable_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :method => "POST",
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_non_cacheable_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :method => "POST",
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_for_non_cacheable_streaming
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :method => "POST",
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
    })
  end

  def test_no_connection_collapsing_for_non_cacheable_streaming_precache_fresh
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :method => "POST",
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
    })
  end

  def test_no_connection_collapsing_for_non_cacheable_streaming_precache_stale
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :method => "POST",
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=2",
        "X-Delay" => "1",
        "X-Delay-Before" => "body",
      },
    }, {
      :cacheable => false,
      :precache => true,
      :precache_stale_delay => 3,
    })
  end

  def test_no_connection_collapsing_when_retry_timeout_exceeded
    refute_connections_collapsed("/api/cacheable-thundering-herd/", {
      :headers => {
        "X-Cache-Control-Response" => "public, max-age=60",
        "X-Delay" => "3",
        "X-Delay-Before" => "headers",
      },
    }, {
      :cacheable => true,
      :min_response_time_range => 2.9..3.7,
      :max_response_time_range => 4.9..5.7,
    })
  end

  private

  def make_thundering_herd_requests(path, custom_http_options = {}, options = {})
    http_opts = http_options.deep_merge(custom_http_options).deep_merge({
      :params => {
        :unique_test_id => unique_test_id,
      },
    })

    url = "http://127.0.0.1:9080#{path}/#{unique_test_id}"

    # Make an initial request if the cache is being pre-seeded.
    if(options[:precache])
      request = Typhoeus::Request.new(url, http_opts)
      request.run
    end

    # Wait until the cache expires if we're checking for the behavior of
    # cached, but stale items.
    if(options[:precache_stale_delay])
      sleep(options[:precache_stale_delay])
    end

    # Make the thundering herd of 50 concurrent requests.
    hydra = Typhoeus::Hydra.new
    requests = Array.new(50) do
      request = Typhoeus::Request.new(url, http_opts)
      hydra.queue(request)
      request
    end
    hydra.run

    # Verify all responses were successful.
    assert_equal(50, requests.length)
    requests.each do |req|
      assert_response_code(200, req.response)
    end
  end

  def backend_call_count
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=#{unique_test_id}")
    assert_response_code(200, response)
    response.body.to_i
  end

  def unique_response_bodies_count(requests)
    requests.map { |r| r.response.body }.uniq.length
  end

  def cache_status(requests)
    cache_status = {
      "HIT" => 0,
      "MISS" => 0,
    }
    requests.each do |request|
      cache = request.response.headers["X-Cache"]
      cache_status[cache] ||= 0
      cache_status[cache] += 1
    end
    cache_status
  end

  def request_timings(requests)
    requests.map { |r| r.response.total_time }.sort
  end

  def assert_connections_collapsed(path, custom_http_options = {}, options = {})
    requests = make_thundering_herd_requests(path, custom_http_options, options)

    requests_count = requests.length
    assert_equal(50, requests_count)

    # Somewhat rarely, more connections seem to be let through when a precache
    # is stale. Since all of this is somewhat fuzzy, we're okay with this, so
    # increase the threshold for these cases. We mainly just want to ensure it
    # still represents not all of the connections being let through.
    collapsed_connection_buffer = COLLAPSED_CONNECTION_BUFFER
    if(options[:precache] && options[:precache_stale_delay])
      collapsed_connection_buffer = COLLAPSED_CONNECTION_BUFFER * 4
    end
    assert_operator(collapsed_connection_buffer, :<, requests_count / 2.0)

    # Since a thundering herd is prevented, ensure connection collapsing and
    # caching took place so that the API backend was only called once (plus 1
    # additional time when pre-caching is enabled for the initial request).
    call_count = backend_call_count
    if(options[:precache] && options[:precache_stale_delay])
      assert_operator(call_count, :>=, 2)
      assert_operator(call_count, :<=, 2 + collapsed_connection_buffer)
    else
      assert_operator(call_count, :>=, 1)
      assert_operator(call_count, :<=, 1 + collapsed_connection_buffer)
    end

    # Ensure all the responses back were identical, since the connections were
    # collapsed to a single API backend request and cached.
    unique_count = unique_response_bodies_count(requests)
    assert_operator(unique_count, :>=, 1)
    assert_operator(unique_count, :<=, 1 + collapsed_connection_buffer)

    statuses = cache_status(requests)
    assert_equal(["HIT", "MISS"].sort, statuses.keys)

    # If there was a fresh cache item in place before making our thundering
    # herd of requests, then all responses should be cache hits. Otherwise, the
    # first request will be a cache miss, but the rest should be hits.
    if(options[:precache] && !options[:precache_stale_delay])
      assert_operator(statuses["HIT"], :>=, requests_count - collapsed_connection_buffer)
      assert_operator(statuses["HIT"], :<=, requests_count)
      assert_operator(statuses["MISS"], :>=, 0)
      assert_operator(statuses["MISS"], :<=, 0 + collapsed_connection_buffer)
    else
      assert_operator(statuses["HIT"], :>=, requests_count - 1 - collapsed_connection_buffer)
      assert_operator(statuses["HIT"], :<=, requests_count - 1)
      assert_operator(statuses["MISS"], :>=, 1)
      assert_operator(statuses["MISS"], :<=, 1 + collapsed_connection_buffer)
    end
    assert_equal(50, statuses["HIT"] + statuses["MISS"])

    # Check the response times to ensure the connection collapsing behavior
    # doesn't serialize the requests and take too long for potentially
    # uncacheable responses (as TrafficServer's open read retry can do)
    timings = request_timings(requests)

    if(options[:min_response_time_range] && options[:max_response_time_range])
      assert_includes(options[:min_response_time_range], timings.min)
      assert_includes(options[:max_response_time_range], timings.max)

    # For cacheable responses that have a fresh pre-cached hit, then all
    # responses should be cached and not subject to the API backend's delay.
    elsif(options.fetch(:cacheable) && options[:precache] && !options[:precache_stale_delay])
      assert_includes(0.0..0.7, timings.min)
      assert_includes(0.0..0.7, timings.max)

    # For cacheable responses, the response times should all be in the
    # neighborhood of the API backend's delayed response time (since after the
    # first request comes back, it should cached and used for all the pending
    # requests, so the pending requests respond basically instantly).
    elsif(options.fetch(:cacheable))
      assert_includes(0.9..1.7, timings.min)
      assert_includes(0.9..1.7, timings.max)

    # For non-cacheable responses, the response times for the parallel requests
    # might be double the initial response time at worst. This is because the
    # first response has to be received before the server knows it's
    # non-cacheable and then the rest of the pending, parallel requests should
    # all be sent at once (we just want to ensure it's no worse than 2x in the
    # worst case).
    else
      assert_includes(0.9..1.7, timings.min)
      assert_includes(1.9..2.7, timings.max)
    end
  end

  def refute_connections_collapsed(path, custom_http_options = {}, options = {})
    requests = make_thundering_herd_requests(path, custom_http_options, options)

    requests_count = requests.length
    assert_equal(50, requests_count)

    # Since a thundering herd is allowed, ensure the API backend was called for
    # each request made (since no caching or connection collapsing should have
    # happened). There's 1 additional request when pre-caching is enabled (for
    # the first pre-cached request).
    call_count = backend_call_count
    if(options[:precache])
      assert_equal(requests_count + 1, call_count)
    else
      assert_equal(requests_count, call_count)
    end

    # Ensure each response back was unique, since no responses should be cached
    # or shared.
    unique_count = unique_response_bodies_count(requests)
    assert_equal(requests_count, unique_count)

    # All responses back should have been a cache miss.
    statuses = cache_status(requests)
    assert_equal(["HIT", "MISS"].sort, statuses.keys)
    assert_equal(0, statuses["HIT"])
    assert_equal(requests_count, statuses["MISS"])
    assert_equal(requests_count, statuses["HIT"] + statuses["MISS"])

    # Check the response times to ensure the connection collapsing behavior
    # doesn't serialize the requests and take too long for potentially
    # uncacheable responses (as TrafficServer's open read retry can do)
    timings = request_timings(requests)

    if(options[:min_response_time_range] && options[:max_response_time_range])
      assert_includes(options[:min_response_time_range], timings.min)
      assert_includes(options[:max_response_time_range], timings.max)

    # For cacheable responses that have a fresh pre-cached hit, then all
    # responses should be cached and not subject to the API backend's delay.
    elsif(options.fetch(:cacheable) && options[:precache] && !options[:precache_stale_delay])
      assert_includes(0.0..0.7, timings.min)
      assert_includes(0.0..0.7, timings.max)

    # For non-cacheable responses that are streamed back (when the headers are
    # received back immediately, and then it's only the body that's delayed),
    # then all the requests should be parallelized immediately, so there should
    # be no significant delays.
    elsif(!options.fetch(:cacheable) && custom_http_options[:headers]["X-Delay-Before"] == "body")
      assert_includes(0.9..1.7, timings.min)
      assert_includes(0.9..1.7, timings.max)

    # For non-cacheable *requests* when TrafficServer knows immediately the
    # response won't be cacheable without actually receiving the response (eg,
    # POST requests), then all the requests should be parallelized immediately.
    elsif(!options.fetch(:cacheable) && custom_http_options[:method] == "POST")
      assert_includes(0.9..1.7, timings.min)
      assert_includes(0.9..1.7, timings.max)

    # For all other situations, the response times for the parallel requests
    # might be double the initial response time at worst. This is because the
    # first response has to be received before the server knows it's
    # non-cacheable and then the rest of the pending, parallel requests should
    # all be sent at once (we just want to ensure it's no worse than 2x in the
    # worst case).
    else
      assert_includes(0.9..1.7, timings.min)
      assert_includes(1.9..2.7, timings.max)
    end
  end
end
