require "rails_helper"

module IntervalHelper
  PLACEHOLDER = {param: "1w", dur: 1, intv: "Week", human: "week", placeholder: true}
  TIME_INTERVALS = {"h" => "Hour",
                    "d" => "Day",
                    "w" => "Week",
                    "m" => "Month",
                    "y" => "Year"}.freeze

  def time_interval(param)
    if (m = param.to_s.match(/\A(\d+)([#{TIME_INTERVALS.keys.join}])\z/))
      dur = m[1].to_i
      return PLACEHOLDER unless dur > 0
      return PLACEHOLDER unless TIME_INTERVALS.include? m[2]
      intv = TIME_INTERVALS[m[2]]
      {
        param: "#{dur}#{m[2]}",
        dur: dur,
        intv: intv,
        human: "#{dur unless dur == 1} #{intv}".downcase.pluralize(dur).chomp,
        placeholder: false
      }
    else
      PLACEHOLDER
    end
  end
end

describe IntervalHelper do
  describe "#time_interval" do
    let(:placeholder) { IntervalHelper::PLACEHOLDER }

    it "replaces empty input with placeholder" do
      expect(helper.time_interval("")).to eq(placeholder)
      expect(helper.time_interval(nil)).to eq(placeholder)
    end

    it "replaces invalid input with placeholder" do
      expect(helper.time_interval("0h")).to eq(placeholder)
      expect(helper.time_interval("1'h")).to eq(placeholder)
      expect(helper.time_interval("1h'")).to eq(placeholder)
      expect(helper.time_interval("-1w")).to eq(placeholder)
      expect(helper.time_interval("2")).to eq(placeholder)
      expect(helper.time_interval("m")).to eq(placeholder)
    end
  end
end