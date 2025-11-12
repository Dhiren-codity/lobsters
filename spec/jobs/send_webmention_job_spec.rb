RSpec.describe SendWebmentionJob, type: :job do
  include ActiveJob::TestHelper

  let(:job) { described_class.new }

  before do
    allow(Rails.application).to receive(:domain).and_return('test.local')
    stub_const('NoIPsError', Class.new(StandardError)) unless defined?(NoIPsError)
    stub_const('DNSError', Class.new(StandardError)) unless defined?(DNSError)
  end

  describe 'queueing' do
    it 'enqueues on the default queue' do
      ActiveJob::Base.queue_adapter = :test
      expect do
        described_class.perform_later('story_id')
      end.to have_enqueued_job(described_class).with('story_id').on_queue('default')
    end

    it 'has queue_as default' do
      expect(described_class.queue_name).to eq('default')
    end
  end

  describe '#endpoint_from_body' do
    it 'finds href from rel~="webmention"' do
      html = '<html><head><link rel="webmention" href="https://wm.example/endpoint"></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://wm.example/endpoint')
    end

    it 'finds href from legacy rel="http://webmention.org/"' do
      html = '<html><head><link rel="http://webmention.org/" href="https://wm.example/legacy"></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://wm.example/legacy')
    end

    it 'finds href from legacy rel="http://webmention.org" (no slash)' do
      html = '<html><head><link rel="http://webmention.org" href="https://wm.example/legacy2"></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://wm.example/legacy2')
    end

    it 'returns nil when absent' do
      html = '<html><head></head><body>No link</body></html>'
      expect(job.endpoint_from_body(html)).to be_nil
    end
  end

  describe '#endpoint_from_headers' do
    it 'matches <url>; rel="... webmention ..."' do
      header = '<https://wm.example/endpoint>; rel="author webmention"'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'matches <url>; rel=webmention' do
      header = '<https://wm.example/endpoint>; rel=webmention'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'matches rel="... webmention ..."; <url>' do
      header = 'rel="author webmention"; <https://wm.example/endpoint>'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'matches rel=webmention; <url>' do
      header = 'rel=webmention; <https://wm.example/endpoint>'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'matches legacy <url>; rel="http://webmention.org/"' do
      header = '<https://wm.example/endpoint>; rel="http://webmention.org/"'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'matches legacy rel="http://webmention.org/"; <url>' do
      header = 'rel="http://webmention.org/"; <https://wm.example/endpoint>'
      expect(job.endpoint_from_headers(header)).to eq('https://wm.example/endpoint')
    end

    it 'returns nil when no header given' do
      expect(job.endpoint_from_headers(nil)).to be_nil
    end

    it 'returns nil when header does not contain webmention' do
      header = '<https://example.com>; rel="author"'
      expect(job.endpoint_from_headers(header)).to be_nil
    end
  end

  describe '#uri_to_absolute' do
    let(:req_uri) { URI.parse('https://example.com/post/123') }

    it 'returns original string when already absolute' do
      expect(job.uri_to_absolute('https://wm.example/endpoint', req_uri)).to eq('https://wm.example/endpoint')
    end

    it 'converts relative path to absolute URI object' do
      result = job.uri_to_absolute('/webmention', req_uri)
      expect(result).to be_a(URI)
      expect(result.scheme).to eq('https')
      expect(result.host).to eq('example.com')
      expect(result.path).to eq('/webmention')
    end

    it 'preserves port and scheme of the request uri' do
      req = URI.parse('http://example.com:8080/blog/post')
      result = job.uri_to_absolute('wm', req)
      expect(result).to be_a(URI)
      expect(result.scheme).to eq('http')
      expect(result.host).to eq('example.com')
      expect(result.port).to eq(8080)
      expect(result.path).to eq('wm')
    end
  end

  describe '#send_webmention' do
    it 'posts encoded source and target using Sponge' do
      sp = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sp)
      expect(sp).to receive(:timeout=).with(10)
      expect(sp).to receive(:ssl_verify=).with(false)
      expect(sp).to receive(:fetch) do |endpoint, method, params, a, b, c|
        expect(endpoint).to eq('https://wm.example/endpoint')
        expect(method).to eq(:post)
        expect(params['source']).to eq(URI.encode_www_form_component('https://source.example/s/abc'))
        expect(params['target']).to eq(URI.encode_www_form_component('https://target.example/post'))
        expect(a).to be_nil
        expect(b).to eq({})
        expect(c).to eq(3)
        :ok
      end.and_return(:ok)

      result = job.send_webmention('https://source.example/s/abc', 'https://target.example/post', 'https://wm.example/endpoint')
      expect(result).to eq(:ok)
    end
  end

  describe '#perform' do
    let(:story) { instance_double('Story') }
    let(:source_url) { 'https://myapp.example/s/abc' }
    let(:target_url) { 'https://remote.example/post' }

    before do
      stub_const('Routes', Module.new) unless defined?(Routes)
      allow(Routes).to receive(:story_short_id_url).with(story).and_return(source_url)
      allow(story).to receive(:url).and_return(target_url)
      allow(story).to receive(:is_gone?).and_return(false)
    end

    def sponge_response(link: nil, body: '')
      resp = double('SpongeResponse')
      allow(resp).to receive(:[]).with('link').and_return(link)
      allow(resp).to receive(:body).and_return(body)
      resp
    end

    it 'returns early if story is gone' do
      allow(story).to receive(:is_gone?).and_return(true)
      expect(Sponge).not_to receive(:new)
      described_class.perform_now(story)
    end

    it 'returns early if story url blank' do
      allow(story).to receive(:url).and_return('')
      expect(Sponge).not_to receive(:new)
      described_class.perform_now(story)
    end

    it 'returns early in development environment' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      expect(Sponge).not_to receive(:new)
      described_class.perform_now(story)
    end

    it 'skips when DNS errors occur on fetch' do
      sp = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sp)
      expect(sp).to receive(:timeout=).with(10)
      expect(sp).to receive(:fetch).and_raise(NoIPsError)
      expect_any_instance_of(described_class).not_to receive(:send_webmention)
      described_class.perform_now(story)
    end

    it 'skips when fetch returns nil' do
      sp = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sp)
      expect(sp).to receive(:timeout=).with(10)
      expect(sp).to receive(:fetch).and_return(nil)
      expect_any_instance_of(described_class).not_to receive(:send_webmention)
      described_class.perform_now(story)
    end

    it 'uses Link header endpoint and calls send_webmention' do
      sp = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sp)
      expect(sp).to receive(:timeout=).with(10)
      allow(sp).to receive(:fetch).and_return(sponge_response(link: '<https://wm.example/endpoint>; rel="webmention"',
                                                              body: ''))

      expect_any_instance_of(described_class).to receive(:send_webmention).with(source_url, target_url, 'https://wm.example/endpoint')
      described_class.perform_now(story)
    end

    it 'uses HTML body endpoint when Link header missing' do
      sp = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sp)
      expect(sp).to receive(:timeout=).with(10)
      body = '<html><head><link rel="webmention" href="/wm"></head></html>'
      allow(sp).to receive(:fetch).and_return(sponge_response(link: nil, body: body))

      expect_any_instance_of(described_class).to receive(:send_webmention) do |_, _, endpoint|
        expect(endpoint).to be_a(URI)
        expect(endpoint.scheme).to eq('https')
        expect(endpoint.host).to eq('remote.example')
        expect(endpoint.path).to eq('/wm')
      end
      described_class.perform_now(story)
    end

    it 'does nothing when no endpoint is found' do
      sp = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sp)
      expect(sp).to receive(:timeout=).with(10)
      allow(sp).to receive(:fetch).and_return(sponge_response(link: nil, body: '<html></html>'))
      expect_any_instance_of(described_class).not_to receive(:send_webmention)
      described_class.perform_now(story)
    end
  end
end
