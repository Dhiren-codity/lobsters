require "rails_helper"

describe User do
  it "has a valid username" do
    expect { create(:user, username: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:user, username: "") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:user, username: "*") }.to raise_error(ActiveRecord::RecordInvalid)
    # security controls, usernames are used in queries and filenames
    expect { create(:user, username: "a'b") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:user, username: "a\"b") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:user, username: "../b") }.to raise_error(ActiveRecord::RecordInvalid)

    create(:user, username: "newbie")
    expect { create(:user, username: "newbie") }.to raise_error(ActiveRecord::RecordInvalid)

    create(:user, username: "underscores_and-dashes")
    invalid_username_variants = ["underscores-and_dashes", "underscores_and_dashes", "underscores-and-dashes"]

    invalid_username_variants.each do |invalid_username|
      subject = build(:user, username: invalid_username)
      expect(subject).to_not be_valid
      expect(subject.errors[:username]).to eq(["is already in use (perhaps swapping _ and -)"])
    end

    create(:user, username: "case_insensitive")
    expect { create(:user, username: "CASE_INSENSITIVE") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:user, username: "case_Insensitive") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:user, username: "case-insensITive") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  describe "#initiate_password_reset_for_ip" do
    it "sets a token and sends a mail" do
      user = create(:user)
      mail_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, "1.2.3.4").and_return(mail_double)
      user.initiate_password_reset_for_ip("1.2.3.4")
      expect(user.reload.password_reset_token).to match(/\A\d{10}-[a-zA-Z0-9]{30}\z/)
    end
  end
end