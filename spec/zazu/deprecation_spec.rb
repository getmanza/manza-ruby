# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe Zazu do
  let(:root) { File.expand_path("../..", __dir__) }

  it "warns on require \"zazu\" that the gem moved to manza" do
    _out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.join(root, "lib"), "-e", 'require "zazu"')

    expect(status).to be_success
    expect(err).to include("zazu-ruby is deprecated").and include('gem "manza"')
  end

  it "points to manza in the post-install message" do
    spec = Gem::Specification.load(File.join(root, "zazu-ruby.gemspec"))

    expect(spec.post_install_message).to include("deprecated").and include('gem "manza"')
  end
end
