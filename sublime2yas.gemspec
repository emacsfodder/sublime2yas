# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sublime2yas/version'

Gem::Specification.new do |spec|
  spec.name          = "sublime2yas"
  spec.version       = Sublime2yas::VERSION
  spec.authors       = ["Jasonm23"]
  spec.email         = ["jasonm23@gmail.com"]
  spec.description   = %q{SublimeTextSnippets to YaSnippet}
  spec.summary       = %q{SublimeText Snippet to YaSnippet/Emacs conversion}
  spec.homepage      = %q{https://github.com/jasonm23/sublime2yas}
  spec.license       = %q{MIT}

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_runtime_dependency "nokogiri"
  spec.add_runtime_dependency "trollop"
end
