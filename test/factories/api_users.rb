FactoryBot.define do
  factory :api_user do
    api_key { SecureRandom.alphanumeric(40) }
    first_name { "Ambrose" }
    last_name { "Burnside" }
    sequence(:email) { |n| "ambrose.burnside#{n}@example.com" }
    terms_and_conditions { "1" }

    factory :xss_api_user do
      email { 'a@"&gt;&lt;script&nbsp;class="xss-test"&gt;alert("Hello-first_name");&lt;/script&gt;.com' }
      first_name { '"><script class="xss-test">alert("Hello first_name");</script>' }
      last_name { '"><script class="xss-test">alert("Hello last_name");</script>' }
      use_description { '"><script class="xss-test">alert("Hello use_description");</script>' }
      registration_source { '"><script class="xss-test">alert("Hello registration_source");</script>' }
    end

    factory :custom_rate_limit_api_user do
      settings do
        FactoryBot.build(:custom_rate_limit_api_user_settings)
      end
    end
  end
end
