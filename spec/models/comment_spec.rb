require 'rails_helper'

RSpec.describe Comment do
  describe ".regenerate_markdown" do
    it "updates all comments with generated markdown" do
      comment = create(:comment, markeddown_comment: "old markdown")
      allow(comment).to receive(:generated_markeddown_comment).and_return("new markdown")
      Comment.regenerate_markdown
      expect(comment.reload.markeddown_comment).to eq("new markdown")
    end
  end

  describe "#as_json" do
    it "returns a hash representation of the comment" do
      comment = create(:comment)
      json = comment.as_json
      expect(json[:short_id]).to eq(comment.short_id)
      expect(json[:created_at]).to eq(comment.created_at)
      expect(json[:commenting_user]).to eq(comment.user.username)
    end
  end

  describe "#assign_initial_attributes" do
    it "assigns initial attributes on create" do
      comment = build(:comment, short_id: nil, score: nil, confidence: nil, last_edited_at: nil)
      comment.assign_initial_attributes
      expect(comment.short_id).not_to be_nil
      expect(comment.score).to eq(1)
      expect(comment.confidence).not_to be_nil
      expect(comment.last_edited_at).not_to be_nil
    end
  end

  describe "#calculated_confidence" do
    it "calculates confidence for a comment" do
      comment = build(:comment, score: 10, flags: 2)
      expect(comment.calculated_confidence).to be_between(0, 1)
    end
  end

  describe "#breaks_speed_limit?" do
    it "returns false for top-level comments" do
      comment = build(:comment, parent_comment: nil)
      expect(comment.breaks_speed_limit?).to be false
    end
  end

  describe "#current_flagged?" do
    it "returns true if current vote is flagged" do
      comment = build(:comment, current_vote: { vote: -1 })
      expect(comment.current_flagged?).to be true
    end
  end

  describe "#current_upvoted?" do
    it "returns true if current vote is upvoted" do
      comment = build(:comment, current_vote: { vote: 1 })
      expect(comment.current_upvoted?).to be true
    end
  end

  describe "#delete_for_user" do
    it "marks the comment as deleted for a user" do
      user = create(:user, :moderator)
      comment = create(:comment)
      comment.delete_for_user(user)
      expect(comment.is_deleted).to be true
    end
  end

  describe "#depth_permits_reply?" do
    it "returns true if depth allows reply" do
      comment = build(:comment, depth: Comment::MAX_DEPTH - 1)
      expect(comment.depth_permits_reply?).to be true
    end
  end

  describe "#generated_markeddown_comment" do
    it "generates markdown for the comment" do
      comment = build(:comment, comment: "This is **bold**")
      expect(comment.generated_markeddown_comment).to include("<strong>bold</strong>")
    end
  end

  describe "#update_score_and_recalculate!" do
    it "updates score and recalculates confidence" do
      comment = create(:comment, score: 0, flags: 0)
      expect {
        comment.update_score_and_recalculate!(1, 0)
      }.to change { comment.reload.score }.by(1)
    end
  end

  describe "#gone_text" do
    it "returns text for moderated comment" do
      moderator = create(:user, :moderator)
      moderation = create(:moderation, moderator: moderator)
      comment = create(:comment, is_moderated: true, moderation: moderation)
      expect(comment.gone_text).to include("Comment removed by moderator")
    end
  end
end