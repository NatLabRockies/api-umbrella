require_relative "../../test_helper"

class Test::Proxy::Caching::TestGzip < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Caching

  parallelize_me!

  def setup
    super
    setup_server
  end

  def test_caches_gzip_version
    assert_cacheable("/api/cacheable-compressible/", {
      :accept_encoding => "gzip",
    })
  end

  def test_caches_ungzip_version
    assert_cacheable("/api/cacheable-compressible/", {
      :accept_encoding => nil,
    })
  end

  # Ideally we would return a cached response regardless of whether the first
  # request was gzipped or not. But for now, we don't support this in all
  # situations, and the gzip and non-gzipped versions must be requested and
  # cached separately (with some exceptions, depending on where the gzipping
  # takes place). So while the behavior of the following first/second tests
  # could change, this documents the current behavior.
  #
  # Varnish supports this more optimized behavior, but it does so by forcing
  # gzip to always be on, then only caching the gzipped version, and then
  # un-gzipping it on the fly for each non-gzip client. For our API traffic, it
  # seems that gzip being enabled is actually the minority of requests (only
  # 40% based on some current production stats), so forcing each request to be
  # un-gzipped on the fly seems like unnecessary overhead given our current
  # usage.
  #
  # In our explorations of TrafficServer, this is unsupported:
  # http://permalink.gmane.org/gmane.comp.apache.trafficserver.user/4191
  #
  # It's possible we might want to revisit this if we decide saving the backend
  # bandwidth is more efficient than unzipping each request on the fly for each
  # non-gzip client.

  def test_backend_does_not_gzip_vary_accept_encoding_separates_cache_when_first_gzip_then_not
    # The cache could technically be shared in this case, and was in Traffic
    # Server prior to 10.2, but no longer is.
    refute_cacheable("/api/cacheable-vary-accept-encoding/", {
      :accept_encoding => "gzip",
    }, {
      :accept_encoding => nil,
    })
  end

  def test_backend_does_not_gzip_vary_accept_encoding_separates_cache_when_first_not_then_gzip
    refute_cacheable("/api/cacheable-vary-accept-encoding/", {
      :accept_encoding => nil,
    }, {
      :accept_encoding => "gzip",
    })
  end

  def test_backend_gzips_itself_separates_cache_when_first_gzip_then_not
    refute_cacheable("/api/cacheable-pre-gzip/", {
      :accept_encoding => "gzip",
    }, {
      :accept_encoding => nil,
    })
  end

  def test_backend_gzips_itself_separates_cache_when_first_not_then_gzip
    refute_cacheable("/api/cacheable-pre-gzip/", {
      :accept_encoding => nil,
    }, {
      :accept_encoding => "gzip",
    })
  end

  def test_backend_force_gzips_itself_separates_cache_when_first_gzip_then_not
    refute_cacheable("/api/cacheable-pre-gzip/?force=true", {
      :accept_encoding => "gzip",
    }, {
      :accept_encoding => nil,
    })
  end

  def test_backend_force_gzips_itself_separates_cache_when_first_not_then_gzip
    # The cache could technically be shared in this case, and was in Traffic
    # Server prior to 10.2, but no longer is.
    # first response.
    refute_cacheable("/api/cacheable-pre-gzip/?force=true", {
      :accept_encoding => nil,
    }, {
      :accept_encoding => "gzip",
    })
  end

  def test_backend_does_not_gzip_no_vary_shares_cache_when_first_gzip_then_not
    # The cache can be shared in this case, since the gzipping isn't handled at
    # the backend layer, so there's no vary rules.
    assert_cacheable("/api/cacheable-compressible/", {
      :accept_encoding => "gzip",
    }, {
      :accept_encoding => nil,
    })
  end

  def test_backend_does_not_gzip_no_vary_shares_cache_when_first_not_then_gzip
    # The cache can be shared in this case, since the gzipping isn't handled at
    # the backend layer, so there's no vary rules.
    assert_cacheable("/api/cacheable-compressible/", {
      :accept_encoding => nil,
    }, {
      :accept_encoding => "gzip",
    })
  end

  def test_backend_gzips_itself
    # Validate that underlying API is pre-gzipped.
    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-pre-gzip/", http_options.deep_merge(:accept_encoding => "gzip"))
    assert_response_code(200, response)
    assert_equal("gzip", response.headers["content-encoding"])
    data = MultiJson.load(response.body)
    assert_kind_of(Hash, data["headers"])
    assert_equal("gzip", data["headers"]["accept-encoding"])

    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-pre-gzip/", http_options)
    assert_response_code(200, response)
    assert_nil(response.headers["content-encoding"])
    data = MultiJson.load(response.body)
    assert_kind_of(Hash, data["headers"])
    assert_nil(data["headers"]["accept-encoding"])

    assert_gzip("/api/cacheable-pre-gzip/")
  end

  def test_backend_force_gzips_itself
    # Validate that underlying API is pre-gzipped.
    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-pre-gzip/?force=true", http_options.deep_merge(:accept_encoding => "gzip"))
    assert_response_code(200, response)
    assert_equal("gzip", response.headers["content-encoding"])
    data = MultiJson.load(response.body)
    assert_kind_of(Hash, data["headers"])
    assert_equal("gzip", data["headers"]["accept-encoding"])

    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-pre-gzip/?force=true", http_options)
    assert_response_code(200, response)
    assert_equal("gzip", response.headers["content-encoding"])
    data = MultiJson.load(Zlib::GzipReader.new(StringIO.new(response.body)).read)
    assert_kind_of(Hash, data["headers"])
    assert_nil(data["headers"]["accept-encoding"])

    assert_gzip("/api/cacheable-pre-gzip/?force=true")
  end

  def test_backend_does_not_gzip_no_vary
    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-compressible/", http_options.deep_merge(:accept_encoding => "gzip"))
    assert_response_code(200, response)
    assert_nil(response.headers["Vary"])
    assert_nil(response.headers["Content-Encoding"])

    assert_gzip("/api/cacheable-compressible/")
  end

  def test_backend_does_not_gzip_vary_accept_encoding
    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-vary-accept-encoding/", http_options.deep_merge(:accept_encoding => "gzip"))
    assert_response_code(200, response)
    assert_equal("Accept-Encoding", response.headers["Vary"])
    assert_nil(response.headers["Content-Encoding"])

    assert_gzip("/api/cacheable-vary-accept-encoding/")
  end

  def test_backend_gzips_itself_multiple_vary
    # Validate that underlying API is pre-gzipped.
    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-pre-gzip-multiple-vary/", http_options)
    assert_response_code(200, response)
    assert_equal("gzip", response.headers["content-encoding"])
    data = MultiJson.load(Zlib::GzipReader.new(StringIO.new(response.body)).read)
    assert_kind_of(Hash, data["headers"])
    assert_nil(data["headers"]["accept-encoding"])

    assert_gzip("/api/cacheable-pre-gzip-multiple-vary/")
  end

  def test_backend_force_gzips_itself_multiple_vary
    # Validate that underlying API is pre-gzipped.
    response = Typhoeus.get("http://127.0.0.1:9444/cacheable-pre-gzip-multiple-vary/?force=true", http_options)
    assert_response_code(200, response)
    assert_equal("gzip", response.headers["content-encoding"])
    data = MultiJson.load(Zlib::GzipReader.new(StringIO.new(response.body)).read)
    assert_kind_of(Hash, data["headers"])
    assert_nil(data["headers"]["accept-encoding"])

    assert_gzip("/api/cacheable-pre-gzip-multiple-vary/?force=true")
  end

  def test_backend_does_not_gzip_multiple_vary
    assert_gzip("/api/cacheable-vary-accept-encoding-multiple/")
  end

  private

  def assert_gzip(path)
    assert_first_request_gzipped_second_request_gzipped(path)
    assert_first_request_gzipped_second_request_not_gzipped(path)
    assert_first_request_not_gzipped_second_request_gzipped(path)
    assert_first_request_not_gzipped_second_request_not_gzipped(path)
  end

  def assert_first_request_gzipped_second_request_gzipped(path)
    first, second = make_duplicate_requests(path, {
      :params => {
        :unique_test_id => "#{unique_test_id}-#{next_unique_number}",
      },
      :accept_encoding => "gzip",
    })
    assert_equal("gzip", first.headers["content-encoding"])
    assert_equal("gzip", second.headers["content-encoding"])
  end

  def assert_first_request_gzipped_second_request_not_gzipped(path)
    first, second = make_duplicate_requests(path, {
      :params => {
        :unique_test_id => "#{unique_test_id}-#{next_unique_number}",
      },
      :accept_encoding => "gzip",
    }, {
      :accept_encoding => nil,
    })
    assert_equal("gzip", first.headers["content-encoding"])
    refute(second.headers["content-encoding"])
  end

  def assert_first_request_not_gzipped_second_request_gzipped(path)
    first, second = make_duplicate_requests(path, {
      :params => {
        :unique_test_id => "#{unique_test_id}-#{next_unique_number}",
      },
      :accept_encoding => nil,
    }, {
      :accept_encoding => "gzip",
    })
    refute(first.headers["content-encoding"])
    assert_equal("gzip", second.headers["content-encoding"])
  end

  def assert_first_request_not_gzipped_second_request_not_gzipped(path)
    first, second = make_duplicate_requests(path, {
      :params => {
        :unique_test_id => "#{unique_test_id}-#{next_unique_number}",
      },
      :accept_encoding => nil,
    })
    refute(first.headers["content-encoding"])
    refute(second.headers["content-encoding"])
  end
end
