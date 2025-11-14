require 'rails_helper'

RSpec.describe SendWebmentionJob, type: :job do
  include ActiveJob::TestHelper

  let(:story) do
    instance_double('Story', is_gone?: false, url: 'https://target.example/post')
  end

  let(:routes_double) do
    double('Routes', story_short_id_url: 'https://app.test/s/abc')
  end

  let(:sponge) do
    instance_double('Sponge')
  end

  let(:response) do
    instance_double('Response')
  end

  before do
    clear_enqueued_jobs
    clear_performed_jobs

    stub_const('Routes', routes_double)
    allow(routes_double).to receive(:story_short_id_url).with(story).and_return('https://app.test/s/abc')

    stub_const('NoIPsError', Class.new(StandardError))
    stub_const('DNSError', Class.new(StandardError))

    stub_const('Sponge', class_double('Sponge', new: sponge))
    allow(sponge).to receive(:timeout=)
    allow(sponge).to receive(:ssl_verify=)
    allow(sponge).to receive(:fetch)

    allow(response).to receive(:body).and_return('')
    allow(response).to receive(:[]).with('link').and_return(nil)
  end

  describe '#perform' do
    it 'returns early if story is gone' do
      allow(story).to receive(:is_gone?).and_return(true)
      job = described_class.new
      expect(sponge).not_to receive(:fetch)
      job.perform(story)
    end

    it 'returns early if story url is blank' do
      story_blank = instance_double('Story', is_gone?: false, url: '')
      job = described_class.new
      expect(sponge).not_to receive(:fetch)
      job.perform(story_blank)
    end

    context 'when in development environment' do
      before do
        allow(Rails).to receive_message_chain(:env, :development?).and_return(true)
      end

      it 'does not perform network calls' do
        job = described_class.new
        expect(sponge).not_to receive(:fetch)
        job.perform(story)
      end
    end

    context 'when fetching the target raises DNS errors' do
      it 'swallows NoIPsError and does not raise' do
        allow(sponge).to receive(:fetch).and_raise(NoIPsError)
        job = described_class.new
        expect do
          job.perform(story)
        end.not_to raise_error
      end

      it 'swallows DNSError and does not raise' do
        allow(sponge).to receive(:fetch).and_raise(DNSError)
        job = described_class.new
        expect do
          job.perform(story)
        end.not_to raise_error
      end
    end

    it 'returns early when fetch returns nil' do
      allow(sponge).to receive(:fetch).and_return(nil)
      job = described_class.new
      expect(job).not_to receive(:send_webmention)
      job.perform(story)
    end

    context 'when endpoint is discovered in Link header' do
      before do
        allow(sponge).to receive(:fetch).and_return(response)
        allow(response).to receive(:[]).with('link').and_return('<https://wm.example/endpoint>; rel="webmention"')
      end

      it 'sends webmention to the endpoint from headers' do
        job = described_class.new
        expect(job).to receive(:send_webmention).with('https://app.test/s/abc', 'https://target.example/post', satisfy do |endpoint|
          endpoint.to_s == 'https://wm.example/endpoint'
        end)
        job.perform(story)
      end

      it 'prefers header endpoint over body endpoint' do
        body_html = '<link rel="webmention" href="https://wrong.example/wm">'
        allow(response).to receive(:body).and_return(body_html)
        job = described_class.new
        expect(job).to receive(:send_webmention).with(anything, anything, satisfy do |endpoint|
          endpoint.to_s == 'https://wm.example/endpoint'
        end)
        job.perform(story)
      end
    end

    context 'when endpoint is discovered in HTML body' do
      before do
        allow(sponge).to receive(:fetch).and_return(response)
        allow(response).to receive(:[]).with('link').and_return(nil)
      end

      it 'handles absolute endpoint' do
        allow(response).to receive(:body).and_return('<link rel="webmention" href="https://wm.example/endpoint">')
        job = described_class.new
        expect(job).to receive(:send_webmention).with('https://app.test/s/abc', 'https://target.example/post', satisfy do |endpoint|
          endpoint.to_s == 'https://wm.example/endpoint'
        end)
        job.perform(story)
      end

      it 'resolves relative endpoint to absolute' do
        allow(response).to receive(:body).and_return('<link rel="webmention" href="/webmention">')
        job = described_class.new
        expect(job).to receive(:send_webmention).with('https://app.test/s/abc', 'https://target.example/post', satisfy do |endpoint|
          endpoint.to_s == 'https://target.example/webmention'
        end)
        job.perform(story)
      end
    end

    context 'when endpoint cannot be discovered' do
      it 'does not send a webmention' do
        allow(sponge).to receive(:fetch).and_return(response)
        allow(response).to receive(:[]).with('link').and_return(nil)
        allow(response).to receive(:body).and_return('<html><head></head><body>No endpoint here</body></html>')
        job = described_class.new
        expect(job).not_to receive(:send_webmention)
        job.perform(story)
      end
    end

    context 'when an unexpected error occurs' do
      it 'raises error to trigger retry' do
        allow(sponge).to receive(:fetch).and_raise(StandardError.new('boom'))
        job = described_class.new
        expect do
          job.perform(story)
        end.to raise_error(StandardError, 'boom')
      end
    end

    context 'idempotency' do
      it 'can be run multiple times without side effects' do
        allow(sponge).to receive(:fetch).and_return(response)
        allow(response).to receive(:[]).with('link').and_return('<https://wm.example/endpoint>; rel="webmention"')
        job = described_class.new
        expect(job).to receive(:send_webmention).twice
        job.perform(story)
        job.perform(story)
      end
    end
  end

  describe 'queueing' do
    it 'uses the default queue' do
      expect(described_class.queue_name).to eq('default')
    end

    it 'enqueues the job' do
      expect do
        described_class.perform_later(nil)
      end.to have_enqueued_job(described_class).with(nil).on_queue('default')
    end

    it 'enqueues the job with delay' do
      expect do
        described_class.set(wait: 1.hour).perform_later(nil)
      end.to have_enqueued_job(described_class).on_queue('default').at(1.hour.from_now)
    end
  end
end
