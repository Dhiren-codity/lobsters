# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWebmentionJob, type: :job do
  before(:all) do
    Object.const_set(:NoIPsError, Class.new(StandardError)) unless defined?(NoIPsError)
    Object.const_set(:DNSError, Class.new(StandardError)) unless defined?(DNSError)
    Object.const_set(:Sponge, Class.new) unless defined?(Sponge)
    Object.const_set(:Routes, Module.new) unless defined?(Routes)
  end

  let(:story_url) { 'https://target.example/article' }
  let(:short_id) { 'abc123' }
  let(:source_url) { "https://news.example/s/#{short_id}" }

  class FakeStory
    include GlobalID::Identification

    attr_accessor :id, :url, :short_id, :gone

    def initialize(id:, url:, short_id:, gone: false)
      @id = id
      @url = url
      @short_id = short_id
      @gone = gone
      self.class.registry[id] = self
    end

    def is_gone?
      !!gone
    end

    def self.find(id)
      registry[id]
    end

    def self.registry
      @registry ||= {}
    end
  end

  let(:story) { FakeStory.new(id: 1, url: story_url, short_id: short_id, gone: false) }

  before do
    allow(Rails.application).to receive(:domain).and_return('news.example')
    allow(Routes).to receive(:story_short_id_url).with(story).and_return(source_url)
  end

  def expect_get_with_response(response)
    get_client = instance_double('SpongeGet')
    post_client = instance_double('SpongePost')

    allow(Sponge).to receive(:new).and_return(get_client, post_client)

    allow(get_client).to receive(:timeout=)
    allow(post_client).to receive(:timeout=)
    allow(post_client).to receive(:ssl_verify=)

    expect(get_client).to receive(:fetch).with(
      URI::RFC2396_PARSER.escape(story.url),
      :get,
      nil,
      nil,
      { 'User-agent' => "#{Rails.application.domain} webmention endpoint lookup" },
      3
    ).and_return(response)

    [get_client, post_client]
  end

  it 'enqueues the job with default queue and serializes the story via GlobalID' do
    ActiveJob::Base.queue_adapter = :test

    expect do
      described_class.perform_later(story)
    end.to have_enqueued_job(described_class).with(story).on_queue('default')
  end

  it 'returns early if story is gone' do
    story.gone = true

    expect(Sponge).not_to receive(:new)

    described_class.new.perform(story)
  end

  it 'returns early if story has blank url' do
    story.url = ''

    expect(Sponge).not_to receive(:new)

    described_class.new.perform(story)
  end

  it 'does nothing in development environment' do
    original_env = Rails.env
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

    expect(Sponge).not_to receive(:new)

    described_class.new.perform(story)

    allow(Rails).to receive(:env).and_return(original_env)
  end

  it 'discovers endpoint from Link header (quoted rel with webmention) and posts webmention' do
    response = instance_double('Response', :[] => '<https://endpoint.example/webmention>; rel="webmention"',
                                           body: '<html></html>')
    _get_client, post_client = expect_get_with_response(response)

    encoded_source = URI.encode_www_form_component(source_url)
    encoded_target = URI.encode_www_form_component(story_url)

    expect(post_client).to receive(:fetch).with(
      'https://endpoint.example/webmention',
      :post,
      { 'source' => encoded_source, 'target' => encoded_target },
      nil,
      {},
      3
    )

    described_class.new.perform(story)
  end

  it 'discovers endpoint from Link header (unquoted rel=webmention)' do
    response = instance_double('Response', :[] => '<https://endpoint.example/wm>; rel=webmention', body: '')
    _get_client, post_client = expect_get_with_response(response)

    expect(post_client).to receive(:fetch).with(
      'https://endpoint.example/wm',
      :post,
      hash_including('source', 'target'),
      nil,
      {},
      3
    )

    described_class.new.perform(story)
  end

  it 'discovers endpoint from Link header where rel appears before link' do
    response = instance_double('Response', :[] => 'rel="webmention"; <https://endpoint.example/wm>', body: '')
    _get_client, post_client = expect_get_with_response(response)

    expect(post_client).to receive(:fetch).with(
      'https://endpoint.example/wm',
      :post,
      hash_including('source', 'target'),
      nil,
      {},
      3
    )

    described_class.new.perform(story)
  end

  it 'discovers endpoint from Link header legacy rel http://webmention.org/' do
    response = instance_double('Response', :[] => '<https://endpoint.example/wm>; rel="http://webmention.org/"',
                                           body: '')
    _get_client, post_client = expect_get_with_response(response)

    expect(post_client).to receive(:fetch).with(
      'https://endpoint.example/wm',
      :post,
      hash_including('source', 'target'),
      nil,
      {},
      3
    )

    described_class.new.perform(story)
  end

  it 'falls back to HTML body discovery when Link header missing' do
    html = '<html><head><link rel="webmention" href="https://endpoint.example/wm"></head></html>'
    response = instance_double('Response', :[] => nil, body: html)
    _get_client, post_client = expect_get_with_response(response)

    expect(post_client).to receive(:fetch).with(
      'https://endpoint.example/wm',
      :post,
      hash_including('source', 'target'),
      nil,
      {},
      3
    )

    described_class.new.perform(story)
  end

  it 'resolves a relative endpoint from HTML to absolute using target URL' do
    html = '<html><head><link rel="webmention" href="/webmention"></head></html>'
    response = instance_double('Response', :[] => nil, body: html)
    _get_client, post_client = expect_get_with_response(response)

    expect(post_client).to receive(:fetch).with(
      'https://target.example/webmention',
      :post,
      hash_including('source', 'target'),
      nil,
      {},
      3
    )

    described_class.new.perform(story)
  end

  it 'does not attempt to post when no endpoint discovered' do
    html = '<html><head><title>No endpoint</title></head><body></body></html>'
    response = instance_double('Response', :[] => nil, body: html)
    _get_client, post_client = expect_get_with_response(response)

    expect(post_client).not_to receive(:fetch)

    described_class.new.perform(story)
  end

  it 'returns when target fetch returns nil response' do
    get_client = instance_double('SpongeGet')
    post_client = instance_double('SpongePost')

    allow(Sponge).to receive(:new).and_return(get_client, post_client)
    allow(get_client).to receive(:timeout=)
    allow(post_client).to receive(:timeout=)
    allow(post_client).to receive(:ssl_verify=)

    expect(get_client).to receive(:fetch).and_return(nil)
    expect(post_client).not_to receive(:fetch)

    described_class.new.perform(story)
  end

  it 'rescues DNSError during target fetch and does not attempt to post' do
    get_client = instance_double('SpongeGet')
    post_client = instance_double('SpongePost')

    allow(Sponge).to receive(:new).and_return(get_client, post_client)
    allow(get_client).to receive(:timeout=)
    allow(post_client).to receive(:timeout=)
    allow(post_client).to receive(:ssl_verify=)

    expect(get_client).to receive(:fetch).and_raise(DNSError)
    expect(post_client).not_to receive(:fetch)

    described_class.new.perform(story)
  end

  it 'rescues NoIPsError during target fetch and does not attempt to post' do
    get_client = instance_double('SpongeGet')
    post_client = instance_double('SpongePost')

    allow(Sponge).to receive(:new).and_return(get_client, post_client)
    allow(get_client).to receive(:timeout=)
    allow(post_client).to receive(:timeout=)
    allow(post_client).to receive(:ssl_verify=)

    expect(get_client).to receive(:fetch).and_raise(NoIPsError)
    expect(post_client).not_to receive(:fetch)

    described_class.new.perform(story)
  end

  it 'encodes source and target parameters when posting' do
    # Introduce characters that need encoding
    long_source = "#{source_url}?q=hello world&x=1+2"
    allow(Routes).to receive(:story_short_id_url).with(story).and_return(long_source)

    response = instance_double('Response', :[] => '<https://endpoint.example/wm>; rel="webmention"', body: '')
    _get_client, post_client = expect_get_with_response(response)

    expected_body = {
      'source' => URI.encode_www_form_component(long_source),
      'target' => URI.encode_www_form_component(story_url)
    }

    expect(post_client).to receive(:fetch).with(
      'https://endpoint.example/wm',
      :post,
      expected_body,
      nil,
      {},
      3
    )

    described_class.new.perform(story)
  end
end
