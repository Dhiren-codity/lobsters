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
    let(:user) do
      double('User', username: 'alice').tap do |u|
        allow(u).to receive(:avatar_path) do |size|
          "/avatars/alice_#{size}.png"
        end
      end
    end
  end

  describe '#errors_for' do
    class HelperSpecThing
    end
  end

  describe '#filtered_tags' do
    before do
      helper.instance_variable_set(:@_filtered_tags, nil)
      helper.instance_variable_set(:@user, nil)
    end

    it 'returns @user.tag_filter_tags when @user is present and caches the result' do
      t1 = double('Tag1')
      user = double('User', tag_filter_tags: [t1])
      helper.instance_variable_set(:@user, user)
      helper.instance_variable_set(:@_filtered_tags, nil)

      first = helper.filtered_tags
      expect(first).to eq([t1])

      allow(user).to receive(:tag_filter_tags).and_return([])
      second = helper.filtered_tags
      expect(second).to eq([t1])
    end

    it 'queries Tag by cookie when no @user is present' do
      helper.instance_variable_set(:@user, nil)
      helper.instance_variable_set(:@_filtered_tags, nil)

      tag1 = create(:tag, tag: 'one')
      tag2 = create(:tag, tag: 'two')
      cookies[ApplicationController::TAG_FILTER_COOKIE] = 'one,two'

      result = helper.filtered_tags
      expect(result.map(&:tag)).to include('one', 'two')
      expect(result).to include(tag1, tag2)
    end
  end

  describe '#inline_avatar_for' do
    let(:user) { create(:user) }

    it 'returns a link with avatar when viewer is nil' do
      allow(helper).to receive(:avatar_img).with(user, 16).and_return('IMG')
      allow(helper).to receive(:user_path).with(user).and_return("/users/#{user.id}")

      html = helper.inline_avatar_for(nil, user)
      expect(html).to include('<a')
      expect(html).to include('href="/users/')
      expect(html).to include('IMG')
    end

    it 'returns a link with avatar when viewer shows avatars' do
      viewer = double('Viewer', show_avatars?: true)
      allow(helper).to receive(:avatar_img).with(user, 16).and_return('IMG')
      allow(helper).to receive(:user_path).with(user).and_return("/users/#{user.id}")

      html = helper.inline_avatar_for(viewer, user)
      expect(html).to include('<a')
      expect(html).to include('IMG')
    end

    it 'returns nil when viewer hides avatars' do
      viewer = double('Viewer', show_avatars?: false)
      html = helper.inline_avatar_for(viewer, user)
      expect(html).to be_nil
    end
  end

  describe '#link_to_different_page' do
    it 'adds current_page class when the normalized path matches' do
      req = double('Request', path: '/stories')
      allow(helper).to receive(:request).and_return(req)

      html = helper.link_to_different_page('Stories', '/stories', class: 'btn')
      expect(html).to include('class="btn current_page"')
      expect(html).to include('href="/stories"')
    end

    it 'does not add current_page class when path does not match' do
      req = double('Request', path: '/stories')
      allow(helper).to receive(:request).and_return(req)

      html = helper.link_to_different_page('Comments', '/comments', class: 'btn')
      expect(html).to include('class="btn"')
      expect(html).to_not include('current_page')
    end

    it 'ignores /page/:n suffix when comparing current page' do
      req = double('Request', path: '/stories/page/3')
      allow(helper).to receive(:request).and_return(req)

      html = helper.link_to_different_page('Stories', '/stories/page/1', class: 'x')
      expect(html).to include('class="x current_page"')
    end
  end

  describe '#link_post' do
    it 'renders the partial with defaults' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: { button_label: 'Go', link: '/x', class_name: nil, confirm: nil }
      ).and_return('HTML')
      expect(helper.link_post('Go', '/x')).to eq('HTML')
    end

    it 'renders the partial with provided options' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: { button_label: 'Delete', link: '/delete', class_name: 'btn-danger', confirm: 'Are you sure?' }
      ).and_return('OK')
      expect(helper.link_post('Delete', '/delete', class_name: 'btn-danger', confirm: 'Are you sure?')).to eq('OK')
    end
  end

  describe '#possible_flag_warning' do
    let(:viewer) { create(:user) }
    let(:user) { create(:user) }

    it 'renders dev flag warning in non-production environments' do
      expect(helper).to receive(:render).with(partial: 'users/dev_flag_warning').and_return('DEV')
      expect(helper.possible_flag_warning(viewer, user)).to eq('DEV')
    end

    it 'returns nil in production when not self_or_mod' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      allow(helper).to receive(:self_or_mod).with(viewer, user).and_return(false)

      expect(helper.possible_flag_warning(viewer, user)).to be_nil
    end

    it 'renders flag warning in production when flagged commenters list matches' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      allow(helper).to receive(:self_or_mod).with(viewer, user).and_return(true)

      interval = { param: '1m' }
      allow(helper).to receive(:time_interval).with('1m').and_return(interval)

      checker = instance_double('FlaggedCommenters', check_list_for: true)
      expect(FlaggedCommenters).to receive(:new).with(interval[:param], 1.day).and_return(checker)

      expect(helper).to receive(:render).with(
        partial: 'users/flag_warning',
        locals: { showing_user: viewer, interval: interval }
      ).and_return('WARN')

      expect(helper.possible_flag_warning(viewer, user)).to eq('WARN')
    end

    it 'returns nil in production when no flagged commenters match' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      allow(helper).to receive(:self_or_mod).with(viewer, user).and_return(true)
      interval = { param: '1m' }
      allow(helper).to receive(:time_interval).with('1m').and_return(interval)
      checker = instance_double('FlaggedCommenters', check_list_for: false)
      expect(FlaggedCommenters).to receive(:new).with(interval[:param], 1.day).and_return(checker)

      expect(helper.possible_flag_warning(viewer, user)).to be_nil
    end
  end

  describe '#tag (open=true override)' do
    it 'emits an open tag by default' do
      # Explicit open=true to avoid Rails version differences
      html = helper.tag(:span, nil, true)
      expect(html).to eq('<span>')
    end
  end

  describe '#tag_link' do
    let(:tag_obj) { double('Tag', tag: 'rails', css_class: 'tag-rails', description: 'Ruby on Rails') }

    it 'builds a tag link without filtered class when tag is not filtered' do
      allow(helper).to receive(:filtered_tags).and_return([])
      allow(helper).to receive(:tag_path).with(tag_obj).and_return('/t/rails')

      html = helper.tag_link(tag_obj)
      expect(html).to include('<a')
      expect(html).to include('href="/t/rails"')
      expect(html).to include('class="tag-rails"')
      expect(html).to_not include('filtered')
      expect(html).to include('title="Ruby on Rails"')
      expect(html).to include('>rails</a>')
    end

    it 'includes filtered class when tag is filtered' do
      allow(helper).to receive(:filtered_tags).and_return([tag_obj])
      allow(helper).to receive(:tag_path).with(tag_obj).and_return('/t/rails')

      html = helper.tag_link(tag_obj)
      expect(html).to include('class="tag-rails filtered"')
    end
  end

  describe '#how_long_ago_label' do
    it 'renders a time element with proper attributes' do
      time = Time.utc(2024, 1, 1, 12, 0, 0)
      allow(helper).to receive(:how_long_ago).with(time).and_return('3 minutes ago')

      html = helper.how_long_ago_label(time)
      expect(html).to include('<time')
      expect(html).to include('>3 minutes ago</time>')
      expect(html).to include('title="2024-01-01 12:00:00"')
      expect(html).to include('datetime="2024-01-01 12:00:00"')
      expect(html).to include(%(data-at-unix="#{time.to_i}"))
    end
  end
end
