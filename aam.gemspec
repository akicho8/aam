# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'aam/version'

Gem::Specification.new do |spec|
  spec.name          = "aam"
  spec.version       = Aam::VERSION
  spec.authors       = ["akicho8"]
  spec.email         = ["akicho8@gmail.com"]
  spec.description   = %q{Index reference to Japanese correspondence relation annotate_models}
  spec.summary       = %q{Advanced Annotate Models}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "test-unit"
  spec.add_development_dependency "sqlite3"

  spec.add_dependency "rails"
  spec.add_dependency "activerecord"
  spec.add_dependency "activesupport"
  spec.add_dependency "table_format"
end
