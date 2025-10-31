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
      expect(json).to include(:short_id, :created_at, :last_edited_at, :is_deleted, :is_moderated, :score, :flags)
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
    it "calculates confidence for non-deleted, non-moderated comments" do
      comment = build(:comment, score: 10, flags: 2, is_deleted: false, is_moderated: false)
      expect(comment.calculated_confidence).to be_between(0, 1)
    end

    it "returns 0 for deleted comments" do
      comment = build(:comment, is_deleted: true)
      expect(comment.calculated_confidence).to eq(0)
    end

    it "returns 0 for moderated comments" do
      comment = build(:comment, is_moderated: true)
      expect(comment.calculated_confidence).to eq(0)
    end
  end

  describe "#breaks_speed_limit?" do
    it "returns false for top-level comments" do
      comment = build(:comment, parent_comment_id: nil)
      expect(comment.breaks_speed_limit?).to be false
    end

    it "returns true if speed limit is exceeded" do
      parent = create(:comment)
      comment = build(:comment, parent_comment: parent, created_at: 1.minute.ago)
      allow(Comment).to receive(:where).and_return(Comment.where(id: comment.id))
      expect(comment.breaks_speed_limit?).to be true
    end
  end

  describe "#delete_for_user" do
    it "marks comment as deleted and moderated for moderators" do
      mod = create(:user, :moderator)
      comment = create(:comment)
      comment.delete_for_user(mod, "reason")
      expect(comment.is_deleted).to be true
      expect(comment.is_moderated).to be true
    end

    it "does not mark as moderated if user is not a moderator" do
      user = create(:user)
      comment = create(:comment)
      comment.delete_for_user(user)
      expect(comment.is_moderated).to be false
    end
  end

  describe "#depth_permits_reply?" do
    it "returns true if depth is less than MAX_DEPTH" do
      comment = build(:comment, depth: Comment::MAX_DEPTH - 1)
      expect(comment.depth_permits_reply?).to be true
    end

    it "returns false if depth is equal to MAX_DEPTH" do
      comment = build(:comment, depth: Comment::MAX_DEPTH)
      expect(comment.depth_permits_reply?).to be false
    end
  end

  describe "#generated_markeddown_comment" do
    it "generates markdown from comment text" do
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
      moderation = create(:moderation, moderator: mod)
      comment = create(:comment, is_moderated: true, moderation: moderation)
      expect(comment.gone_text).to include("Comment removed by moderator")
    end

    it "returns author removal text if not moderated" do
      comment = create(:comment, is_deleted: true, is_moderated: false)
      expect(comment.gone_text).to include("Comment removed by author")
    end
  end
end