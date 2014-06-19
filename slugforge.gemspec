require File.expand_path('../lib/slugforge/version', __FILE__)

Gem::Specification.new do |s|
  s.name        = 'slugforge'
  s.version     = Slugforge::VERSION
  s.licenses    = ['MIT']
  s.authors     = ['Tapjoy, Inc.']
  s.email       = ['chris.gerber@tapjoy.com']
  s.homepage    = 'http://github.com/Tapjoy/slugforge'
  s.summary     = 'Tool for building slugs from git repos'
  s.description = <<-EOF
    Slugforge is a tool for building, managing, and deploying Procfile
    based applications. It was developed to automate the workflow used
    at Tapjoy, but has been generalized to be more widely applicable.
  EOF

  s.files             = %w(bin lib scripts templates).map { |path| Dir["#{path}/**/*"] }.flatten
  s.test_files        = Dir['spec/**/*'].to_a
  s.extra_rdoc_files  = %w(README.md)

  s.executables  = ['slugforge']
  s.bindir       = 'bin'
  s.require_paths << 'lib'

  s.add_runtime_dependency('fpm',                '~> 1.1')
  s.add_runtime_dependency('foreman',            '~> 0.63')
  s.add_runtime_dependency('thor',               '~> 0.18')
  s.add_runtime_dependency('fog',                '~> 1.22')
  s.add_runtime_dependency('unf',                '~> 0')     # for fog
  s.add_runtime_dependency('progress_bar',       '~> 1.0')
  s.add_runtime_dependency('activesupport',      '~> 4.0.0')
  s.add_runtime_dependency('json',               '= 1.7.7')  # for Ruby 2.1.0

  s.add_development_dependency('rspec'             , '~> 2')
  s.add_development_dependency('guard-rspec'       , '~> 4')
  s.add_development_dependency('pry'               , '~> 0')
  s.add_development_dependency('pry-rescue'        , '~> 1')
  s.add_development_dependency('pry-stack_explorer', '~> 0')
  s.add_development_dependency('fakefs'            , '~> 0')
end

