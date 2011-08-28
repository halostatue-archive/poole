# -*- ruby encoding: utf-8 -*-

require 'rubygems'
require 'rspec'
require 'hoe'

Hoe.plugin :doofus
Hoe.plugin :gemspec
Hoe.plugin :git

Hoe.spec 'diff-lcs' do
  self.rubyforge_name = 'ruwiki'

  developer('Austin Ziegler', 'austin@rubyforge.org')

  self.remote_rdoc_dir = 'diff-lcs/rdoc'
  self.rsync_args << ' --exclude=statsvn/'

  self.history_file = 'History.rdoc'
  self.readme_file = 'README.rdoc'
  self.extra_rdoc_files = FileList["*.rdoc"].to_a

  self.extra_deps << ['nokogiri', '~> 1.5.0']
  self.extra_deps << ['main', '~> 4.7.3']
  self.extra_dev_deps << ['rspec', '~> 2.0']
  self.extra_dev_deps << ['hoe-doofus', '~> 1.0']
  self.extra_dev_deps << ['hoe-gemspec', '~> 1.0']
  self.extra_dev_deps << ['hoe-git', '~> 1.0']
  self.extra_dev_deps << ['hoe-seattlerb', '~> 1.0']

  self.spec_extras[:requirements] = [ "pandoc, ~> 1.8.2" ]
end

# vim: syntax=ruby
