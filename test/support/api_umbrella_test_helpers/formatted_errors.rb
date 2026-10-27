module ApiUmbrellaTestHelpers
  module FormattedErrors
    private

    def assert_json_error(response, error_code = "API_KEY_MISSING")
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal(error_code, data["error"]["code"])
    end

    def assert_xml_error(response, content_type = "application/xml", error_code = "API_KEY_MISSING")
      assert_response_code(403, response)
      assert_equal(content_type, response.headers["content-type"])
      doc = Nokogiri::XML(response.body)
      assert_equal(error_code, doc.xpath("/response/error/code").text)
    end

    def assert_csv_error(response, error_code = "API_KEY_MISSING")
      assert_response_code(403, response)
      assert_equal("text/csv", response.headers["content-type"])
      data = CSV.parse(response.body)
      assert_equal("Error Code", data[0][0])
      assert_equal(error_code, data[1][0])
    end

    def assert_html_error(response, error_code = "API_KEY_MISSING")
      assert_response_code(403, response)
      assert_equal("text/html", response.headers["content-type"])
      doc = Nokogiri::HTML(response.body)
      assert_equal(error_code, doc.xpath("/html/body/h1").text)
    end
  end
end
