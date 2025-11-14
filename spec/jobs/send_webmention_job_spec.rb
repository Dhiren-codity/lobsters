require 'rails_helper'

RSpec.describe SendWebmentionJob, type: :job do
  include ActiveJob::TestHelper

  let(:job) { described_class.new }

  before do
    clear_enqueued_jobs
    allow(Rails).to receive_message_chain(:env, :development?).and_return(false)
    allow(Rails).to receive_message_chain(:application, :domain).and_return('example.test')
    stub_const('Routes', Class.new)
    allow(Routes).to receive(:story_short_id_url).and_return('https://example.test/s/abc')
    stub_const('Sponge', Class.new)
  end

  describe '#perform' do
    let(:story_url) { 'https://target.test/article' }
    let(:story) { instance_double('Story', is_gone?: false, url: story_url) }

    context 'when story is gone' do
      let(:gone_story) { instance_double('Story', is_gone?: true, url: story_url) }

      it 'returns early without network calls' do
        expect(Sponge).not_to receive(:new)
        job.perform(gone_story)
      end
    end

    context 'when story url is blank' do
      let(:blank_url_story) { instance_double('Story', is_gone?: false, url: nil) }

      it 'returns early without network calls' do
        expect(Sponge).not_to receive(:new)
        job.perform(blank_url_story)
      end
    end

    context 'when in development environment' do
      before do
        allow(Rails).to receive_message_chain(:env, :development?).and_return(true)
      end

      it 'returns early without network calls' do
        expect(Sponge).not_to receive(:new)
        job.perform(story)
      end
    end

    context 'when DNS errors occur' do
      before do
        stub_const('NoIPsError', Class.new(StandardError))
        stub_const('DNSError', Class.new(StandardError))
      end

      it 'rescues NoIPsError and does not raise' do
        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        expect(sponge).to receive(:fetch).and_raise(NoIPsError)

        expect do
          job.perform(story)
        end.not_to raise_error
      end

      it 'rescues DNSError and does not raise' do
        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        expect(sponge).to receive(:fetch).and_raise(DNSError)

        expect do
          job.perform(story)
        end.not_to raise_error
      end
    end

    context 'when a non-rescued error occurs' do
      it 'raises the error (to allow retry mechanisms)' do
        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        expect(sponge).to receive(:fetch).and_raise(StandardError)

        expect do
          job.perform(story)
        end.to raise_error(StandardError)
      end
    end

    context 'when no response is returned' do
      it 'does not attempt to send a webmention' do
        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        expect(sponge).to receive(:fetch).and_return(nil)
        expect(job).not_to receive(:send_webmention)

        job.perform(story)
      end
    end

    context 'when no endpoint can be discovered' do
      it 'does not attempt to send a webmention' do
        response = double('Response')
        allow(response).to receive(:[]).with('link').and_return(nil)
        allow(response).to receive(:body).and_return('<html><head></head><body>No endpoint here</body></html>')

        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        expect(sponge).to receive(:fetch).and_return(response)

        expect(job).not_to receive(:send_webmention)
        job.perform(story)
      end
    end

    context 'when endpoint is found in Link headers' do
      it 'calls send_webmention with header endpoint' do
        link_header = '<https://endpoint.example/webmention>; rel="webmention"'
        response = double('Response')
        allow(response).to receive(:[]).with('link').and_return(link_header)
        allow(response).to receive(:body).and_return('<html></html>')

        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        allow(sponge).to receive(:fetch).and_return(response)

        expect(job).to receive(:send_webmention) do |source, target, endpoint|
          expect(source).to eq('https://example.test/s/abc')
          expect(target).to eq(story_url)
          expect(endpoint.to_s).to eq('https://endpoint.example/webmention')
        end

        job.perform(story)
      end
    end

    context 'when endpoint is found in HTML body as relative link' do
      it 'resolves the endpoint to an absolute URI and sends' do
        html = '<html><head><link rel="webmention" href="/wm"></head><body></body></html>'
        response = double('Response')
        allow(response).to receive(:[]).with('link').and_return(nil)
        allow(response).to receive(:body).and_return(html)

        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        allow(sponge).to receive(:fetch).and_return(response)

        expect(job).to receive(:send_webmention) do |source, target, endpoint|
          expect(source).to eq('https://example.test/s/abc')
          expect(target).to eq(story_url)
          expect(endpoint.to_s).to match(%r{\Ahttps://target\.test(?::443)?/wm\z})
        end

        job.perform(story)
      end
    end

    context 'idempotency' do
      it 'can be performed multiple times without crashing and repeats the call' do
        link_header = '<https://endpoint.example/wm>; rel="webmention"'
        response = double('Response')
        allow(response).to receive(:[]).with('link').and_return(link_header)
        allow(response).to receive(:body).and_return('<html></html>')

        sponge = double('Sponge', timeout: nil)
        allow(Sponge).to receive(:new).and_return(sponge)
        allow(sponge).to receive(:timeout=).with(10)
        allow(sponge).to receive(:fetch).and_return(response)

        expect(job).to receive(:send_webmention).twice

        job.perform(story)
        job.perform(story)
      end
    end
  end

  describe '#send_webmention' do
    it 'posts encoded source and target to the endpoint' do
      endpoint = 'https://endpoint.example/wm'
      source = 'https://example.test/s/abc?param=hello world'
      target = 'https://target.test/article?q=a b'
      expected_params = {
        'source' => URI.encode_www_form_component(source),
        'target' => URI.encode_www_form_component(target)
      }

      sponge = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sponge)
      expect(sponge).to receive(:timeout=).with(10)
      expect(sponge).to receive(:ssl_verify=).with(false)
      expect(sponge).to receive(:fetch).with(endpoint, :post, expected_params, nil, {}, 3)

      job.send_webmention(source, target, endpoint)
    end
  end

  describe '#endpoint_from_headers' do
    it 'parses rel="webmention" format' do
      header = '<https://endpoint.example/wm>; rel="webmention"'
      expect(job.endpoint_from_headers(header)).to eq('https://endpoint.example/wm')
    end

    it 'parses rel=webmention format' do
      header = '<https://endpoint.example/wm>; rel=webmention'
      expect(job.endpoint_from_headers(header)).to eq('https://endpoint.example/wm')
    end

    it 'parses reversed order with quoted rel' do
      header = 'rel="foo webmention bar"; <https://endpoint.example/wm>'
      expect(job.endpoint_from_headers(header)).to eq('https://endpoint.example/wm')
    end

    it 'parses reversed order with unquoted rel' do
      header = 'rel=webmention; <https://endpoint.example/wm>'
      expect(job.endpoint_from_headers(header)).to eq('https://endpoint.example/wm')
    end

    it 'parses http://webmention.org/ rel' do
      header = '<https://endpoint.example/wm>; rel="http://webmention.org/"'
      expect(job.endpoint_from_headers(header)).to eq('https://endpoint.example/wm')
    end

    it 'parses reversed http://webmention.org/ rel' do
      header = 'rel="http://webmention.org/"; <https://endpoint.example/wm>'
      expect(job.endpoint_from_headers(header)).to eq('https://endpoint.example/wm')
    end
  end

  describe '#endpoint_from_body' do
    it 'finds rel~="webmention" link' do
      html = '<html><head><link rel="something webmention" href="https://endpoint.example/wm"></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://endpoint.example/wm')
    end

    it 'finds legacy rel="http://webmention.org/" link' do
      html = '<html><head><link rel="http://webmention.org/" href="https://endpoint.example/wm"></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://endpoint.example/wm')
    end

    it 'finds legacy rel="http://webmention.org" link' do
      html = '<html><head><link rel="http://webmention.org" href="https://endpoint.example/wm"></head></html>'
      expect(job.endpoint_from_body(html)).to eq('https://endpoint.example/wm')
    end

    it 'returns nil when no link present' do
      html = '<html><head></head><body>No wm</body></html>'
      expect(job.endpoint_from_body(html)).to be_nil
    end
  end

  describe '#uri_to_absolute' do
    it 'returns the same URI when already absolute' do
      base = URI.parse('https://target.test/article')
      absolute = 'https://endpoint.example/wm'
      expect(job.uri_to_absolute(absolute, base)).to eq(absolute)
    end

    it 'converts relative path to absolute using base URI' do
      base = URI.parse('https://target.test/article')
      relative = '/wm'
      result = job.uri_to_absolute(relative, base)
      expect(result.to_s).to match(%r{\Ahttps://target\.test(?::443)?/wm\z})
    end
  end

  describe 'enqueuing' do
    it 'enqueues the job on the default queue with arguments' do
      expect do
        described_class.perform_later('arg1')
      end.to have_enqueued_job(described_class).on_queue('default').with('arg1')
    end

    it 'enqueues the job with a delay' do
      expect do
        described_class.set(wait: 1.hour).perform_later('arg1')
      end.to have_enqueued_job(described_class).at(1.hour.from_now)
    end
  end
end
