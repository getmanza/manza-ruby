# frozen_string_literal: true

require_relative "lib/zazu/version"

Gem::Specification.new do |spec|
  spec.name = "zazu-ruby"
  spec.version = Zazu::VERSION
  spec.authors = ["Zazu"]
  spec.email = ["hello@get-zazu.com"]

  spec.summary = "Ruby SDK for the Zazu API"
  spec.description = "Faraday-based Ruby SDK for the Zazu payment platform API. " \
                     "Wraps accounts, customers, invoices, payment links, transactions, and webhook " \
                     "endpoints. HTTPX adapter for HTTP/2 + persistent connections."
  spec.homepage = "https://github.com/getzazu/zazu-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["source_code_uri"] = "https://github.com/getzazu/zazu-ruby/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/getzazu/zazu-ruby/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/getzazu/zazu-ruby/issues"
  spec.metadata["documentation_uri"] = "https://github.com/getzazu/zazu-ruby#readme"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.post_install_message = <<~MSG
    zazu-ruby is deprecated and gets no further updates. It is now published
    as gem "manza" (require "manza", Manza::Client). Migration guide:
    https://github.com/getmanza/manza-ruby/blob/main/CHANGELOG.md
  MSG

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "httpx", "~> 1.0"
end
