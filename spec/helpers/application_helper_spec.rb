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
    it 'builds an avatar image tag with responsive srcset and attributes' do
      user = double('User', username: 'alice')
      allow(user).to receive(:avatar_path) do |s|
        "/avatars/alice/#{s}.png"
      end

      html = helper.avatar_img(user, 32)
      expect(html).to include('src="/avatars/alice/32.png"')
      expect(html).to include('srcset="/avatars/alice/32.png 1x, /avatars/alice/64.png 2x"')
      expect(html).to include('class="avatar"')
      expect(html).to include('alt="alice avatar"')
      expect(html).to include('loading="lazy"')
      expect(html).to include('decoding="async"')
      expect(html).to include('width="32"')
      expect(html).to include('height="32"')
    end
  end

  describe '#errors_for' do
    class SpecDummyModel
      include ActiveModel::Model
      include ActiveModel::Validations
      attr_accessor :title, :comments
    end

    it 'returns empty string when there are no errors' do
      obj = SpecDummyModel.new
      expect(helper.errors_for(obj)).to eq('')
    end

    it 'renders a formatted error list with special-case substitution' do
      obj = SpecDummyModel.new
      obj.errors.add(:comments, 'is invalid')
      obj.errors.add(:title, "can't be blank")

      html = helper.errors_for(obj)
      expect(html).to include('class="flash-error"')
      expect(html).to include('2 errors prohibited this specdummymodel from being saved')
      expect(html).to include('<p>There were the problems with the following fields:</p>')
      expect(html).to include('<li>Comment is missing</li>')
      expect(html).to include("<li>Title can't be blank</li>")
    end
  end

  describe '#filtered_tags' do
    before do
      helper.instance_variable_set(:@_filtered_tags, nil)
    end

    it "returns user's filtered tags when @user is present" do
      tag = create(:tag, tag: 'foo')
      user = double('User')
      allow(user).to receive(:tag_filter_tags).and_return([tag])
      helper.instance_variable_set(:@user, user)
      expect(helper.filtered_tags).to eq([tag])
    end

    it 'returns tags based on cookie when @user is not present' do
      t1 = create(:tag, tag: 'foo')
      t2 = create(:tag, tag: 'bar')
      allow(helper).to receive(:cookies).and_return({ ApplicationController::TAG_FILTER_COOKIE => 'foo,bar' })
      helper.instance_variable_set(:@user, nil)
      tags = helper.filtered_tags
      expect(tags.map(&:id)).to match_array([t1.id, t2.id])
    end

    it 'returns empty when no cookie is set and no user' do
      allow(helper).to receive(:cookies).and_return({})
      helper.instance_variable_set(:@user, nil)
      expect(helper.filtered_tags).to be_empty
    end
  end

  describe '#inline_avatar_for' do
    let(:user) { create(:user) }

    it 'returns a link with avatar when viewer is nil' do
      allow(helper).to receive(:avatar_img).and_return('<img class="avatar">'.html_safe)
      html = helper.inline_avatar_for(nil, user)
      expect(html).to include(%(href="#{user_path(user)}"))
      expect(html).to include('<img')
    end

    it 'returns a link with avatar when viewer shows avatars' do
      allow(helper).to receive(:avatar_img).and_return('<img class="avatar">'.html_safe)
      viewer = double('User', show_avatars?: true)
      html = helper.inline_avatar_for(viewer, user)
      expect(html).to include(%(href="#{user_path(user)}"))
    end

    it 'returns nil when viewer hides avatars' do
      viewer = double('User', show_avatars?: false)
      expect(helper.inline_avatar_for(viewer, user)).to be_nil
    end
  end

  describe '#link_to_different_page' do
    it 'marks link as current when normalized path matches the current request path' do
      allow(helper).to receive(:request).and_return(double(path: '/stories/page/2'))
      html = helper.link_to_different_page('Stories', '/stories/page/10', class: 'btn')
      expect(html).to include('class="btn current_page"').or include('class="current_page btn"')
      expect(html).to include('href="/stories"')
    end

    it 'does not mark as current when paths differ' do
      allow(helper).to receive(:request).and_return(double(path: '/stories/other'))
      html = helper.link_to_different_page('Stories', '/stories', class: 'btn')
      expect(html).to include('href="/stories"')
      expect(html).not_to include('current_page')
    end
  end

  describe '#link_post' do
    it 'renders the partial with provided options' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: { button_label: 'Do it', link: '/go', class_name: 'primary', confirm: 'Sure?' }
      ).and_return('OK')

      expect(helper.link_post('Do it', '/go', class_name: 'primary', confirm: 'Sure?')).to eq('OK')
    end

    it 'renders with default nil options when not provided' do
      expect(helper).to receive(:render).with(
        partial: 'helpers/link_post',
        locals: { button_label: 'Go', link: '/go', class_name: nil, confirm: nil }
      ).and_return('OK')

      expect(helper.link_post('Go', '/go')).to eq('OK')
    end
  end

  describe '#possible_flag_warning' do
    let(:showing_user) { create(:user) }
    let(:user) { create(:user) }

    it 'renders dev flag warning in non-production environments' do
      expect(helper).to receive(:render).with(partial: 'users/dev_flag_warning').and_return('DEV')
      expect(helper.possible_flag_warning(showing_user, user)).to eq('DEV')
    end

    context 'in production' do
      before do
        allow(Rails).to receive_message_chain(:env, :production?).and_return(true)
      end

      it 'returns nil when not self or moderator' do
        allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(false)
        expect(helper.possible_flag_warning(showing_user, user)).to be_nil
      end

      it 'renders flag warning when user is in flagged commenters' do
        allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
        allow(helper).to receive(:time_interval).with('1m').and_return({ param: '1m' })
        flagged = instance_double('FlaggedCommenters')
        allow(FlaggedCommenters).to receive(:new).with('1m', 1.day).and_return(flagged)
        allow(flagged).to receive(:check_list_for).with(showing_user).and_return(true)
        expect(helper).to receive(:render).with(
          partial: 'users/flag_warning',
          locals: { showing_user: showing_user, interval: { param: '1m' } }
        ).and_return('WARN')
        expect(helper.possible_flag_warning(showing_user, user)).to eq('WARN')
      end

      it 'returns nil when user is not in flagged commenters' do
        allow(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
        allow(helper).to receive(:time_interval).with('1m').and_return({ param: '1m' })
        flagged = instance_double('FlaggedCommenters')
        allow(FlaggedCommenters).to receive(:new).with('1m', 1.day).and_return(flagged)
        allow(flagged).to receive(:check_list_for).with(showing_user).and_return(false)
        expect(helper.possible_flag_warning(showing_user, user)).to be_nil
      end
    end
  end

  describe '#tag_link' do
    before do
      helper.instance_variable_set(:@_filtered_tags, nil)
    end

    it 'renders a link to the tag with title and css class' do
      tag = create(:tag, tag: 'ruby', description: 'Lang')
      allow(tag).to receive(:css_class).and_return('tag-ruby')
      allow(helper).to receive(:cookies).and_return({ ApplicationController::TAG_FILTER_COOKIE => '' })
      html = helper.tag_link(tag)
      expect(html).to include(%(href="#{tag_path(tag)}"))
      expect(html).to include(">#{tag.tag}<")
      expect(html).to include('class="tag-ruby"')
      expect(html).to include('title="Lang"')
    end

    it 'adds filtered class when tag is filtered (cookie-based)' do
      tag = create(:tag, tag: 'ruby', description: 'Lang')
      allow(tag).to receive(:css_class).and_return('tag-ruby')
      allow(helper).to receive(:cookies).and_return({ ApplicationController::TAG_FILTER_COOKIE => 'ruby' })
      helper.instance_variable_set(:@user, nil)
      html = helper.tag_link(tag)
      expect(html).to include('filtered')
    end
  end

  describe '#how_long_ago_label' do
    it 'renders a time tag with proper attributes' do
      time = Time.zone.parse('2024-01-01 12:34:56')
      allow(helper).to receive(:how_long_ago).with(time).and_return('3 minutes ago')
      html = helper.how_long_ago_label(time)
      at = time.strftime('%F %T')
      expect(html).to include('<time')
      expect(html).to include('>3 minutes ago<')
      expect(html).to include(%(title="#{at}"))
      expect(html).to include(%(datetime="#{at}"))
      expect(html).to include(%(data-at-unix="#{time.to_i}"))
    end
  end

  describe '#how_long_ago_link' do
    it 'wraps the label in an anchor to the URL' do
      time = Time.zone.now
      allow(helper).to receive(:how_long_ago_label).with(time).and_return('<time id="ago">just now</time>'.html_safe)
      html = helper.how_long_ago_link('/posts/1', time)
      expect(html).to include(%(href="/posts/1"))
      expect(html).to include('<time id="ago">just now</time>')
    end
  end
end
