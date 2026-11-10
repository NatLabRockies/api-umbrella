class ApiUser < ApplicationRecord
  has_one :settings, :class_name => "ApiUserSettings"
  has_and_belongs_to_many :roles, -> { order(:id) }, :class_name => "ApiRole", :join_table => "api_users_roles"
  attr_accessor :terms_and_conditions
  attr_accessor :deactivation_token

  def id=(id)
    prev_id = self[:id]
    self[:id] = id

    # Re-encrypt if the ID (used for the auth data) changes.
    if prev_id && prev_id != id && @unencrypted_api_key
      self.api_key = @unencrypted_api_key
    end
  end

  def self.delete_non_seeded
    self.where("registration_source IS NULL OR registration_source != 'seed'").delete_all
  end

  def roles
    self.role_ids
  end

  def roles=(ids)
    ApiRole.insert_missing(ids)
    self.role_ids = ids
  end

  def api_key=(value)
    @unencrypted_api_key = value

    # Ensure the record ID is set (it may not be on initial create), since we
    # need the ID for the auth data.
    self.id ||= SecureRandom.uuid

    self.api_key_hash = OpenSSL::HMAC.hexdigest("sha256", $config["secret_key"], value)
    self.api_key_encrypted_iv = SecureRandom.hex(6)
    self.api_key_encrypted = Base64.strict_encode64(Encryptor.encrypt({
      :value => value,
      :iv => self.api_key_encrypted_iv,
      :key => Digest::SHA256.digest($config.fetch("secret_key")),
      :auth_data => self.id,
    }))
    self.api_key_prefix = value[0, 16]
    self.api_key_suffix = value[-6..]
  end

  def api_key
    Encryptor.decrypt({
      :value => Base64.strict_decode64(self.api_key_encrypted),
      :iv => self.api_key_encrypted_iv,
      :key => Digest::SHA256.digest($config.fetch("secret_key")),
      :auth_data => self.id,
    })
  end

  def api_key_preview
    "#{self.api_key_prefix[0, 4]}...#{self.api_key_suffix[-4..]}"
  end

  def serializable_hash(options = nil)
    options ||= {}
    options.merge!({
      :methods => [
        :api_key,
        :roles,
      ],
      :include => {
        :settings => {
          :include => {
            :rate_limits => {},
          },
        },
      },
    })
    super
  end

  def deactivation_token=(value)
    self.deactivation_token_hash = OpenSSL::HMAC.hexdigest("sha256", $config["secret_key"], value)
    @deactivation_token = value
  end
end
