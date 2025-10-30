require "rails_helper"

RSpec.describe NotifyCommentJob, type: :job do
  describe "comment notifications" do
    it "sends reply notification" do
      recipient = FactoryBot.build(:user)
      recipient.settings["email_notifications"] = true
      recipient.settings["email_replies"] = true
      recipient.save!

      sender = FactoryBot.create(:user)
      story = FactoryBot.create(:story)

      c = FactoryBot.build(:comment, story: story, user: recipient)
      c.save!

      c2 = FactoryBot.build(:comment, story: story, user: sender, parent_comment: c)
      c2.save!

      NotifyCommentJob.perform_now(c2)

      expect(sent_emails.size).to eq(1)
      expect(sent_emails[0].subject).to match(/Reply from #{sender.username}/)
      expect(recipient.notifications.count).to eq(1)
      expect(recipient.notifications.first.notifiable).to eq(c2)
    end

    it "doesn't email if the replied-to user is hiding the story" do
      story = FactoryBot.create(:story)

      recipient = FactoryBot.build(:user)
      recipient.settings["email_notifications"] = true
      recipient.settings["email_replies"] = true
      recipient.save!
      parent_comment = FactoryBot.create(:comment, story: story, user: recipient)

      HiddenStory.hide_story_for_user(story, recipient)
      reply = FactoryBot.create(:comment, story: story, parent_comment: parent_comment)

      NotifyCommentJob.perform_now(reply)

      expect(recipient.notifications.count).to eq(1)
      expect(sent_emails.size).to eq(0)
    end

    it "sends mention notification" do
      recipient = FactoryBot.build(:user)
      recipient.settings["email_notifications"] = true
      recipient.settings["email_mentions"] = true
      recipient.save!

      sender = FactoryBot.create(:user)
      c = FactoryBot.create(:comment, user: sender, comment: "@#{recipient.username}")

      NotifyCommentJob.perform_now(c)

      expect(sent_emails.size).to eq(1)
      expect(sent_emails[0].subject).to match(/Mention from #{sender.username}/)
      expect(recipient.notifications.count).to eq(1)
      expect(recipient.notifications.first.notifiable).to eq(c)
    end

    it "also sends mentions with ~username" do
      recipient = FactoryBot.build(:user)
      recipient.settings["email_notifications"] = true
      recipient.settings["email_mentions"] = true
      recipient.save!

      c = FactoryBot.build(:comment, comment: "~#{recipient.username}")
      c.save!

      NotifyCommentJob.perform_now(c)

      expect(sent_emails.size).to eq(1)
      expect(recipient.notifications.count).to eq(1)
      expect(recipient.notifications.first.notifiable).to eq(c)
    end

    it "doesn't email if the mentioned user is hiding the story" do
      story = FactoryBot.create(:story)

      mentioned = FactoryBot.build(:user)
      mentioned.settings["email_notifications"] = true
      mentioned.settings["email_mentions"] = true
      mentioned.save!

      HiddenStory.hide_story_for_user(story, mentioned)
      reply = FactoryBot.create(:comment, story: story, comment: "Hello @#{mentioned.username}")

      NotifyCommentJob.perform_now(reply)
      expect(mentioned.notifications.count).to eq(1)
      expect(sent_emails.size).to eq(0)
    end

    it "sends only reply notification on reply with mention" do
      recipient = FactoryBot.build(:user)
      recipient.settings["email_notifications"] = true
      recipient.settings["email_mentions"] = true
      recipient.settings["email_replies"] = true
      recipient.save!

      sender = FactoryBot.create(:user)
      story = FactoryBot.create(:story)
      c = FactoryBot.build(:comment, user: recipient, story: story)
      c.save!

      c2 = FactoryBot.build(:comment, user: sender, story: story, parent_comment: c,
        comment: "@#{recipient.username}")
      c2.save!

      NotifyCommentJob.perform_now(c2)

      expect(sent_emails.size).to eq(1)
      expect(sent_emails[0].subject).to match(/Reply from #{sender.username}/)
      expect(recipient.notifications.count).to eq(1)
      expect(recipient.notifications.first.notifiable).to eq(c2)
    end
  end
end