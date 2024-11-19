# typed: false

# named 00_zeitwerk because Rails loads these in alphabetical order and
# production.rb needs these classes loaded

# prevent zeitwerk from failing on prod boot because these patches don't match
# its expected filenames
Rails.autoloaders.main.ignore(Rails.root.join("extras/prohibit*rb"))
Rails.autoloaders.main.ignore(Rails.root.join("lib/monkey.rb"))
require Rails.root.join("lib/monkey.rb").to_s
