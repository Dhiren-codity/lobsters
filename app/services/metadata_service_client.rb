class MetadataServiceClient
  class Error < StandardError; end
  class TimeoutError < Error; end
  class ConnectionError < Error; end

  DEFAULT_TIMEOUT = 3
  DEFAULT_SERVICE_URL = ENV.fetch("METADATA_SERVICE_URL", "http://localhost:8080")

  def initialize(service_url: DEFAULT_SERVICE_URL, timeout: DEFAULT_TIMEOUT)
    @service_url = service_url
    @timeout = timeout
  end

  def fetch_metadata(url)
    return nil if url.blank?

    response = make_request(url)
    return nil unless response

    parse_response(response)
  rescue Timeout::Error, Errno::ETIMEDOUT
    raise TimeoutError, "Metadata service timeout after #{@timeout}s"
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
    raise ConnectionError, "Cannot connect to metadata service at #{@service_url}"
  rescue StandardError => e
    Rails.logger.error "MetadataServiceClient error: #{e.message}"
    raise Error, "Failed to fetch metadata: #{e.message}"
  end

  def health_check
    uri = URI("#{@service_url}/health")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @timeout
    http.read_timeout = @timeout

    response = http.get(uri.path)
    response.code == "200" && JSON.parse(response.body)["status"] == "healthy"
  rescue StandardError
    false
  end

  private

  def make_request(url)
    uri = URI("#{@service_url}/fetch")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @timeout
    http.read_timeout = @timeout

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request.body = { url: url }.to_json

    response = http.request(request)

    unless response.code == "200"
      Rails.logger.warn "Metadata service returned #{response.code} for #{url}"
      return nil
    end

    response
  end

  def parse_response(response)
    data = JSON.parse(response.body)
    metadata = data["metadata"]

    return nil unless metadata

    {
      url: metadata["url"],
      title: metadata["title"],
      description: metadata["description"],
      site_name: metadata["site_name"],
      image_url: metadata["image_url"],
      error: metadata["error"]
    }.compact
  end
end

