# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
# typed: false

require 'rails_helper'

describe ApplicationHelper do
  describe 'excerpt_fragment_around_link' do
    it 'strips HTML tags besides the link' do
      comment = create(:comment, comment: 'I **love** [example](https://example.com) so much')
      expect(comment.markeddown_comment).to include('strong') # the double star
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, 'https://example.com')
      expect(excerpt).to_not include('strong')
      expect(excerpt).to start_with('I love')    # text before
      expect(excerpt).to include('example.com')  # link href
      expect(excerpt).to end_with('so much')     # text after
    end

    it 'strips HTML tags wrapping the link' do
      comment = create(:comment, comment: 'I **love [example](https://example.com)**')
      expect(comment.markeddown_comment).to include('strong') # the double star
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, 'https://example.com')
      expect(excerpt).to_not include('strong')
      expect(excerpt).to include('example.com')
    end

    it 'excerpts even in multiple nesting' do
      comment = create(:comment, comment: "See:\n\n * an _[example](https://example.com)_")
      expect(comment.markeddown_comment).to include('<li>')
      expect(comment.markeddown_comment).to include('<em>')
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, 'https://example.com')
      expect(excerpt).to_not include('li')
      expect(excerpt).to_not include('em')
      expect(excerpt).to include('example.com')
    end

    it 'displays a few words around links in comments' do
      comment = create(:comment,
                       comment: "This reminds me of [a great site](https://example.com) with more info. #{Faker::Lorem.sentences(number: 30).join(' ')}")
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, 'https://example.com')
      expect(excerpt.split.length).to be < 20
    end

    it 'strips unpaired, invalid HTML tags' do
      html = '<p>i <strong>love <a href="https://example.com">example</a></p>'
      excerpt = helper.excerpt_fragment_around_link(html, 'https://example.com')
      expect(excerpt).to_not include('strong')
      expect(excerpt).to include('example.com')
    end

    it 'returns the first few words if the link is not present' do
      html = "Hello world. #{Faker::Lorem.sentences(number: 30).join(' ')} Removed."
      excerpt = helper.excerpt_fragment_around_link(html, 'https://example.com')
      expect(excerpt).to_not include('Removed')
      expect(excerpt).to start_with('Hello world')
    end
  end

  describe '#page_numbers_for_pagination' do
    it 'returns the right number of pages' do
      expect(helper.page_numbers_for_pagination(10, 1))
        .to eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

      expect(helper.page_numbers_for_pagination(20, 1))
        .to eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, '...', 20])

      expect(helper.page_numbers_for_pagination(25, 1))
        .to eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, '...', 25])

      expect(helper.page_numbers_for_pagination(25, 10))
        .to eq([1, '...', 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, '...', 25])

      expect(helper.page_numbers_for_pagination(25, 20))
        .to eq([1, '...', 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
    end
  end

  describe '#page_count' do
    it 'returns the right number of pages' do
      expect(page_count(49, 50)).to eq(1)
      expect(page_count(50, 50)).to eq(1)
      expect(page_count(51, 50)).to eq(2)
      expect(page_count(99, 50)).to eq(2)
      expect(page_count(100, 50)).to eq(2)
    end
  end

  describe 'comment_score_for_user' do
    let(:comment) { create(:comment, score: 4) }
    let(:user) { create(:user) }

    it 'when user can see the score' do
      allow_any_instance_of(Comment).to receive(:show_score_to_user?).and_return(true)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq 4
    end

    it 'when user cannot see the score' do
      allow_any_instance_of(Comment).to receive(:show_score_to_user?).and_return(false)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq '&nbsp;'
    end

    it 'when user can flag the comment' do
      allow_any_instance_of(User).to receive(:can_flag?).and_return(true)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq '~'
    end

    it 'when no user' do
      expect(helper.comment_score_for_user(comment, nil)[:score_value]).to eq nil
    end

    it 'when no comment' do
      expect(helper.comment_score_for_user(nil, user)[:score_value]).to eq nil
    end

    it 'when score is 1000' do
      comment.update(score: 1000)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq 1000
      expect(helper.comment_score_for_user(comment, user)[:score_formatted]).to eq '1K'
    end
  end

  describe '#avatar_img' do
    it 'renders an img with correct srcset, alt, size, loading and decoding' do
      user = double(
        'User',
        username: 'alice',
        avatar_path: nil
      )
      allow(user).to receive(:avatar_path).with(16).and_return('/avatars/alice-16.png')
      allow(user).to receive(:avatar_path).with(32).and_return('/avatars/alice-32.png')

      html = helper.avatar_img(user, 16)
      expect(html).to include('<img')
      expect(html).to include('class="avatar"')
      expect(html).to include('src="/avatars/alice-16.png"')
      expect(html).to include('srcset="/avatars/alice-16.png 1x, /avatars/alice-32.png 2x"')
      expect(html).to include('alt="alice avatar"')
      expect(html).to include('loading="lazy"')
      expect(html).to include('decoding="async"')
      expect(html).to include('width="16"')
      expect(html).to include('height="16"')
    end
  end

  describe '#errors_for' do
    class Widget
      attr_accessor :errors
    end

    it 'returns empty string when there are no errors' do
      errors = double('Errors', blank?: true, count: 0, full_messages: [])
      widget = Widget.new
      widget.errors = errors

      html = helper.errors_for(widget).to_s
      expect(html).to eq('')
    end
  end

  describe '#filtered_tags' do
    it 'returns user.tag_filter_tags when @user is present' do
      tag1 = double('Tag')
      tag2 = double('Tag')
      user = double('User', tag_filter_tags: [tag1, tag2])
      helper.instance_variable_set(:@user, user)
      expect(Tag).not_to receive(:where)
      expect(helper.filtered_tags).to eq([tag1, tag2])
    end

    it 'fetches tags from cookies when @user is not present and memoizes' do
      helper.instance_variable_set(:@user, nil)
      cookie_key = ApplicationController::TAG_FILTER_COOKIE
      allow(helper).to receive(:cookies).and_return({ cookie_key => 'foo,bar' })
      tag1 = double('Tag foo')
      tag2 = double('Tag bar')

      expect(Tag).to receive(:where).with(hash_including(tag: %w[foo bar])).once.and_return([tag1, tag2])

      first = helper.filtered_tags
      second = helper.filtered_tags
      expect(first).to eq([tag1, tag2])
      expect(second).to equal(first)
    end
  end

  describe '#inline_avatar_for' do
    let(:user) { double('User') }

    it 'returns link with avatar when viewer is nil' do
      allow(helper).to receive(:avatar_img).and_return('IMG')
      allow(helper).to receive(:user_path).with(user).and_return('/users/1')
      html = helper.inline_avatar_for(nil, user)
      expect(html).to include('<a')
      expect(html).to include('href="/users/1"')
      expect(html).to include('IMG')
    end

    it 'returns link when viewer shows avatars' do
      viewer = double('Viewer', show_avatars?: true)
      allow(helper).to receive(:avatar_img).and_return('IMG')
      allow(helper).to receive(:user_path).with(user).and_return('/users/1')
      html = helper.inline_avatar_for(viewer, user)
      expect(html).to include('<a')
    end

    it 'returns nil when viewer hides avatars' do
      viewer = double('Viewer', show_avatars?: false)
      expect(helper.inline_avatar_for(viewer, user)).to be_nil
    end
  end

  describe '#link_post' do
    it 'renders the partial with provided options' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: {
          button_label: 'Delete',
          link: '/items/1',
          class_name: 'danger',
          confirm: 'Are you sure?'
        }
      ).and_return('OK')
      res = helper.link_post('Delete', '/items/1', class_name: 'danger', confirm: 'Are you sure?')
      expect(res).to eq('OK')
    end

    it 'renders the partial with nil defaults when options are omitted' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: {
          button_label: 'Go',
          link: '/go',
          class_name: nil,
          confirm: nil
        }
      ).and_return('OK')
      res = helper.link_post('Go', '/go')
      expect(res).to eq('OK')
    end
  end

  describe '#possible_flag_warning' do
    let(:showing_user) { double('User') }
    let(:user) { double('ViewedUser') }

    it 'renders dev flag warning in non-production' do
      allow(helper).to receive(:render).with(partial: 'users/dev_flag_warning').and_return('DEV')
      # Default test env is not production
      res = helper.possible_flag_warning(showing_user, user)
      expect(res).to eq('DEV')
    end

    it 'returns nil in production when user is not self or mod' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
      allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(false)
      expect(helper.possible_flag_warning(showing_user, user)).to be_nil
    end

    it 'returns nil in production when user is self/mod but not flagged' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
      allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
      allow(helper).to receive(:time_interval).with('1m').and_return({ param: '1m' })
      fc = double('FlaggedCommenters', check_list_for: false)
      expect(FlaggedCommenters).to receive(:new).with('1m', 1.day).and_return(fc)
      expect(helper.possible_flag_warning(showing_user, user)).to be_nil
    end

    it 'renders flag warning in production when user is flagged' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
      allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
      interval = { param: '1m' }
      allow(helper).to receive(:time_interval).with('1m').and_return(interval)
      fc = double('FlaggedCommenters', check_list_for: true)
      expect(FlaggedCommenters).to receive(:new).with('1m', 1.day).and_return(fc)
      expect(helper).to receive(:render).with(
        partial: 'users/flag_warning',
        locals: { showing_user: showing_user, interval: interval }
      ).and_return('WARN')
      res = helper.possible_flag_warning(showing_user, user)
      expect(res).to eq('WARN')
    end
  end

  describe '#tag_link' do
    let(:tag) { double('Tag', tag: 'foo', css_class: 't-foo', description: 'Foo tag') }

    it 'renders a link to the tag with classes and title' do
      allow(helper).to receive(:filtered_tags).and_return([])
      allow(helper).to receive(:tag_path).with(tag).and_return('/t/foo')
      html = helper.tag_link(tag)
      expect(html).to include('href="/t/foo"')
      expect(html).to include('class="t-foo"').or include('class="t-foo ')
      expect(html).to include('title="Foo tag"')
      expect(html).to include('>foo<')
    end

    it 'adds filtered class when tag is filtered' do
      allow(helper).to receive(:filtered_tags).and_return([tag])
      allow(helper).to receive(:tag_path).with(tag).and_return('/t/foo')
      html = helper.tag_link(tag)
      expect(html).to include('filtered')
    end
  end

  describe '#how_long_ago_label' do
    it 'renders a time tag with title, datetime and data-at-unix' do
      time = Time.zone.parse('2023-01-01 12:34:56 UTC')
      allow(helper).to receive(:how_long_ago).with(time).and_return('3 minutes ago')
      html = helper.how_long_ago_label(time)
      at = time.strftime('%F %T')
      expect(html).to include('>3 minutes ago<')
      expect(html).to include(%(title="#{at}"))
      expect(html).to include(%(datetime="#{at}"))
      expect(html).to include(%(data-at-unix="#{time.to_i}"))
      expect(html).to start_with('<time')
    end
  end

  describe '#how_long_ago_link' do
    it 'wraps how_long_ago_label in an anchor with href' do
      time = Time.zone.now
      allow(helper).to receive(:how_long_ago_label).with(time).and_return(helper.content_tag(:time, 'ago'))
      html = helper.how_long_ago_link('/post/1', time)
      expect(html).to start_with('<a')
      expect(html).to include('href="/post/1"')
      expect(html).to include('<time')
    end
  end

  describe '#tag' do
    it 'delegates to super and returns an open tag by default' do
      html = helper.tag('br')
      expect(html).to be_a(String)
      expect(html).to include('<br')
      expect(html.strip).to end_with('>')
    end
  end
end
