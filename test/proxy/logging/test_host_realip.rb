require_relative "../../test_helper"

class Test::Proxy::Logging::TestHostRealip < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Logging
  include Minitest::Hooks

  def setup
    super
    setup_server
    once_per_class_setup do
      override_config_set({
        "hosts" => [
          {
            "hostname" => "realip.foo",
            "real_ip_header" => "True-Client-IP",
          },
        ],
      })

      prepend_api_backends([
        {
          :frontend_host => "realip.foo",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/", :backend_prefix => "/" }],
          :settings => {
            :rate_limits => [
              {
                :duration => 60 * 60 * 1000, # 1 hour
                :limit_by => "ip",
                :limit_to => 5,
                :distributed => true,
                :response_headers => true,
              },
            ],
          },
        },
      ])
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_default_ignores_custom_headers
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "True-Client-IP" => "52.52.118.192",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_equal("127.0.0.1", record.fetch("request_ip"))
  end

  def test_default_x_forwarded_still_works
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "True-Client-IP" => "52.52.118.192",
        "X-Forwarded-For" => "8.8.8.8",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_equal("8.8.8.8", record.fetch("request_ip"))
  end

  def test_allows_custom_realip_header_for_hosts
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", log_http_options.deep_merge({
      :headers => {
        "Host" => "realip.foo",
        "True-Client-IP" => "216.160.83.56",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_equal("216.160.83.56", record.fetch("request_ip"))
    assert_equal("US", record.fetch("request_ip_country"))
    assert_equal("WA", record.fetch("request_ip_region"))
    assert_equal("Milton", record.fetch("request_ip_city"))
  end

  def test_rate_limit_uses_realip
    http_opts = keyless_http_options.deep_merge({
      :headers => {
        "X-Api-Key" => FactoryBot.create(:api_user).api_key,
      },
    })

    ip1 = next_unique_ip_addr
    ip2 = next_unique_ip_addr

    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", http_opts.deep_merge({
      :headers => {
        "Host" => "realip.foo",
        "True-Client-IP" => ip1,
      },
    }))
    assert_response_code(200, response)
    assert_equal("4", response.headers["X-RateLimit-Remaining"])

    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", http_opts.deep_merge({
      :headers => {
        "Host" => "realip.foo",
        "True-Client-IP" => ip1,
      },
    }))
    assert_response_code(200, response)
    assert_equal("3", response.headers["X-RateLimit-Remaining"])

    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", http_opts.deep_merge({
      :headers => {
        "Host" => "realip.foo",
        "True-Client-IP" => ip2,
      },
    }))
    assert_response_code(200, response)
    assert_equal("4", response.headers["X-RateLimit-Remaining"])
  end
end
