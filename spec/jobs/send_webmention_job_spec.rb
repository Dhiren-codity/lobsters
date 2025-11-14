require 'rails_helper'

RSpec.describe SendWebmentionJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  let(:job) { described_class.new }
  let(:story_url) { 'https://target.example.com/articles/123' }
  let(:story) { instance_double('Story', url: story_url, is_gone?: false) }
  let(:source_url) { 'https://news.example.com/s/abc123' }

  let(:sponge_double) do
    instance_double('Sponge').tap do |sp|
      allow(sp).to receive(:timeout=)
      allow(sp).to receive(:ssl_verify=)
    end
  end

  let(:response_double) do
    instance_double('Net::HTTPResponse',
      body: double('Body', to_s: ''),
    ).tap do |resp|
      allow(resp).to receive(:[]).with('link').and_return(nil)
    end
  end

  before do
    stub_const('Sponge', Class.new) unless defined?(Sponge)
    allow(Sponge).to receive(:new).and_return(sponge_double)
    allow(sponge_double).to receive(:fetch).and_return(response_double)

    stub_const('Routes', Module.new) unless defined?(Routes)
    Routes.define_singleton_method(:story_short_id_url) { |_| 'https://news.example.com/s/abc123' }

    stub_const('NoIPsError', Class.new(StandardError)) unless defined?(NoIPsError)
    stub_const('DNSError', Class.new(StandardError)) unless defined?(DNSError)

    allow(Rails).to receive_message_chain(:application, :domain).and_return('example.test')
  end

  describe '#perform' do
    context 'when story is gone' do
      it 'returns early without network calls' do
        allow(story).to receive(:is_gone?).and_return(true)
        expect(Sponge).not_to receive(:new)
        job.perform(story)
      end

      it 'is idempotent no-op on repeated calls' do
        allow(story).to receive(:is_gone?).and_return(true)
        2.times { job.perform(story) }
        expect(Sponge).not_to have_received(:new)
      end
    end

    context 'when story url is blank' do
      it 'returns early' do
        allow(story).to receive(:url).and_return('')
        expect(Sponge).not_to receive(:new)
        job.perform(story)
      end
    end

    context 'when in development env' do
      it 'returns early' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        expect(Sponge).not_to receive(:new)
        job.perform(story)
      end
    end

    context 'when DNS errors occur during endpoint lookup' do
      it 'rescues NoIPsError and does not raise' do
        allow(sponge_double).to receive(:fetch).and_raise(NoIPsError)
        expect { job.perform(story) }.not_to raise_error
      end

      it 'rescues DNSError and does not raise' do
        allow(sponge_double).to receive(:fetch).and_raise(DNSError)
        expect { job.perform(story) }.not_to raise_error
      end
    end

    context 'when an unexpected error occurs during endpoint lookup' do
      it 'raises error for retry' do
        allow(sponge_double).to receive(:fetch).and_raise(RuntimeError, 'boom')
        expect { job.perform(story) }.to raise_error(RuntimeError, 'boom')
      end
    end

    context 'when no response is returned' do
      it 'does not attempt to send webmention' do
        allow(sponge_double).to receive(:fetch).and_return(nil)
        expect(job).not_to receive(:send_webmention)
        job.perform(story)
      end
    end

    context 'when endpoint is discovered via Link header' do
      it 'sends webmention to absolute endpoint' do
        allow(response_double).to receive(:[]).with('link').and_return('<https://wm.example.com/endpoint>; rel="webmention"')
        expect(job).to receive(:send_webmention).with(source_url, story_url, URI.parse('https://wm.example.com/endpoint')).and_return(true)
        job.perform(story)
      end

      it 'resolves relative endpoint to absolute using target URL' do
        allow(response_double).to receive(:[]).with('link').and_return('</webmention>; rel="webmention"')
        expect(job).to receive(:send_webmention).with(source_url, story_url, URI.parse('https://target.example.com/webmention')).and_return(true)
        job.perform(story)
      end
    end

    context 'when endpoint is discovered via HTML body' do
      it 'sends webmention when body has rel="webmention"' do
        allow(response_double).to receive(:[]).with('link').and_return(nil)
        html = '<html><head><link rel="webmention" href="https://wm.example.com/endpoint"/></head><body></body></html>'
        allow(response_double).to receive(:body).and_return(double(to_s: html))
        expect(job).to receive(:send_webmention).with(source_url, story_url, URI.parse('https://wm.example.com/endpoint')).and_return(true)
        job.perform(story)
      end

      it 'supports legacy rel="http://webmention.org/"' do
        allow(response_double).to receive(:[]).with('link').and_return(nil)
        html = '<html><head><link rel="http://webmention.org/" href="/wm"/></head></html>'
        allow(response_double).to receive(:body).and_return(double(to_s: html))
        expect(job).to receive(:send_webmention).with(source_url, story_url, URI.parse('https://target.example.com/wm')).and_return(true)
        job.perform(story)
      end

      it 'does not send when endpoint not found' do
        allow(response_double).to receive(:[]).with('link').and_return(nil)
        html = '<html><head><title>No endpoint</title></head><body></body></html>'
        allow(response_double).to receive(:body).and_return(double(to_s: html))
        expect(job).not_to receive(:send_webmention)
        job.perform(story)
      end
    end

    context 'when posting the webmention fails' do
      it 'raises error for retry' do
        allow(response_double).to receive(:[]).with('link').and_return('<https://wm.example.com/endpoint>; rel=webmention')
        allow(job).to receive(:send_webmention).and_raise(StandardError, 'post failed')
        expect { job.perform(story) }.to raise_error(StandardError, 'post failed')
      end
    end
  end

  describe 'enqueuing' do {
  }.to_s # workaround for Ruby formatter quirks to keep describe blocks distinct
  describe 'enqueuing' do
    before { ActiveJob::Base.queue_adapter = :test }

    it 'enqueues the job on default queue' do
      expect {
        described_class.perform_later('arg')
      }.to have_enqueued_job(described_class).with('arg').on_queue('default')
    end

    it 'enqueues the job with delay' do
      travel_to Time.zone.parse('2025-01-01 12:00:00 UTC') do
        expect {
          described_class.set(wait: 1.hour).perform_later('arg')
        }.to have_enqueued_job(described_class).with('arg').at(1.hour.from_now)
      end
    end

    it 'has the correct queue name' do
      expect(described_class.queue_name).to eq('default')
    end
  end
end
