# -*- ruby encoding: utf-8 -*-

require 'poole'
require 'main'
require 'set'

module Poole::Main
  class Config
    unless defined? Parser
      begin
        require 'psych'
        Parser = ::Psych
      rescue LoadError
        require 'yaml'
        Parser = ::YAML
      end
    end

    def defaults
      {
        "build_dir"         =>  "build",
        "date_format"       => "%Y-%m-%d %H:%M:%S",
        "download_images"   => false,
        "item_field_filter" => {
          "status" => "draft",
        },
        "item_type_filter"  => [ "attachment", "nav_menu_item" ],
        "target_format"     => "markdown",
        "taxonomies"        => {
          "filter"        => [],
          "name_mapping"  => {
            "category"  => "categories",
            "post_tag"  => "tags",
          },
          "entry_filter"  => {
            "category" => "Uncategorized"
          },
        },
        "wp_exports"        => "wordpress-xml",
      }
    end

    def initialize(config)
      case config
      when Hash
        nil
      when String
        config = Parser.load(config)
      else
        raise ArgumentError, "Invalid config value."
      end

      @config = defaults.merge(config)

      tf = @config['taxonomies']['filter']
      case tf
      when Hash
        warn "Creating the taxonomies filter from the provided hash keys."
        @config['taxonomies']['filter'] = Set.new(tf.keys)
      when Array, Set
        @config['taxonomies']['filter'] = Set.new(tf)
      else
        raise ArgumentError, "The taxonomies filter must be a Hash, Set, or Array."
      end

      @config['item_type_filter'] = Set.new(@config['item_type_filter'])
      @config['wp_exports'] = File.expand_path(@config['wp_exports'])
    end

    def respond_to?(sym)
      if @config.has_key? sym.to_s
        true
      else
        super
      end
    end

    def method_missing(sym, *args, &block)
      if @config.has_key? sym.to_s
        @config[sym.to_s]
      else
        super
      end
    end

    def [](name)
      @config[name]
    end

    attr_reader :config
  end
end

Main do
  program 'poole'

  # a short description of program functionality, auto-set and used in usage
  # synopsis "poole [config-file]"

  # long description of program functionality, used in usage iff set
  description "Convert a WordPress export file to Jekyll."

  # used in usage iff set
  author 'austin@rubyforge.org'

  # used in usage
  version Poole::VERSION

  # the logger should be a Logger object, something 'write'-able, or a string
  # which will be used to open the logger.  the logger_level specifies the
  # initalize verbosity setting, the default is Logger::INFO
  # logger(( program + '.log' ))
  # logger_level Logger::DEBUG

  # the usage object is rather complex.  by default it's an object which can
  # be built up in sections using the 
  #
  #   usage["BUGS"] = "something about bugs'
  #
  # syntax to append sections onto the already pre-built usage message which
  # contains program, synopsis, parameter descriptions and the like

  argument 'config-file' do
    validate do |file|
      if File.exists? file
        true
      else
        ENV['main.error.missing.config-file'] = file
      end
    end

    synopsis 'config-file (optional, defaults to config.yaml)'
    description <<-EOS
The name of the config file to use. If not provided, defaults to config.yaml
in the current directory.
    EOS

    default 'config.yaml'

    error do
      file = ENV.delete('main.error.missing.config-file')
      $stderr.puts "error: cannot open config file: #{file}"
    end
  end

  option 'quiet' do
    description "Suppresses the normal output."
  end

  option 'pandoc' do
    description 'The name of the pandoc file.'
  end

  def set_option(name, default)
    if params[name].given?
      @yaml_config[name] = params[name].value
    else
      @yaml_config[name] = default[:default] unless @yaml_config.has_key? name
    end
  end

  attr_reader :yaml_config

  def run
    config_file = params['config-file'].value
    @yaml_config = Poole::Main::Config::Parser.load_file(config_file)
    set_option('quiet', :default => false)
    set_option('pandoc', :default => 'pandoc')
    yaml_config['stdout'] = stdout
    yaml_config['stderr'] = stderr

    config = Poole::Main::Config.new(yaml_config)
    Poole.new(config).run

#   # you can set the exit_status at anytime.  this status is used when
#   # exiting the program.  exceptions cause this to be ext_failure if, and
#   # only if, the current value was exit_success.  in otherwords an
#   # un-caught exception always results in a failing exit_status
#   #
#   exit_status exit_failure
#   #
#   # a few shortcuts both set the exit_status and exit the program.
#   #
#   exit_success!
#   exit_failure!
#   exit_warn!
  end
end

# vim: ft=ruby
