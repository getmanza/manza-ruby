# frozen_string_literal: true

require_relative "lib/manza/version"

Gem::Specification.new do |spec|
  spec.name = "manza"
  spec.version = Manza::VERSION
  spec.authors = ["Manza"]
  spec.email = ["hello@get-manza.com"]

  spec.summary = "Ruby SDK for the Manza API"
  spec.description = "Faraday-based Ruby SDK for the Manza payment platform API. " \
                     "Wraps accounts, customers, invoices, payment links, transactions, and webhook " \
                     "endpoints. HTTPX adapter for HTTP/2 + persistent connections."
  spec.homepage = "https://github.com/getmanza/manza-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["source_code_uri"] = "https://github.com/getmanza/manza-ruby/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/getmanza/manza-ruby/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/getmanza/manza-ruby/issues"
  spec.metadata["documentation_uri"] = "https://github.com/getmanza/manza-ruby#readme"
  spec.metadata["rubygems_mfa_required"] = "true"

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
