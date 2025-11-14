require 'rails_helper'

RSpec.describe SendWebmentionJob, type: :job do
  let(:story_url) { 'https://target.example/post' }
  let(:story) { double('Story', is_gone?: false, url: story_url) }
  let(:source_url) { 'https://app.example/s/abc' }

  before do
    allow(Routes).to receive(:story_short_id_url).with(story).and_return(source_url)
    allow(Rails).to receive_message_chain(:application, :domain).and_return('example.com')
    stub_const('NoIPsError', Class.new(StandardError)) unless defined?(NoIPsError)
    stub_const('DNSError', Class.new(StandardError)) unless defined?(DNSError)
  end

  def build_response(header: nil, body: '')
    response = double('Response', body: body)
    allow(response).to receive(:[]).with('link').and_return(header)
    response
  end

  describe '#perform' do
    it 'returns early when the story is gone' do
      gone_story = double('Story', is_gone?: true, url: story_url)
      expect(Sponge).not_to receive(:new)
      described_class.new.perform(gone_story)
    end

    it 'returns early when the story URL is blank' do
      blank_story = double('Story', is_gone?: false, url: '')
      expect(Sponge).not_to receive(:new)
      described_class.new.perform(blank_story)
    end

    it 'returns early when in development environment' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      expect(Sponge).not_to receive(:new)
      described_class.new.perform(story)
    end

    it 'rescues DNS-related errors and does not raise' do
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_raise(NoIPsError)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).not_to receive(:send_webmention)
      expect do
        job.perform(story)
      end.not_to raise_error
    end

    it 'returns when no response is received' do
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(nil)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).not_to receive(:send_webmention)
      job.perform(story)
    end

    it 'returns when no endpoint is discovered' do
      response = build_response(header: nil, body: '<html><head></head><body>No webmention here</body></html>')
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).not_to receive(:send_webmention)
      job.perform(story)
    end

    it 'discovers endpoint from Link header with rel="webmention" and sends webmention' do
      header = '<https://wm.example/endpoint>; rel="webmention"'
      response = build_response(header: header, body: '')
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).to receive(:send_webmention).with(source_url, story_url, 'https://wm.example/endpoint')
      job.perform(story)
    end

    it 'discovers endpoint from Link header with bare rel=webmention and sends webmention' do
      header = '<https://wm.example/bare>; rel=webmention'
      response = build_response(header: header, body: '')
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).to receive(:send_webmention).with(source_url, story_url, 'https://wm.example/bare')
      job.perform(story)
    end

    it 'discovers endpoint from HTML body link[rel~="webmention"] and sends webmention' do
      body = '<html><head><link rel="webmention" href="https://wm.example/from_body"></head><body></body></html>'
      response = build_response(header: nil, body: body)
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).to receive(:send_webmention).with(source_url, story_url, 'https://wm.example/from_body')
      job.perform(story)
    end

    it 'translates relative endpoint to absolute before sending' do
      body = '<html><head><link rel="webmention" href="/wm-endpoint"></head><body></body></html>'
      response = build_response(header: nil, body: body)
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).to receive(:send_webmention) do |src, tgt, endpoint|
        expect(src).to eq(source_url)
        expect(tgt).to eq(story_url)
        expect(endpoint.to_s).to match(%r{\Ahttps://target\.example(:443)?/wm-endpoint\z})
      end
      job.perform(story)
    end

    it 'raises error to allow retry when non-DNS error occurs during fetch' do
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_raise(StandardError, 'boom')
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect do
        job.perform(story)
      end.to raise_error(StandardError, 'boom')
    end

    it 'raises error to allow retry when sending webmention fails' do
      header = '<https://wm.example/endpoint>; rel="webmention"'
      response = build_response(header: header, body: '')
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      allow(job).to receive(:send_webmention).and_raise(StandardError, 'post failed')

      expect do
        job.perform(story)
      end.to raise_error(StandardError, 'post failed')
    end

    it 'is idempotent in that running twice triggers two sends for the same input' do
      header = '<https://wm.example/endpoint>; rel="webmention"'
      response = build_response(header: header, body: '')
      get_sponge = double('SpongeGET')
      allow(get_sponge).to receive(:timeout=)
      allow(get_sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(get_sponge)

      job = described_class.new
      expect(job).to receive(:send_webmention).with(source_url, story_url, 'https://wm.example/endpoint').twice
      job.perform(story)
      job.perform(story)
    end
  end

  describe 'enqueuing' do
    include ActiveJob::TestHelper

    before do
      clear_enqueued_jobs
    end

    it 'enqueues the job on the default queue' do
      expect do
        described_class.perform_later('arg')
      end.to have_enqueued_job(described_class).on_queue('default').with('arg')
    end

    it 'enqueues the job with a delay' do
      expect do
        described_class.set(wait: 1.hour).perform_later('arg')
      end.to have_enqueued_job(described_class).at(1.hour.from_now)
    end
  end
end
