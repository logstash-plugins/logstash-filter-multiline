Gem::Specification.new do |s|

  s.name            = 'logstash-filter-multiline'
  s.version         = '0.1.0'
  s.licenses        = ['Apache License (2.0)']
  s.summary         = "This filter will collapse multiline messages from a single source into one Logstash event."
  s.description     = "This filter will collapse multiline messages from a single source into one Logstash event."
  s.authors         = ["Elasticsearch"]
  s.email           = 'richard.pijnenburg@elasticsearch.com'
  s.homepage        = "http://logstash.net/"
  s.require_paths = ["lib"]

  # Files
  s.files = `git ls-files`.split($\)

  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "group" => "filter" }

  # Gem dependencies
  s.add_runtime_dependency 'logstash', '>= 1.4.0', '< 2.0.0'
  s.add_runtime_dependency 'logstash-patterns-core'
  s.add_runtime_dependency 'jls-grok', '~> 0.11.0'

end

