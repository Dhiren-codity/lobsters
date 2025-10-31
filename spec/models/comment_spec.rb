require 'rails_helper'

RSpec.describe Comment do
  describe ".regenerate_markdown" do
    it "regenerates markdown for all comments" do
      comment = create(:comment, markeddown_comment: "old markdown")
      allow(Comment).to receive(:all).and_return([comment])
      allow(comment).to receive(:generated_markeddown_comment).and_return("new markdown")

      Comment.regenerate_markdown

      expect(comment.markeddown_comment).to eq("new markdown")
    end
  end

  describe "#as_json" do
    it "returns a hash representation of the comment" do
      user = create(:user, username: "testuser")
      comment = create(:comment, user: user, short_id: "abc123", comment: "Test comment")
      json = comment.as_json

      expect(json[:short_id]).to eq("abc123")
      expect(json[:commenting_user]).to eq("testuser")
      expect(json[:comment]).to eq("Test comment")
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
      confidence = comment.calculated_confidence

      expect(confidence).to be_between(0, 1)
    end
  end

  describe "#breaks_speed_limit?" do
    it "returns false for top-level comments" do
      comment = build(:comment, parent_comment_id: nil)
      expect(comment.breaks_speed_limit?).to be false
    end

    it "returns true if speed limit is broken" do
      parent = create(:comment, created_at: 1.minute.ago)
      comment = build(:comment, parent_comment: parent, created_at: Time.current)
      allow(Comment).to receive(:where).and_return([parent])

      expect(comment.breaks_speed_limit?).to be true
    end
  end

  describe "#current_flagged?" do
    it "returns true if current vote is flagged" do
      comment = build(:comment, current_vote: { vote: -1 })
      expect(comment.current_flagged?).to be true
    end

    it "returns false if current vote is not flagged" do
      comment = build(:comment, current_vote: { vote: 1 })
      expect(comment.current_flagged?).to be false
    end
  end

  describe "#current_upvoted?" do
    it "returns true if current vote is upvoted" do
      comment = build(:comment, current_vote: { vote: 1 })
      expect(comment.current_upvoted?).to be true
    end

    it "returns false if current vote is not upvoted" do
      comment = build(:comment, current_vote: { vote: -1 })
      expect(comment.current_upvoted?).to be false
    end
  end

  describe "#delete_for_user" do
    it "deletes the comment for a moderator" do
      mod = create(:user, :moderator)
      comment = create(:comment)
      comment.delete_for_user(mod, "Inappropriate content")

      expect(comment.is_deleted).to be true
      expect(comment.is_moderated).to be true
    end
  end

  describe "#depth_permits_reply?" do
    it "returns true if depth allows reply" do
      comment = build(:comment, depth: Comment::MAX_DEPTH - 1)
      expect(comment.depth_permits_reply?).to be true
    end

    it "returns false if depth does not allow reply" do
      comment = build(:comment, depth: Comment::MAX_DEPTH)
      expect(comment.depth_permits_reply?).to be false
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
    it "returns moderator removal text if moderated" do
      mod = create(:user, :moderator)
      comment = create(:comment, is_moderated: true, moderation: create(:moderation, moderator: mod))
      expect(comment.gone_text).to include("Comment removed by moderator")
    end

    it "returns author removal text if not moderated" do
      comment = create(:comment, is_deleted: true)
      expect(comment.gone_text).to include("Comment removed by author")
    end
  end
end