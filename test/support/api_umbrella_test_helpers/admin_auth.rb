require "securerandom"
require "support/api_umbrella_test_helpers/selenium"

module ApiUmbrellaTestHelpers
  module AdminAuth
    # Since lua-resty-session checks the user agent when decrypting the session
    # (to ensure the session hasn't been lifted and being used elsewhere), set
    # a hard-coded user agent when we're pre-seeding the session cookie value.
    STATIC_USER_AGENT = "TestStaticUserAgent".freeze

    # lua-resty-session v4 binary header layout constants.
    # Header is 82 bytes: [1B type][2B flags][32B sid][5B creation_time]
    #   [4B rolling_offset][3B data_size][16B tag][3B idling_offset][16B mac]
    V4_HEADER_SIZE = 82
    V4_HEADER_SID_OFFSET = 3
    V4_HEADER_SID_SIZE = 32
    V4_HEADER_PRE_TAG_SIZE = 47 # bytes before AES-GCM tag
    V4_HEADER_TAG_SIZE = 16

    include ApiUmbrellaTestHelpers::Selenium

    def admin_login(admin = nil)
      selenium_add_cookie("_api_umbrella_session", encrypt_session_cookie(admin_session_data(admin)))

      visit "/admin/login"
      assert_logged_in(admin)
    end

    def csrf_session
      csrf_token_key = SecureRandom.hex(20)
      session_client_cookie = encrypt_session_client_cookie(csrf_session_data(csrf_token_key))
      {
        :headers => {
          "Cookie" => "_api_umbrella_session_client=#{session_client_cookie}",
          "User-Agent" => STATIC_USER_AGENT,
          "X-CSRF-Token" => csrf_token(csrf_token_key),
        },
      }
    end

    def admin_session(admin = nil)
      session_cookie = encrypt_session_cookie(admin_session_data(admin))
      {
        :headers => {
          "Cookie" => "_api_umbrella_session=#{session_cookie}",
          "User-Agent" => STATIC_USER_AGENT,
        },
      }
    end

    def admin_csrf_session(admin = nil)
      csrf_token_key = SecureRandom.hex(20)
      session_cookie = encrypt_session_cookie(admin_session_data(admin))
      session_client_cookie = encrypt_session_client_cookie(csrf_session_data(csrf_token_key))
      {
        :headers => {
          "Cookie" => "_api_umbrella_session=#{session_cookie}; _api_umbrella_session_client=#{session_client_cookie}",
          "User-Agent" => STATIC_USER_AGENT,
          "X-CSRF-Token" => csrf_token(csrf_token_key),
        },
      }
    end

    def parse_admin_session_cookie(raw_cookies)
      cookie_value = Array(raw_cookies).join("; ").match(/_api_umbrella_session=([^;\s]+)/)[1]
      cookie_value = CGI.unescape(cookie_value)
      decrypt_session_cookie(cookie_value)
    end

    def parse_admin_session_client_cookie(raw_cookies)
      cookie_value = Array(raw_cookies).join("; ").match(/_api_umbrella_session_client=([^;\s]+)/)[1]
      cookie_value = CGI.unescape(cookie_value)
      decrypt_session_client_cookie(cookie_value)
    end

    def admin_token(admin = nil)
      admin ||= FactoryBot.create(:admin)
      { :headers => { "X-Admin-Auth-Token" => admin.authentication_token } }
    end

    def assert_logged_in(admin = nil)
      # Wait for the page to fully load, including the /admin/auth ajax request
      # which will fill out the "My Account" link. If we don't wait, then
      # navigating to another page immediately may cancel the previous
      # /admin/auth ajax request if it hadn't finished throwing some errors.
      if(admin)
        assert_link("my_account_nav_link", :href => /#{admin.id}/, :visible => :all)
      else
        assert_link("my_account_nav_link", :visible => :all)
      end
    end

    def assert_first_time_admin_creation_allowed
      assert_equal(0, Admin.count)

      get_response, create_response = make_first_time_admin_creation_requests
      assert_response_code(200, get_response)
      assert_response_code(302, create_response)

      assert_equal("https://127.0.0.1:9081/admin/#/login", create_response.headers["Location"])

      assert_equal(1, Admin.count)
    end

    def assert_first_time_admin_creation_forbidden
      initial_count = Admin.count

      get_response, create_response = make_first_time_admin_creation_requests
      assert_response_code(302, get_response)
      assert_response_code(302, create_response)

      assert_equal("https://127.0.0.1:9081/admin/", get_response.headers["Location"])
      assert_equal("https://127.0.0.1:9081/admin/", create_response.headers["Location"])

      assert_equal(initial_count, Admin.count)
    end

    def assert_first_time_admin_creation_not_found
      initial_count = Admin.count

      get_response, create_response = make_first_time_admin_creation_requests
      assert_response_code(404, get_response)
      assert_response_code(404, create_response)

      assert_equal(initial_count, Admin.count)
    end

    def assert_no_password_fields_on_admin_forms
      admin1 = FactoryBot.create(:admin)
      admin2 = FactoryBot.create(:admin)
      admin_login(admin1)

      # Admin cannot edit their own password
      visit "/admin/#/admins/#{admin1.id}/edit"
      assert_text("Edit Admin")
      assert_field("Email", :with => admin1.username)
      refute_text("Password")

      # Admins cannot edit other admin passwords
      visit "/admin/#/admins/#{admin2.id}/edit"
      assert_text("Edit Admin")
      assert_field("Email", :with => admin2.username)
      refute_text("Password")

      # Admins cannot set new admin passwords
      visit "/admin/#/admins/new"
      assert_text("Add Admin")
      refute_text("Password")
    end

    def assert_password_fields_on_my_account_admin_form_only
      admin1 = FactoryBot.create(:admin)
      admin2 = FactoryBot.create(:admin)
      admin_login(admin1)

      # Admin can edit their own password
      visit "/admin/#/admins/#{admin1.id}/edit"
      assert_text("Edit Admin")
      assert_field("Email", :with => admin1.username)
      assert_text("Change Your Password")
      assert_field("Current Password")
      assert_field("New Password")
      assert_field("Confirm New Password")
      assert_text("14 characters minimum")

      # Admins cannot edit other admin passwords
      visit "/admin/#/admins/#{admin2.id}/edit"
      assert_text("Edit Admin")
      assert_field("Email", :with => admin2.username)
      refute_text("Password")

      # Admins cannot set new admin passwords
      visit "/admin/#/admins/new"
      assert_text("Add Admin")
      refute_text("Password")
    end

    def make_first_time_admin_creation_requests
      get_response = Typhoeus.get("https://127.0.0.1:9081/admins/signup", keyless_http_options)

      create_response = Typhoeus.post("https://127.0.0.1:9081/admins", keyless_http_options.deep_merge(csrf_session).deep_merge({
        :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
        :body => {
          :admin => {
            :username => "new@example.com",
            :password => "password123456",
            :password_confirmation => "password123456",
          },
        },
      }))

      [get_response, create_response]
    end

    def assert_current_admin_url(fragment_path, fragment_query_values)
      uri = Addressable::URI.parse(page.current_url)
      assert_equal("/admin/", uri.path)
      assert(uri.fragment)

      fragment_uri = Addressable::URI.parse(uri.fragment)
      assert_equal(fragment_path, fragment_uri.path)
      if(fragment_query_values.nil?)
        assert_nil(fragment_uri.query_values)
      else
        assert_equal(fragment_query_values, fragment_uri.query_values)
      end
    end

    private

    def csrf_session_data(csrf_token_key)
      { "csrf_token_key" => csrf_token_key }
    end

    def csrf_token(csrf_token_key)
      iv = SecureRandom.hex(6)
      data_encrypted = Encryptor.encrypt({
        :value => csrf_token_key,
        :iv => iv,
        :key => Digest::SHA256.digest($config["secret_key"]),
        :auth_data => [
          STATIC_USER_AGENT,
          "http",
        ].join(""),
      })

      "#{Base64.strict_encode64(data_encrypted)}|#{iv}"
    end

    def admin_session_data(admin)
      admin ||= FactoryBot.create(:admin)
      { "admin_id" => admin.id }
    end

    def session_base64_encode(value)
      Base64.urlsafe_encode64(value, :padding => false)
    end

    def session_base64_decode(value)
      Base64.urlsafe_decode64(value)
    end

    # Build a lua-resty-session v4 cookie header and encrypt data using v4's
    # binary cookie format. Returns [header_binary, ciphertext_binary].
    #
    # The 82-byte header structure:
    #   [1B type][2B flags][32B sid][5B creation_time][4B rolling_offset]
    #   [3B data_size][16B tag][3B idling_offset][16B mac]
    #
    # The encryption uses HKDF-derived AES-256-GCM keys.
    def build_v4_session(data, flags: 0)
      ikm = Digest::SHA256.digest($config.fetch("secret_key"))
      cookie_type = 1
      sid = SecureRandom.bytes(32)
      creation_time = Time.now.to_i
      rolling_offset = 0
      idling_offset = 0

      # Derive AES-256-GCM key and IV from the SID using HKDF
      sid_key = OpenSSL::KDF.hkdf(ikm, salt: "", info: "encryption:#{sid}", length: 44, hash: "SHA256")
      aes_key = sid_key[0, 32]
      iv = sid_key[32, 12]

      # Compute data_size as the base64url-encoded length of the ciphertext.
      # We need to encrypt first to know the exact size, but since AES-GCM
      # output length equals input length for the ciphertext portion, we can
      # predict it: base64url length of data.length bytes.
      # Actually, we need to encrypt to get the tag, so we build the header
      # in two passes: first without tag/mac, encrypt, then fill in tag/mac.

      # Build partial header (up to and including data_size, before tag)
      # This is the AAD for AES-GCM encryption.
      data_size = session_base64_encode(data).length
      partial_header = [
        [cookie_type].pack("C"),           # 1 byte
        [flags].pack("v"),                 # 2 bytes little-endian uint16
        sid,                               # 32 bytes
        [creation_time].pack("Q<")[0, 5],  # 5 bytes LE
        [rolling_offset].pack("V"),        # 4 bytes LE
        [data_size].pack("V")[0, 3],       # 3 bytes LE
      ].join("")

      # Encrypt session data with AES-256-GCM
      cipher = OpenSSL::Cipher.new("aes-256-gcm")
      cipher.encrypt
      cipher.key = aes_key
      cipher.iv = iv
      cipher.auth_data = partial_header
      ciphertext = cipher.update(data)
      ciphertext << cipher.final
      tag = cipher.auth_tag

      # Complete header: partial_header + tag + idling_offset
      header_for_mac = partial_header + tag + [idling_offset].pack("V")[0, 3]

      # Compute HMAC-SHA256 MAC over the header (truncated to 16 bytes)
      mac_key = OpenSSL::KDF.hkdf(ikm, salt: "", info: "authentication:#{sid}", length: 32, hash: "SHA256")
      mac = OpenSSL::HMAC.digest("sha256", mac_key, header_for_mac)[0, 16]

      full_header = header_for_mac + mac

      {
        header: full_header,
        ciphertext: ciphertext,
        sid: sid,
        creation_time: creation_time,
      }
    end

    # Serialize session data the way lua-resty-session v4 stores it internally:
    # [[data_dict, audience]] where audience defaults to "default"
    def v4_session_data(data)
      MultiJson.dump([[data, "default"]])
    end

    def encrypt_session_cookie(data)
      data_serialized = v4_session_data(data)
      # FLAG_STORAGE = 0x0001 indicates server-side storage is used
      result = build_v4_session(data_serialized, flags: 0x0001)

      # For DB-backed sessions, cookie contains only the header
      cookie_header = session_base64_encode(result[:header])

      # Store encrypted data in database
      sid_encoded = session_base64_encode(result[:sid])
      ciphertext_encoded = session_base64_encode(result[:ciphertext])
      db_data = MultiJson.dump([ciphertext_encoded])
      ttl = 12 * 60 * 60 # 12 hours, matches absolute_timeout
      exp = Time.at(result[:creation_time] + ttl).utc

      Session.create!({
        :sid => sid_encoded,
        :name => "_api_umbrella_session",
        :data => db_data,
        :exp => exp,
      })

      cookie_header
    end

    def decrypt_session_cookie(cookie_value)
      # In v4, the DB-backed cookie is just the base64url-encoded header.
      # Extract the SID from the header to look up the DB record.
      header = session_base64_decode(cookie_value)
      sid = header[V4_HEADER_SID_OFFSET, V4_HEADER_SID_SIZE]
      sid_encoded = session_base64_encode(sid)

      session = Session.find_by(:sid => sid_encoded)

      # DB data is a JSON array: ["<base64url_ciphertext>"]
      db_data = MultiJson.load(session.data)
      ciphertext = session_base64_decode(db_data[0])

      # Derive the decryption key from the SID
      ikm = Digest::SHA256.digest($config["secret_key"])
      sid_key = OpenSSL::KDF.hkdf(ikm, salt: "", info: "encryption:#{sid}", length: 44, hash: "SHA256")
      aes_key = sid_key[0, 32]
      iv = sid_key[32, 12]

      # The AAD is the bytes before the AES-GCM tag
      aad = header[0, V4_HEADER_PRE_TAG_SIZE]
      tag = header[V4_HEADER_PRE_TAG_SIZE, V4_HEADER_TAG_SIZE]

      decipher = OpenSSL::Cipher.new("aes-256-gcm")
      decipher.decrypt
      decipher.key = aes_key
      decipher.iv = iv
      decipher.auth_data = aad
      decipher.auth_tag = tag
      plaintext = decipher.update(ciphertext)
      plaintext << decipher.final

      # v4 data format: [[data_dict, audience]]
      parsed = MultiJson.load(plaintext)
      parsed[0][0]
    end

    def encrypt_session_client_cookie(data)
      data_serialized = v4_session_data(data)
      # No FLAG_STORAGE for cookie-only sessions
      result = build_v4_session(data_serialized, flags: 0)

      # For cookie-only sessions, cookie contains header + ciphertext
      session_base64_encode(result[:header]) + session_base64_encode(result[:ciphertext])
    end

    def decrypt_session_client_cookie(cookie_value)
      # The cookie value is base64url(header) + base64url(ciphertext).
      # The header is always V4_HEADER_SIZE bytes raw.
      header_b64_len = session_base64_encode("\x00" * V4_HEADER_SIZE).length
      header_b64 = cookie_value[0, header_b64_len]
      ciphertext_b64 = cookie_value[header_b64_len..]

      header = session_base64_decode(header_b64)
      ciphertext = session_base64_decode(ciphertext_b64)
      sid = header[V4_HEADER_SID_OFFSET, V4_HEADER_SID_SIZE]

      # Derive the decryption key from the SID
      ikm = Digest::SHA256.digest($config["secret_key"])
      sid_key = OpenSSL::KDF.hkdf(ikm, salt: "", info: "encryption:#{sid}", length: 44, hash: "SHA256")
      aes_key = sid_key[0, 32]
      iv = sid_key[32, 12]

      # The AAD is the bytes before the AES-GCM tag
      aad = header[0, V4_HEADER_PRE_TAG_SIZE]
      tag = header[V4_HEADER_PRE_TAG_SIZE, V4_HEADER_TAG_SIZE]

      decipher = OpenSSL::Cipher.new("aes-256-gcm")
      decipher.decrypt
      decipher.key = aes_key
      decipher.iv = iv
      decipher.auth_data = aad
      decipher.auth_tag = tag
      plaintext = decipher.update(ciphertext)
      plaintext << decipher.final

      # v4 data format: [[data_dict, audience]]
      parsed = MultiJson.load(plaintext)
      parsed[0][0]
    end
  end
end
