# frozen_string_literal: true

require_relative "lib/haystack/version"

Gem::Specification.new do |spec|
  spec.name          = "haystack-core"
  spec.version       = Haystack::VERSION
  spec.authors       = ["Haystack Team"]
  spec.description   = spec.summary = "A gem that provides the core functionalities for the Haystack error and performance monitoring system"
  spec.email         = "accounts@haystack.io"
  spec.license       = 'MIT'
  spec.homepage      = "https://github.com/pedrotyag/haystack"

  spec.platform = Gem::Platform::RUBY
  spec.required_ruby_version = '>= 2.4'
  spec.extra_rdoc_files = ["README.md", "LICENSE.txt"]
  spec.files = `git ls-files | grep -Ev '^(spec|benchmarks|examples|\.rubocop\.yml)'`.split("\n")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Dependências
  spec.add_dependency "haystack", Haystack::VERSION
  spec.add_dependency "concurrent-ruby"
end
