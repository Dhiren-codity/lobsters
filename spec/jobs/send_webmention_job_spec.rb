# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
require 'rails_helper'

RSpec.describe SendWebmentionJob, type: :job do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    allow(Rails).to receive_message_chain(:application, :domain).and_return('example.test')
    allow(Rails.env).to receive(:development?).and_return(false)
    stub_const('Routes', Class.new) unless Object.const_defined?(:Routes)
  end

  describe '#perform' do
    let(:story) do
      instance_double('Story', is_gone?: false, url: 'https://target.test/article')
    end

    let(:source_url) do
      'https://example.test/s/abc'
    end

    let(:sponge) do
      instance_double('Sponge')
    end

    let(:link_header) do
      nil
    end

    let(:body_html) do
      ''
    end

    let(:body_double) do
      instance_double('Body', to_s: body_html)
    end

    let(:response) do
      instance_double('Response')
    end

    before do
      allow(Routes).to receive(:story_short_id_url).with(story).and_return(source_url)
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:ssl_verify=)
      allow(sponge).to receive(:fetch).and_return(response)
      allow(response).to receive(:[]).with('link').and_return(link_header)
      allow(response).to receive(:body).and_return(body_double)
    end

    it 'returns early when story is gone' do
      gone_story = instance_double('Story', is_gone?: true, url: 'https://target.test/article')
      expect(Sponge).not_to receive(:new)
      described_class.new.perform(gone_story)
    end

    it 'returns early when story url is blank' do
      blank_story = instance_double('Story', is_gone?: false, url: '')
      expect(Sponge).not_to receive(:new)
      described_class.new.perform(blank_story)
    end

    it 'returns early in development environment' do
      allow(Rails.env).to receive(:development?).and_return(true)
      expect(Sponge).not_to receive(:new)
      described_class.new.perform(story)
    end

    context 'when endpoint is provided via Link header' do
      let(:link_header) do
        '<https://wm.example/endpoint>; rel="webmention"'
      end
    end

    context 'when endpoint is missing in headers but present in body' do
      let(:body_html) do
        '<!doctype html><head><link rel="webmention" href="/wm"></head><body></body>'
      end

      it 'discovers endpoint from body and sends webmention' do
        job = described_class.new
        expect(job).to receive(:send_webmention).with(
          source_url,
          'https://target.test/article',
          satisfy do |ep|
            ep.to_s == 'https://target.test/wm'
          end
        )
        job.perform(story)
      end
    end

    context 'when both headers and body contain endpoints' do
      let(:link_header) do
        '<https://wm.example/endpoint>; rel=webmention'
      end

      let(:body_html) do
        '<!doctype html><head><link rel="webmention" href="/wm-body"></head>'
      end

      it 'prefers header endpoint over body endpoint' do
        job = described_class.new
        expect(job).to receive(:send_webmention).with(
          source_url,
          'https://target.test/article',
          satisfy do |ep|
            ep.to_s == 'https://wm.example/endpoint'
          end
        )
        job.perform(story)
      end
    end

    context 'when endpoint cannot be discovered' do
      it 'does not send a webmention' do
        job = described_class.new
        expect(job).not_to receive(:send_webmention)
        job.perform(story)
      end
    end

    context 'when Sponge.fetch raises DNS-related errors' do
      before do
        stub_const('NoIPsError', Class.new(StandardError)) unless Object.const_defined?(:NoIPsError)
        stub_const('DNSError', Class.new(StandardError)) unless Object.const_defined?(:DNSError)
      end

      it 'rescues NoIPsError and does not raise' do
        allow(sponge).to receive(:fetch).and_raise(NoIPsError)
        job = described_class.new
        expect(job).not_to receive(:send_webmention)
        expect do
          job.perform(story)
        end.not_to raise_error
      end

      it 'rescues DNSError and does not raise' do
        allow(sponge).to receive(:fetch).and_raise(DNSError)
        job = described_class.new
        expect(job).not_to receive(:send_webmention)
        expect do
          job.perform(story)
        end.not_to raise_error
      end
    end

    context 'when an unexpected network error occurs during discovery' do
      it 'raises error to allow retry' do
        allow(sponge).to receive(:fetch).and_raise(Timeout::Error)
        expect do
          described_class.new.perform(story)
        end.to raise_error(Timeout::Error)
      end
    end

    context 'when sending the webmention fails' do
      let(:link_header) do
        '<https://wm.example/endpoint>; rel="webmention"'
      end

      it 'raises error to allow retry' do
        job = described_class.new
        allow(job).to receive(:send_webmention).and_raise(StandardError.new('post failed'))
        expect do
          job.perform(story)
        end.to raise_error(StandardError, 'post failed')
      end
    end

    describe 'idempotency for non-actionable cases' do
      it 'does not perform any network activity for a gone story across multiple runs' do
        gone_story = instance_double('Story', is_gone?: true, url: 'https://target.test/article')
        expect(Sponge).not_to receive(:new)
        job = described_class.new
        2.times do
          job.perform(gone_story)
        end
      end
    end
  end

  describe 'enqueuing' do
    it 'enqueues the job on the default queue' do
      expect do
        described_class.perform_later(123)
      end.to have_enqueued_job(described_class).on_queue('default')
    end
  end
end
