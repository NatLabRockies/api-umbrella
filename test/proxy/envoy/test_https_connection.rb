require_relative "../../test_helper"

class Test::Proxy::Envoy::TestHttpsConnection < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::AdminAuth

  def setup
    super
    setup_server
  end

  def test_defaults_to_http_communication
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
    assert_response_code(200, response)

    # Validate that the underlying Envoy server is running over HTTP
    response = Typhoeus.get("http://127.0.0.1:#{$config.fetch("envoy").fetch("port")}/", http_options)
    assert_response_code(404, response)
  end

  def test_https_communication
    domain = unique_test_hostname
    certificate, private_key = create_self_signed_cert(2048, "/O=API Umbrella/CN=#{domain}", "")

    override_config({
      "envoy" => {
        "scheme" => "https",
        "tls_certificate" => {
          "certificate_chain" => certificate.to_pem,
          "private_key" => private_key.to_pem,
          "domain" => domain,
        },
      },
    }) do
      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
      assert_response_code(200, response)

      # Validate that the underlying Envoy server is running over HTTPS and not HTTP
      response = Typhoeus.get("http://127.0.0.1:#{$config.fetch("envoy").fetch("port")}/", http_options)
      assert_response_code(0, response)
      response = Typhoeus.get("https://127.0.0.1:#{$config.fetch("envoy").fetch("port")}/", http_options)
      assert_response_code(404, response)
    end
  end

  def test_https_with_mismatched_cert
    domain = unique_test_hostname
    certificate, private_key = create_self_signed_cert(2048, "/O=API Umbrella/CN=#{domain}", "")

    assert_raises Timeout::Error do
      override_config_set({
        "envoy" => {
          "scheme" => "https",
          "tls_certificate" => {
            "certificate_chain" => certificate.to_pem,
            "private_key" => private_key.to_pem,
            "domain" => "example.com",
          },
        },
      }, {
        :timeout => 10,
        :restart_timeout => 10,
      })
    end

    log_tail = LogTail.new("trafficserver/current")

    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
    assert_response_code(502, response)
    assert_match("Could not connect to the requested server host", response.body)

    log_output = log_tail.read_until("WARNING: SNI")
    assert_match("WARNING: SNI (example.com) not in certificate. Action=Terminate", log_output)
  ensure
    override_config_reset
  end

  private

  # Based on
  # https://github.com/ruby/webrick/blob/v1.8.1/lib/webrick/ssl.rb#L97-L140
  def create_self_signed_cert(bits, name_str, comment)
    rsa = OpenSSL::PKey::RSA.new(bits)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    name = OpenSSL::X509::Name.parse(name_str)
    cert.subject = name
    cert.issuer = name
    cert.not_before = Time.now
    cert.not_after = Time.now + (365 * 24 * 60 * 60)
    cert.public_key = rsa.public_key

    ef = OpenSSL::X509::ExtensionFactory.new(nil, cert)
    ef.issuer_certificate = cert
    cert.extensions = [
      ef.create_extension("basicConstraints", "CA:FALSE"),
      ef.create_extension("keyUsage", "keyEncipherment, digitalSignature, keyAgreement, dataEncipherment"),
      ef.create_extension("subjectKeyIdentifier", "hash"),
      ef.create_extension("extendedKeyUsage", "serverAuth"),
      ef.create_extension("nsComment", comment),
    ]
    aki = ef.create_extension("authorityKeyIdentifier",
      "keyid:always,issuer:always")
    cert.add_extension(aki)
    cert.sign(rsa, "SHA256")

    [cert, rsa]
  end
end
