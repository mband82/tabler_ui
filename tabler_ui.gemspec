# frozen_string_literal: true

require_relative "lib/tabler_ui/version"

Gem::Specification.new do |spec|
  spec.name = "tabler_ui"
  spec.version = TablerUi::VERSION
  spec.authors = ["webbastelbude"]
  spec.email = ["h.quick@webbastelbude.de"]

  spec.summary = "Tabler UI components for Rails applications"
  spec.description = "A collection of reusable UI components based on Tabler.io framework for Rails applications. Includes Navbar, Page Headers, Buttons, Cards, Tables and more."
  spec.homepage = "https://github.com/webbastelbude/tabler_ui"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/webbastelbude/tabler_ui"
  spec.metadata["changelog_uri"] = "https://github.com/webbastelbude/tabler_ui/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "stimulus-rails"
  spec.add_dependency "ostruct"
  # app/assets/stylesheets/tabler_ui.css is a Sprockets directive manifest
  # (`*= require ...`), and the engine's asset initializer appends to
  # config.assets.paths. Propshaft processes neither, so a host app on Rails 8's
  # default pipeline is served the directive comments instead of any CSS. The
  # gem has always required Sprockets; this says so.
  spec.add_dependency "sprockets-rails", "~> 3.5"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "combustion"
  spec.add_development_dependency "nokogiri"
  spec.add_development_dependency "sqlite3"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
