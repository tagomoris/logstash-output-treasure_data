Gem::Specification.new do |s|
  s.name = 'logstash-output-treasure_data'
  s.version     = "1.0.0.pre1"
  s.licenses    = ["Apache License (2.0)"]
  s.summary     = "Logstash plugin to store data into Treasure Data service."
  s.description = "This gem is a logstash plugin to store data from logstash to Treasure Data service. This gem is not a stand-alone program."
  s.authors     = ["Satoshi Tagomori"]
  s.email       = "tagomoris@gmail.com"
  s.homepage    = "https://github.com/tagomoris/logstash-output-treasure_data"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']
  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "output" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency "logstash-codec-plain"
  s.add_runtime_dependency "msgpack", "~> 1.0"
  s.add_runtime_dependency "td-client", "~> 1.0"
  s.add_development_dependency "logstash-devutils"
end
