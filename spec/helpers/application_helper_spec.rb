require 'rails_helper'

describe ApplicationHelper do
  describe 'excerpt_fragment_around_link' do
    it 'strips HTML tags besides the link' do
      comment = create(:comment, comment: 'I love [example](https://example.com) so much')
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
      # Count words ignoring HTML tags
      text_only = excerpt.gsub(/<[^>]+>/, ' ')
      expect(text_only.split.length).to be < 20
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
      allow_any_instance_of(Comment).to receive(:show_score_to_user?).and_return(false)
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
    it 'renders an image tag with proper srcset, alt, class, and dimensions' do
      user = double('User', username: 'alice')
      allow(user).to receive(:avatar_path) do |size|
        "/avatars/alice-#{size}.png"
      end

      html = helper.avatar_img(user, 16)
      expect(html).to include('src="/avatars/alice-16.png"')
      expect(html).to include('srcset="/avatars/alice-16.png 1x, /avatars/alice-32.png 2x"')
      expect(html).to include('class="avatar"')
      expect(html).to include('alt="alice avatar"')
      expect(html).to include('loading="lazy"')
      expect(html).to include('decoding="async"')
      expect(html).to include('width="16"')
      expect(html).to include('height="16"')
    end
  end

  describe '#errors_for' do
    let(:dummy_class) do
      stub_const('SpecModel', Class.new do
        include ActiveModel::Model
        attr_accessor :name
      end)
    end

    it 'returns empty string when there are no errors' do
      obj = dummy_class.new(name: 'ok')
      expect(helper.errors_for(obj)).to eq('')
    end

    it 'renders a flash error div with pluralized header and messages' do
      obj = dummy_class.new
      obj.errors.add(:name, :blank)
      html = helper.errors_for(obj)
      expect(html).to include('class="flash-error"')
      # normalize whitespace introduced by multiline string in the helper
      normalized = html.gsub(/\s+/, ' ')
      expect(normalized).to include("1 error prohibited this #{obj.class.name.downcase} from being saved")
      expect(html).to include('<ul>')
      expect(html).to include("Name can't be blank")
    end

    it "replaces 'Comments is invalid' with 'Comment is missing'" do
      obj = dummy_class.new
      obj.errors.add(:comments, :invalid)
      html = helper.errors_for(obj)
      expect(html).to include('<li>Comment is missing</li>')
      expect(html).to_not include('Comments is invalid')
    end
  end

  describe '#filtered_tags' do
    it 'returns @user.tag_filter_tags when @user is present' do
      u = double('User', tag_filter_tags: %i[foo bar])
      helper.instance_variable_set(:@user, u)
      expect(helper.filtered_tags).to eq(%i[foo bar])
    end

    it 'queries Tag.where based on cookie when @user is not present' do
      helper.instance_variable_set(:@user, nil)
      tags = [double('Tag1'), double('Tag2')]
      cookie_key = ApplicationController::TAG_FILTER_COOKIE
      cookie_store = {}
      cookie_store[cookie_key] = 'a,b'
      allow(helper).to receive(:cookies).and_return(cookie_store)
      expect(Tag).to receive(:where).with(tag: %w[a b]).and_return(tags)
      expect(helper.filtered_tags).to eq(tags)
    end
  end

  describe '#inline_avatar_for' do
    let(:user) { double('UserObj') }

    it 'returns link with avatar when viewer is nil' do
      allow(helper).to receive(:avatar_img).with(user, 16).and_return('IMG')
      allow(helper).to receive(:user_path).with(user).and_return('/users/1')
      html = helper.inline_avatar_for(nil, user)
      expect(html).to include('<a href="/users/1">IMG</a>')
    end

    it 'returns link with avatar when viewer shows avatars' do
      viewer = double('Viewer', show_avatars?: true)
      allow(helper).to receive(:avatar_img).with(user, 16).and_return('IMG')
      allow(helper).to receive(:user_path).with(user).and_return('/users/1')
      html = helper.inline_avatar_for(viewer, user)
      expect(html).to include('<a href="/users/1">IMG</a>')
    end

    it 'returns nil when viewer hides avatars' do
      viewer = double('Viewer', show_avatars?: false)
      expect(helper.inline_avatar_for(viewer, user)).to be_nil
    end
  end

  describe '#link_to_different_page' do
    before do
      req = double('Request', path: '/stories/page/2')
      allow(helper).to receive(:request).and_return(req)
    end

    it 'marks link as current_page when path matches after pagination stripping' do
      html = helper.link_to_different_page('Stories', '/stories/page/1'.dup, class: 'base')
      expect(html).to include('href="/stories"')
      expect(html).to include('class="base current_page"')
    end

    it 'does not mark as current_page when path differs' do
      html = helper.link_to_different_page('Other', '/other'.dup, class: 'base')
      expect(html).to include('href="/other"')
      expect(html).to include('class="base"')
      expect(html).to_not include('current_page')
    end
  end

  describe '#link_post' do
    it 'renders the partial with provided locals' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: {
          button_label: 'Delete',
          link: '/items/1',
          class_name: 'danger',
          confirm: 'Are you sure?'
        }
      ).and_return('OK')

      result = helper.link_post('Delete', '/items/1', class_name: 'danger', confirm: 'Are you sure?')
      expect(result).to eq('OK')
    end

    it 'renders with nil defaults when options are omitted' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: {
          button_label: 'Click',
          link: '/somewhere',
          class_name: nil,
          confirm: nil
        }
      ).and_return('OK')

      result = helper.link_post('Click', '/somewhere')
      expect(result).to eq('OK')
    end
  end

  describe '#possible_flag_warning' do
    let(:showing_user) { double('User') }
    let(:user) { double('ProfileUser') }

    it 'renders dev flag warning when not in production' do
      expect(helper).to receive(:render).with(partial: 'users/dev_flag_warning').and_return('DEV')
      result = helper.possible_flag_warning(showing_user, user)
      expect(result).to eq('DEV')
    end

    context 'in production' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      end

      it 'returns nil when not self_or_mod' do
        allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(false)
        expect(helper.possible_flag_warning(showing_user, user)).to be_nil
      end

      it 'renders flag warning when flagged commenters include the user' do
        allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
        allow(helper).to receive(:time_interval).with('1m').and_return({ param: '1m' })
        checker = double('FlaggedCommenters', check_list_for: true)
        expect(FlaggedCommenters).to receive(:new).with('1m', 1.day).and_return(checker)
        expect(helper).to receive(:render).with(
          partial: 'users/flag_warning',
          locals: { showing_user: showing_user, interval: { param: '1m' } }
        ).and_return('FLAG')
        result = helper.possible_flag_warning(showing_user, user)
        expect(result).to eq('FLAG')
      end

      it 'returns nil when flagged commenters do not include the user' do
        allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
        allow(helper).to receive(:time_interval).with('1m').and_return({ param: '1m' })
        checker = double('FlaggedCommenters', check_list_for: false)
        expect(FlaggedCommenters).to receive(:new).with('1m', 1.day).and_return(checker)
        expect(helper.possible_flag_warning(showing_user, user)).to be_nil
      end
    end
  end

  describe '#tag (overridden)' do
    it 'delegates to ActionView tag helper and supports all arguments' do
      open_tag = helper.tag('a', { href: '/x' })
      expect(open_tag).to include('<a href="/x"')
      expect(open_tag).to_not include('</a>')

      closed_tag = helper.tag('img', { src: '/x.png', alt: 'x' }, false, true)
      expect(closed_tag).to include('src="/x.png"')
      expect(closed_tag).to include('alt="x"')
      expect(closed_tag).to match(%r{<img[^>]+/?>})
    end
  end

  describe '#tag_link' do
    let(:tag_obj) { double('Tag', tag: 'ruby', description: 'Ruby tag', css_class: 'tag-ruby') }

    it 'renders link with css class and title, and marks filtered when applicable' do
      allow(helper).to receive(:filtered_tags).and_return([tag_obj])
      allow(helper).to receive(:tag_path).with(tag_obj).and_return('/t/ruby')
      html = helper.tag_link(tag_obj)
      expect(html).to include('href="/t/ruby"')
      expect(html).to include('>ruby<')
      expect(html).to include('class="tag-ruby filtered"')
      expect(html).to include('title="Ruby tag"')
    end

    it 'omits filtered class when tag is not filtered' do
      allow(helper).to receive(:filtered_tags).and_return([])
      allow(helper).to receive(:tag_path).with(tag_obj).and_return('/t/ruby')
      html = helper.tag_link(tag_obj)
      expect(html).to include('class="tag-ruby"')
      expect(html).to_not include('filtered')
    end
  end

  describe '#how_long_ago_label and #how_long_ago_link' do
    let(:time) { Time.zone.at(1_700_000_000) } # fixed

    it 'renders a time element with title, datetime and data-at-unix' do
      allow(helper).to receive(:how_long_ago).with(time).and_return('a while ago')
      html = helper.how_long_ago_label(time)
      expect(html).to include('<time')
      expect(html).to include('>a while ago<')
      formatted = time.strftime('%F %T')
      expect(html).to include(%(title="#{formatted}"))
      expect(html).to include(%(datetime="#{formatted}"))
      expect(html).to include(%(data-at-unix="#{time.to_i}"))
    end

    it 'wraps the time label in a link' do
      allow(helper).to receive(:how_long_ago_label).with(time).and_return('<time>ago</time>'.html_safe)
      html = helper.how_long_ago_link('/x', time)
      expect(html).to include('<a href="/x"><time>ago</time></a>')
    end
  end
end
