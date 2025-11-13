class SendWebmentionJob < ApplicationJob
  queue_as :default

  def endpoint_from_body(html)
    doc = Nokogiri::HTML(html.to_s)

    node =
      doc.at_css('[rel~="webmention"][href]') ||
      doc.at_css('[rel="http://webmention.org/"][href]') ||
      doc.at_css('[rel="http://webmention.org"][href]')

    node && node['href']
  end

  def endpoint_from_headers(header)
    return unless header

    if (matches = header.match(/<([^>]+)>;\s*rel="[^"]*\bwebmention\b[^"]*"/i))
      matches[1]
    elsif (matches = header.match(/<([^>]+)>;\s*rel=webmention/i))
      matches[1]
    elsif (matches = header.match(/rel="[^"]*\bwebmention\b[^"]*";\s*<([^>]+)>/i))
      matches[1]
    elsif (matches = header.match(/rel=webmention;\s*<([^>]+)>/i))
      matches[1]
    elsif (matches = header.match(/<([^>]+)>;\s*rel="http:\/\/webmention\.org\/?"/i))
      matches[1]
    elsif (matches = header.match(/rel="http:\/\/webmention\.org\/?";\s*<([^>]+)>/i))
      matches[1]
    end
  end

  # Translate a possibly relative endpoint URI into an absolute string based on the target URL.
  def uri_to_absolute(uri, req_uri)
    begin
      parsed = URI.parse(uri.to_s)
    rescue URI::InvalidURIError
      return uri.to_s
    end

    # Already absolute
    return uri.to_s if parsed.scheme && parsed.host

    base = req_uri.is_a?(URI) ? req_uri : URI.parse(req_uri.to_s)
    URI.join(base.to_s, uri.to_s).to_s
  end

  def send_webmention(source, target, endpoint)
    sp = Sponge.new
    sp.timeout = 10
    # Don't check SSL certificate here for backward compatibility, security risk
    # is minimal.
    sp.ssl_verify = false
    sp.fetch(endpoint.to_s, :post, {
      "source" => URI.encode_www_form_component(source),
      "target" => URI.encode_www_form_component(target)
    }, nil, {}, 3)
  end

  def perform(story)
    # Could have been deleted between creation and now
    return if story.is_gone?
    # Need a URL to send the webmention to
    return if story.url.blank?
    # Don't try to send webmentions in dev
    return if Rails.env.development?

    sp = Sponge.new
    sp.timeout = 10
    begin
      response = sp.fetch(URI::RFC2396_PARSER.escape(story.url), :get, nil, nil, {
        "User-agent" => "#{Rails.application.domain} webmention endpoint lookup"
      }, 3)
    rescue NoIPsError, DNSError
      # other people's DNS issues (usually transient); just skip the webmention
      return
    end
    return unless response

    wm_endpoint_raw = endpoint_from_headers(response["link"]) ||
      endpoint_from_body(response.body.to_s)
    return unless wm_endpoint_raw

    wm_endpoint = uri_to_absolute(wm_endpoint_raw, URI.parse(story.url))
    send_webmention(Routes.story_short_id_url(story), story.url, wm_endpoint)
  end
end