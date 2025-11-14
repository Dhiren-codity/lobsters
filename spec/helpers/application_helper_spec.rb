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

    it 'when user is moderator' do
      expect(helper.comment_score_for_user(comment, create(:user, :moderator))[:score_value]).to eq 4
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
    it 'renders an img with correct attributes and srcset' do
      user = double('User', username: 'alice')
      allow(user).to receive(:avatar_path) do |size|
        "/avatars/alice_#{size}.png"
      end

      html = helper.avatar_img(user, 32)
      fragment = Nokogiri::HTML.fragment(html)
      img = fragment.at_css('img')
      expect(img['src']).to eq('/avatars/alice_32.png')
      expect(img['srcset']).to include('/avatars/alice_32.png 1x')
      expect(img['srcset']).to include('/avatars/alice_64.png 2x')
      expect(img['class']).to include('avatar')
      expect(img['alt']).to eq('alice avatar')
      expect(img['loading']).to eq('lazy')
      expect(img['decoding']).to eq('async')
      expect(img['width']).to eq('32')
      expect(img['height']).to eq('32')
    end
  end

  describe '#errors_for' do
    it 'returns empty string when there are no errors' do
      object = double('Thing')
      errors = double('Errors', blank?: true)
      allow(object).to receive(:errors).and_return(errors)

      expect(helper.errors_for(object)).to eq('')
    end

    it 'renders formatted errors and replaces specific message' do
      object = double('Thing')
      errors = double(
        'Errors',
        blank?: false,
        count: 2,
        full_messages: ['Comments is invalid', "Title can't be blank"]
      )
      allow(object).to receive(:errors).and_return(errors)
      allow(object).to receive(:class).and_return(double(name: 'Post'))

      html = helper.errors_for(object)
      expect(html).to include('<div class="flash-error">')
      expect(html).to include('2 errors prohibited this post from being saved')
      expect(html).to include('There were the problems with the following fields:')
      expect(html).to include('<li>Comment is missing</li>')
      expect(html).to include("<li>Title can't be blank</li>")
    end
  end

  describe '#filtered_tags' do
    context 'when @user is present' do
      it "returns user's tag_filter_tags" do
        t1 = create(:tag, tag: 'ruby')
        t2 = create(:tag, tag: 'rails')
        user = double('User', tag_filter_tags: [t1, t2])
        helper.instance_variable_set(:@user, user)

        expect(helper.filtered_tags).to match_array([t1, t2])
      end
    end

    context 'when @user is not present' do
      it 'returns tags from cookies' do
        create(:tag, tag: 'ruby')
        create(:tag, tag: 'rails')
        create(:tag, tag: 'elixir')
        cookie_value = 'ruby,elixir'
        allow(helper).to receive(:cookies).and_return({ ApplicationController::TAG_FILTER_COOKIE => cookie_value })

        helper.instance_variable_set(:@user, nil)
        tags = helper.filtered_tags
        expect(tags.map(&:tag)).to match_array(%w[ruby elixir])
      end
    end
  end

  describe '#inline_avatar_for' do
    let(:user) do
      double('User', username: 'bob').tap do |u|
        allow(u).to receive(:avatar_path) { |size| "/avatars/bob_#{size}.png" }
      end
    end

    before do
      allow(helper).to receive(:user_path).with(user).and_return('/users/1')
    end

    it 'returns a link with avatar when viewer is nil' do
      html = helper.inline_avatar_for(nil, user)
      expect(html).to include('href="/users/1"')
      expect(html).to include('<img')
    end

    it 'returns a link with avatar when viewer shows avatars' do
      viewer = double('Viewer', show_avatars?: true)
      html = helper.inline_avatar_for(viewer, user)
      expect(html).to include('href="/users/1"')
      expect(html).to include('<img')
    end

    it 'returns nil when viewer hides avatars' do
      viewer = double('Viewer', show_avatars?: false)
      expect(helper.inline_avatar_for(viewer, user)).to be_nil
    end
  end

  describe '#link_to_different_page' do
    it 'adds current_page class when normalized path matches request path' do
      request_double = double('Request', path: '/posts/page/9')
      allow(helper).to receive(:request).and_return(request_double)

      path = '/posts/page/2'
      html = helper.link_to_different_page('Posts', path.dup, class: 'btn')
      expect(html).to include('class="btn current_page"').or include('class="current_page btn"')
      expect(html).to include('href="/posts"')
    end

    it 'does not add current_page class when path differs' do
      request_double = double('Request', path: '/posts')
      allow(helper).to receive(:request).and_return(request_double)

      html = helper.link_to_different_page('About', '/about', class: 'link')
      expect(html).to include('class="link"')
      expect(html).not_to include('current_page')
    end
  end

  describe '#link_post' do
    it 'renders the link_post partial with given locals' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: {
          button_label: 'Delete',
          link: '/posts/1',
          class_name: 'btn',
          confirm: 'Are you sure?'
        }
      ).and_return('<div>ok</div>')

      result = helper.link_post('Delete', '/posts/1', class_name: 'btn', confirm: 'Are you sure?')
      expect(result).to eq('<div>ok</div>')
    end
  end

  describe '#possible_flag_warning' do
    let(:showing_user) { double('User') }
    let(:user) { double('User') }

    it 'renders dev flag warning outside production' do
      allow(Rails).to receive_message_chain(:env, :production?).and_return(false)
      expect(helper).to receive(:render).with(partial: 'users/dev_flag_warning').and_return('dev')
      expect(helper.possible_flag_warning(showing_user, user)).to eq('dev')
    end

    it 'returns nil in production when self_or_mod is false' do
      allow(Rails).to receive_message_chain(:env, :production?).and_return(true)
      allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(false)
      expect(helper.possible_flag_warning(showing_user, user)).to be_nil
    end

    it 'renders flag warning when in production and user is flagged' do
      allow(Rails).to receive_message_chain(:env, :production?).and_return(true)
      allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
      allow(helper).to receive(:time_interval).with('1m').and_return({ param: '1m' })

      checker = instance_double('FlaggedCommenters')
      allow(FlaggedCommenters).to receive(:new).and_return(checker)
      allow(checker).to receive(:check_list_for).with(showing_user).and_return(true)

      expect(helper).to receive(:render).with(
        partial: 'users/flag_warning',
        locals: { showing_user: showing_user, interval: { param: '1m' } }
      ).and_return('flag')

      expect(helper.possible_flag_warning(showing_user, user)).to eq('flag')
    end

    it 'returns nil when in production and user is not flagged' do
      allow(Rails).to receive_message_chain(:env, :production?).and_return(true)
      allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
      allow(helper).to receive(:time_interval).with('1m').and_return({ param: '1m' })

      checker = instance_double('FlaggedCommenters')
      allow(FlaggedCommenters).to receive(:new).and_return(checker)
      allow(checker).to receive(:check_list_for).with(showing_user).and_return(false)

      expect(helper.possible_flag_warning(showing_user, user)).to be_nil
    end
  end

  describe '#tag_link' do
    let(:tag_obj) { double('Tag', tag: 'ruby', css_class: 'tag-ruby', description: 'Ruby language') }

    before do
      allow(helper).to receive(:tag_path).with(tag_obj).and_return('/t/ruby')
    end

    it 'renders link with tag css class and title' do
      allow(helper).to receive(:filtered_tags).and_return([])
      html = helper.tag_link(tag_obj)
      expect(html).to include('href="/t/ruby"')
      expect(html).to include('class="tag-ruby"').or include('class="tag-ruby filtered"')
      expect(html).to include('title="Ruby language"')
      expect(html).to include('>ruby<')
    end

    it 'adds filtered class when tag is filtered' do
      allow(helper).to receive(:filtered_tags).and_return([tag_obj])
      html = helper.tag_link(tag_obj)
      expect(html).to include('filtered')
    end
  end

  describe '#how_long_ago_label' do
    it 'renders a time tag with proper attributes' do
      time = Time.zone.parse('2023-01-02 03:04:05 UTC')
      allow(helper).to receive(:how_long_ago).with(time).and_return('3 minutes ago')

      html = helper.how_long_ago_label(time)
      fragment = Nokogiri::HTML.fragment(html)
      t = fragment.at_css('time')
      expect(t.text).to eq('3 minutes ago')
      expect(t['title']).to eq(time.strftime('%F %T'))
      expect(t['datetime']).to eq(time.strftime('%F %T'))
      expect(t['data-at-unix']).to eq(time.to_i.to_s)
    end
  end

  describe '#how_long_ago_link' do
    it 'wraps the label in a link' do
      time = Time.zone.parse('2023-01-02 03:04:05 UTC')
      allow(helper).to receive(:how_long_ago_label).with(time).and_return('<time>ago</time>')

      html = helper.how_long_ago_link('/posts/1', time)
      fragment = Nokogiri::HTML.fragment(html)
      a = fragment.at_css('a')
      expect(a['href']).to eq('/posts/1')
      expect(a.inner_html).to include('<time>ago</time>')
    end
  end

  describe '#tag' do
    it 'delegates to ActionView tag helper' do
      html = helper.tag(:br)
      expect(html).to include('<br')
    end
  end
end
