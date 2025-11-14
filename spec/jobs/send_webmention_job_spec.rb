require 'rails_helper'

RSpec.describe SendWebmentionJob, type: :job do
  include ActiveJob::TestHelper

  let(:job) do
    described_class.new
  end

  before do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
    allow(Rails).to receive_message_chain(:application, :domain).and_return('example.com')

    routes = Module.new
    def routes.story_short_id_url(story)
      "https://news.example/s/#{story.short_id}"
    end
    stub_const('Routes', routes)

    stub_const('NoIPsError', Class.new(StandardError)) unless defined?(NoIPsError)
    stub_const('DNSError', Class.new(StandardError)) unless defined?(DNSError)

    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe '#perform' do
    let(:story) do
      double('Story', is_gone?: false, url: 'https://target.example/page', short_id: 'abc123')
    end

    let(:sp) do
      double('Sponge')
    end

    let(:response) do
      double('Response', body: double(to_s: ''), :[] => nil)
    end

    before do
      allow(Sponge).to receive(:new).and_return(sp)
      allow(sp).to receive(:timeout=)
      allow(sp).to receive(:fetch)
    end

    it 'returns early if the story is gone' do
      gone_story = double('Story', is_gone?: true, url: 'https://target.example/page', short_id: 'abc123')
      expect(Sponge).not_to receive(:new)
      job.perform(gone_story)
    end

    it 'returns early if the story has no url' do
      no_url_story = double('Story', is_gone?: false, url: '', short_id: 'abc123')
      expect(Sponge).not_to receive(:new)
      job.perform(no_url_story)
    end

    it 'does not run in development environment' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      expect(Sponge).not_to receive(:new)
      job.perform(story)
    end

    it 'discovers endpoint in Link header and sends webmention' do
      allow(response).to receive(:[]).with('link').and_return('<https://wm.example/ep>; rel="webmention"')
      allow(sp).to receive(:fetch).and_return(response)
      expect(job).to receive(:send_webmention).with('https://news.example/s/abc123', 'https://target.example/page', 'https://wm.example/ep')
      job.perform(story)
    end

    it 'falls back to HTML discovery and resolves relative endpoint' do
      html = '<html><head><link rel="webmention" href="/webmention"></head><body></body></html>'
      allow(response).to receive(:[]).with('link').and_return(nil)
      allow(response).to receive(:body).and_return(double(to_s: html))
      allow(sp).to receive(:fetch).and_return(response)
      expected_endpoint = URI.parse('https://target.example/webmention')
      expect(job).to receive(:send_webmention).with('https://news.example/s/abc123', 'https://target.example/page',
                                                    expected_endpoint)
      job.perform(story)
    end

    it 'returns if no endpoint is discovered' do
      allow(response).to receive(:[]).with('link').and_return(nil)
      allow(response).to receive(:body).and_return(double(to_s: '<html></html>'))
      allow(sp).to receive(:fetch).and_return(response)
      expect(job).not_to receive(:send_webmention)
      job.perform(story)
    end

    it 'returns when fetch returns nil' do
      allow(sp).to receive(:fetch).and_return(nil)
      expect(job).not_to receive(:send_webmention)
      job.perform(story)
    end

    it 'swallows NoIPsError during fetch and does not send' do
      expect(job).not_to receive(:send_webmention)
      allow(sp).to receive(:fetch).and_raise(NoIPsError.new('dns'))
      job.perform(story)
    end

    it 'swallows DNSError during fetch and does not send' do
      expect(job).not_to receive(:send_webmention)
      allow(sp).to receive(:fetch).and_raise(DNSError.new('dns'))
      job.perform(story)
    end

    it 'raises errors from send_webmention for retry by backend' do
      allow(response).to receive(:[]).with('link').and_return('<https://wm.example/ep>; rel="webmention"')
      allow(sp).to receive(:fetch).and_return(response)
      allow(job).to receive(:send_webmention).and_raise(StandardError.new('boom'))
      expect do
        job.perform(story)
      end.to raise_error(StandardError, 'boom')
    end

    it 'is idempotent when no endpoint is available (no side effects on repeated runs)' do
      allow(response).to receive(:[]).with('link').and_return(nil)
      allow(response).to receive(:body).and_return(double(to_s: '<html></html>'))
      allow(sp).to receive(:fetch).and_return(response)
      expect(job).not_to receive(:send_webmention)
      job.perform(story)
      job.perform(story)
    end
  end

  describe 'enqueuing' do
    it 'enqueues the job on the default queue' do
      expect do
        described_class.perform_later('arg')
      end.to have_enqueued_job(described_class).with('arg').on_queue('default')
    end

    it 'enqueues the job with a delay' do
      expect do
        described_class.set(wait: 1.hour).perform_later('arg')
      end.to have_enqueued_job(described_class).at(a_value_within(5.seconds).of(1.hour.from_now))
    end
  end

  describe '#endpoint_from_headers' do
    it 'extracts endpoint from rel="webmention" format' do
      header = '<https://wm.example/endpoint>; rel="webmention"'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'extracts endpoint from unquoted rel=webmention format' do
      header = '<https://wm.example/endpoint>; rel=webmention'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'extracts endpoint when rel appears before URL' do
      header = 'rel=webmention; <https://wm.example/endpoint>'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'accepts http://webmention.org rel value' do
      header = '<https://wm.example/endpoint>; rel="http://webmention.org/"'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'returns nil when no match' do
      header = '<https://wm.example/endpoint>; rel="next"'
      expect(job.endpoint_from_headers(header)).to be_nil
    end

    it 'returns nil when header is nil' do
      expect(job.endpoint_from_headers(nil)).to be_nil
    end
  end

  describe '#endpoint_from_body' do
    it 'finds rel~="webmention" link' do
      html = '<html><head><link rel="webmention pingback" href="https://wm.example/ep"></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://wm.example/ep')
    end

    it 'finds rel="http://webmention.org/" link' do
      html = '<html><head><a rel="http://webmention.org/" href="https://wm.example/ep"></a></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://wm.example/ep')
    end

    it 'finds rel="http://webmention.org" link' do
      html = '<html><head><a rel="http://webmention.org" href="https://wm.example/ep"></a></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://wm.example/ep')
    end

    it 'returns nil when no webmention link is present' do
      html = '<html><head><link rel="author" href="/me"></head></html>'
      expect(job.endpoint_from_body(html)).to be_nil
    end
  end

  describe '#uri_to_absolute' do
    it 'returns the same URI string when already absolute' do
      req_uri = URI.parse('https://example.com/path')
      expect(job.uri_to_absolute('https://wm.example/ep', req_uri)).to eq('https://wm.example/ep')
    end

    it 'converts relative URI to absolute URI object' do
      req_uri = URI.parse('https://example.com/path')
      result = job.uri_to_absolute('/webmention', req_uri)
      expect(result).to be_a(URI)
      expect(result.to_s).to eq('https://example.com/webmention')
    end

    it 'preserves port and scheme from request URI' do
      req_uri = URI.parse('http://example.com:8080/path')
      result = job.uri_to_absolute('/webmention', req_uri)
      expect(result.scheme).to eq('http')
      expect(result.host).to eq('example.com')
      expect(result.port).to eq(8080)
    end
  end

  describe '#send_webmention' do
    let(:sp) do
      double('Sponge')
    end

    before do
      allow(Sponge).to receive(:new).and_return(sp)
      allow(sp).to receive(:timeout=)
      allow(sp).to receive(:ssl_verify=)
    end

    it 'posts encoded source and target to endpoint' do
      endpoint = 'https://wm.example/ep'
      source = 'https://src.example/post?q=a b'
      target = 'https://target.example/page?x=y&z=1'
      encoded_source = URI.encode_www_form_component(source)
      encoded_target = URI.encode_www_form_component(target)
      expect(sp).to receive(:fetch).with(endpoint.to_s, :post,
                                         hash_including('source' => encoded_source, 'target' => encoded_target), nil, {}, 3)
      job.send_webmention(source, target, endpoint)
    end
  end
end
