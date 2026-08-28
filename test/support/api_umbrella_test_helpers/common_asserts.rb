module ApiUmbrellaTestHelpers
  module CommonAsserts
    private

    def response_error_message(response)
      message = nil
      if response
        message = <<~EOS
          response_code: #{response.response_code}
          return_code: #{response.return_code}
          return_message: #{response.return_message}
          total_time: #{response.total_time}
          starttransfer_time: #{response.starttransfer_time}
          appconnect_time: #{response.appconnect_time}
          pretransfer_time: #{response.pretransfer_time}
          connect_time: #{response.connect_time}
          namelookup_time: #{response.namelookup_time}
          redirect_time: #{response.redirect_time}
          effective_url: #{response.effective_url}
          primary_ip: #{response.primary_ip}
          response_headers: #{response.headers.inspect}
          response_body: #{response.body}
        EOS
      end

      message
    end

    def assert_response_code(expected_code, response, message = nil)
      if(expected_code != response.code)
        message ||= <<~EOS
          Response code did not match
          #{response_error_message(response)}
        EOS
      end
      assert_equal(expected_code, response.code, message)
    end

    def assert_match_iso8601(obj, msg = nil)
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z\z/, obj, msg)
    end

    def assert_match_uuid(obj, msg = nil)
      assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, obj, msg)
    end

    def assert_match_api_key(obj, msg = nil)
      assert_match(/\A[a-zA-Z0-9]{40}\z/, user["api_key"])
    end
  end
end
