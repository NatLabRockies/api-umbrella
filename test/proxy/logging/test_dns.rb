require_relative "../../test_helper"

class Test::Proxy::Logging::TestDns < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Dns
  include ApiUmbrellaTestHelpers::Logging
  include Minitest::Hooks

  def setup
    super
    setup_server
    once_per_class_setup do
      override_config_set({
        "dns_resolver" => {
          "nameservers" => ["[127.0.0.1]:#{$config["unbound"]["port"]}"],
          "negative_ttl" => false,
        },
      })
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_logs_extra_fields_for_chunked_or_gzip
    set_dns_records(["#{unique_test_hostname} 1 A 127.0.0.2"])

    prepend_api_backends([
      {
        :frontend_host => "127.0.0.1",
        :backend_host => unique_test_hostname,
        :servers => [{ :host => unique_test_hostname, :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/info/" }],
      },
    ]) do
      response = wait_for_response("/#{unique_test_id}/", {
        :code => 200,
        :local_interface_ip => "127.0.0.2",
      })

      record = wait_for_log(response)[:hit_source]
      assert_logs_base_fields(record, api_user)
      assert_equal("127.0.0.2:9444", record["api_backend_resolved_host"])
      assert_equal("via_upstream", record["api_backend_response_code_details"])
    end
  end
end
