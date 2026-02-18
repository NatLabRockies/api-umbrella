class LogItem
  include ActiveAttr::Model

  mattr_accessor :client

  attribute :_id
  attribute :api_backend_id
  attribute :api_backend_resolved_host
  attribute :api_backend_response_code_details
  attribute :api_backend_response_flags
  attribute :api_key
  attribute :gatekeeper_denied_code
  attribute :request_accept
  attribute :request_accept_encoding
  attribute :request_at
  attribute :request_connection
  attribute :request_content_type
  attribute :request_hierarchy
  attribute :request_host
  attribute :request_ip
  attribute :request_ip_city
  attribute :request_ip_country
  attribute :request_ip_region
  attribute :request_method
  attribute :request_origin
  attribute :request_path
  attribute :request_query
  attribute :request_referer
  attribute :request_scheme
  attribute :request_size
  attribute :request_url_query
  attribute :request_user_agent
  attribute :request_user_agent_family
  attribute :request_user_agent_type
  attribute :response_age
  attribute :response_cache
  attribute :response_cache_flags
  attribute :response_content_encoding
  attribute :response_content_length
  attribute :response_content_type
  attribute :response_custom1
  attribute :response_custom2
  attribute :response_custom3
  attribute :response_server
  attribute :response_size
  attribute :response_status
  attribute :response_time
  attribute :response_transfer_encoding
  attribute :user_email
  attribute :user_id
  attribute :user_registration_source

  def self.refresh_indices!
    self.client.indices.refresh(:index => "_all")
  end

  def self.clean_indices!
    retries = 0
    begin
      # Refresh all data, so the search results contain all the data for this
      # index.
      self.refresh_indices!

      # Delete all data (but not by dropping indices, since that would remove
      # mappings that only get created once at startup).
      self.client.delete_by_query({
        :index => "_all",
        :refresh => true,
        :body => {
          :query => {
            :match_all => {},
          },
        },
      })
    rescue OpenSearch::Transport::Transport::Errors::Conflict => e
      # Handle possible race condition on deletes, which could lead to "version
      # conflict" errors on rare occasions:
      # https://stackoverflow.com/a/79591362/222487
      retry if (retries += 1) < 5
      raise e
    end
  end

  def serializable_hash
    hash = super

    cleaned_path = hash["request_path"].gsub(%r{//+}, "/")
    cleaned_path.gsub!(%r{/$}, "")
    cleaned_path.gsub!(%r{^/}, "")
    path_parts = cleaned_path.split("/", 6)

    if $config["opensearch"]["template_version"] < 2
      hash["request_url"] = "#{hash.fetch("request_scheme")}://#{hash.fetch("request_host")}#{hash.fetch("request_path")}"
      if hash["request_query"]
        hash["request_url"] << "?#{hash.fetch("request_query")}"
      end
    end

    if !hash["request_hierarchy"] || $config["opensearch"]["template_version"] >= 2
      hash["request_hierarchy"] = []
      host_level = hash["request_host"]
      if !path_parts.empty?
        host_level += "/"
      end
      hash["request_url_hierarchy_level0"] = host_level
      hash["request_hierarchy"] << "0/#{host_level}"

      path_tree = "/"
      path_parts.each_with_index do |path_level, index|
        if index + 1 < path_parts.length
          path_level += "/"
        end

        hash["request_url_hierarchy_level#{index + 1}"] = path_level

        path_tree = "#{path_tree}#{path_level}"
        path_token = "#{index + 1}/#{hash["request_host"]}#{path_tree}"
        hash["request_hierarchy"] << path_token
      end
    end

    if($config["opensearch"]["template_version"] >= 2)
      hash.delete("request_hierarchy")
      hash.delete("request_query")
    end

    hash["request_id"] = self._id
    hash["@timestamp"] = hash.delete("request_at")

    hash
  end

  def save
    prefix = "#{$config.fetch("opensearch").fetch("index_name_prefix")}-logs-v#{$config["opensearch"]["template_version"]}"
    if !self.gatekeeper_denied_code.nil?
      index_name = "#{prefix}-denied"
    elsif self.response_status.to_s =~ /^[4-9]/
      index_name = "#{prefix}-errored"
    else
      index_name = "#{prefix}-allowed"
    end

    self.client.index({
      :index => index_name,
      :id => self._id,
      :body => self.serializable_hash.except("_id"),
    })
  end

  def save!
    self.save || raise("Failed to save log")
  end
end
