# frozen_string_literal: true

$stdout.sync = true

require "yaml"
require "singleton"
require "optparse"
require "erb"
require "fileutils"

module Faktory
  class CLI
  end
end

require "faktory"
require "faktory/util"

module Faktory
  class CLI
    include Util
    include Singleton unless $TESTING

    # Used for CLI testing
    attr_accessor :code
    attr_accessor :launcher
    attr_accessor :environment

    def initialize
      @code = nil
    end

    def parse(args = ARGV)
      @code = nil

      setup_options(args)
      initialize_logger
      validate!
    end

    def jruby?
      defined?(::JRUBY_VERSION)
    end

    # Code within this method is not tested because it alters
    # global process state irreversibly.  PRs which improve the
    # test coverage of Faktory::CLI are welcomed.
    def run
      Faktory::Client.worker!

      boot_system
      print_banner

      self_read, self_write = IO.pipe
      sigs = %w[INT TERM TTIN TSTP]

      sigs.each do |sig|
        trap sig do
          self_write.puts(sig)
        end
      rescue ArgumentError
        puts "Signal #{sig} not supported"
      end

      logger.info "Running in #{RUBY_DESCRIPTION}"
      logger.info Faktory::LICENSE

      # cache process identity
      Faktory.options[:identity] = identity

      # Touch middleware so it isn't lazy loaded by multiple threads, #3043
      Faktory.worker_middleware

      # Before this point, the process is initializing with just the main thread.
      # Starting here the process will now have multiple threads running.
      fire_event(:startup)

      logger.debug { "Client Middleware: #{Faktory.client_middleware.map(&:klass).join(", ")}" }
      logger.debug { "Worker Middleware: #{Faktory.worker_middleware.map(&:klass).join(", ")}" }

      logger.info "Starting processing, hit Ctrl-C to stop" if $stdout.tty?

      require "faktory/launcher"
      @launcher = Faktory::Launcher.new(options)

      begin
        launcher.run

        while self_read.wait_readable
          signal = self_read.gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        logger.info "Shutting down"
        launcher.stop
        # Explicitly exit so busy Processor threads can't block
        # process shutdown.
        logger.info "Bye!"
        exit(0)
      end
    end

    def self.banner
      %q{
                    ,,,,
            ,,,,    |  |
            |  |    |  |
            |  |    |  |
            |  |,,~~'  '~,          ___       _
       ,,~~''   ,~~,      '~,      / __)     | |      _
 ,,~~''   ,~~,  |  |        |    _| |__ _____| |  _ _| |_ ___   ____ _   _
 |  ,~~,  |  |  |  |        |   (_   __|____ | |_/ |_   _) _ \ / ___) | | |
 |  |  |  |  |  |  |        |     | |  / ___ |  _ (  | || |_| | |   | |_| |
 |  |__|  |__|  |__|        |     |_|  \_____|_| \_)  \__)___/|_|    \__  |
 |__________________________|                                       (____/

}
    end

    def handle_signal(sig)
      Faktory.logger.debug "Got #{sig} signal"
      case sig
      when "INT"
        raise Interrupt
      when "TERM"
        # Heroku sends TERM and then waits 30 seconds for process to exit.
        raise Interrupt
      when "TSTP"
        Faktory.logger.info "Received TSTP, no longer accepting new work"
        launcher.quiet
      when "TTIN"
        Thread.list.each do |thread|
          Faktory.logger.warn "Thread TID-#{thread.object_id.to_s(36)} #{thread["faktory_label"]}"
          if thread.backtrace
            Faktory.logger.warn thread.backtrace.join("\n")
          else
            Faktory.logger.warn "<no backtrace available>"
          end
        end
      end
    end

    private

    def print_banner
      # Print logo and banner for development
      if environment == "development" && $stdout.tty?
        puts "\e[31m"
        puts Faktory::CLI.banner
        puts "\e[0m"
      end
    end

    def set_environment(cli_env)
      @environment = cli_env || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
    end

    alias_method :die, :exit
    alias_method :☠, :exit

    def setup_options(args)
      opts = parse_options(args)
      set_environment opts[:environment]

      cfile = opts[:config_file]
      opts = parse_config(cfile).merge(opts) if cfile

      opts[:strict] = true if opts[:strict].nil?
      opts[:concurrency] = Integer(ENV["RAILS_MAX_THREADS"]) if !opts[:concurrency] && ENV["RAILS_MAX_THREADS"]

      options.merge!(opts)
    end

    def options
      Faktory.options
    end

    # Have we been passed a single file to require? e.g. "./worker.rb"
    def req_is_single_file?
      File.exist?(options[:require]) &&
        !File.directory?(options[:require])
    end

    # Have we been given the root of rails directory?
    def req_is_rails_app?
      File.directory?(options[:require]) &&
        File.exist?("#{options[:require]}/config/application.rb")
    end

    # Have we been given a directory with many .rb files? e.g. "./lib/jobs"
    def req_is_class_dir?
      File.directory?(options[:require]) &&
        !Dir.glob("#{options[:require]}/**/*.rb").empty? &&
        !req_is_rails_app?
    end

    def boot_rails_app
        logger.debug("[boot] Found rails app in #{options[:require]}")
        logger.debug("[boot] loading rails and config/environment.rb")

        require "rails"
        require "faktory/rails"
        require File.expand_path("#{options[:require]}/config/environment.rb")
        options[:tag] ||= default_tag
    end

    def boot_worker(req_file)
        require(req_file) && logger.debug("[boot] loaded #{req_file}")
    end

    def boot_worker_multi
        logger.debug("[boot] Found multi-job directory in #{options[:require]}")

        rb_files = Dir.glob("./#{options[:require]}/**/*.rb").flatten
        rb_files.each do |req_file|
          boot_worker(File.expand_path(req_file))
        end
    end

    def boot_system
      ENV["RACK_ENV"] = ENV["RAILS_ENV"] = environment

      boot_rails_app if req_is_rails_app?
      boot_worker(options[:require]) if req_is_single_file?
      boot_worker_multi if req_is_class_dir?
    end

    def default_tag
      dir = ::Rails.root
      name = File.basename(dir)
      if name.to_i != 0 && (prevdir = File.dirname(dir)) # Capistrano release directory?
        if File.basename(prevdir) == "releases"
          return File.basename(File.dirname(prevdir))
        end
      end
      name
    end

    def validate!
      options[:queues] << "default" if options[:queues].empty?

      unless req_is_single_file? || req_is_rails_app? || req_is_class_dir?
        logger.info "========================================================================"
        logger.info "  Require option (-r) does not exist or is not what we expect.          "
        logger.info "                                                                        "
        logger.info "  Please point Faktory to the root of a Rails application, a Ruby file, "
        logger.info "  or a directory containing job classes. ex: -r [DIR|FILE]              "
        logger.info "========================================================================"
        logger.info @parser
        die(1)
      end

      [:concurrency, :timeout].each do |opt|
        raise ArgumentError, "#{opt}: #{options[opt]} is not a valid value" if options.has_key?(opt) && options[opt].to_i <= 0
      end
    end

    def parse_options(argv)
      opts = {}

      @parser = OptionParser.new do |o|
        o.on "-c", "--concurrency INT", "processor threads to use" do |arg|
          opts[:concurrency] = Integer(arg)
        end

        o.on "-e", "--environment ENV", "Application environment" do |arg|
          opts[:environment] = arg
        end

        o.on "-g", "--tag TAG", "Process tag for procline" do |arg|
          opts[:tag] = arg
        end

        o.on "-l", "--label LABEL", "Process label to use in Faktory UI" do |arg|
          (opts[:labels] ||= []) << arg
        end

        o.on "-q", "--queue QUEUE[,WEIGHT]", "Queues to process with optional weights" do |arg|
          queue, weight = arg.split(",")
          parse_queue opts, queue, weight
        end

        o.on "-r", "--require [PATH|DIR]", "Location of Rails application with workers or file to require" do |arg|
          opts[:require] = arg
        end

        o.on "-t", "--timeout NUM", "Shutdown timeout" do |arg|
          opts[:timeout] = Integer(arg)
        end

        o.on "-v", "--verbose", "Print more verbose output" do |arg|
          opts[:verbose] = arg
        end

        o.on "-C", "--config PATH", "path to YAML config file" do |arg|
          opts[:config_file] = arg
        end

        o.on "-V", "--version", "Print version and exit" do |arg|
          puts "Faktory #{Faktory::VERSION}"
          die(0)
        end
      end

      @parser.banner = "faktory-worker [options]"
      @parser.on_tail "-h", "--help", "Show help" do
        logger.info @parser
        die 1
      end
      @parser.parse!(argv)

      %w[config/faktory.yml config/faktory.yml.erb].each do |filename|
        opts[:config_file] ||= filename if File.exist?(filename)
      end

      opts
    end

    def initialize_logger
      Faktory::Logging.initialize_logger(options[:logfile]) if options[:logfile]

      Faktory.logger.level = ::Logger::DEBUG if options[:verbose]
    end

    def parse_config(cfile)
      opts = {}
      if File.exist?(cfile)
        src = ERB.new(IO.read(cfile)).result
        opts = YAML.safe_load(src, permitted_classes: [Symbol], aliases: true) || {}
        opts = opts.merge(opts.delete(environment) || {})
        parse_queues(opts, opts.delete(:queues) || [])
      end
      opts
    end

    def parse_queues(opts, queues_and_weights)
      queues_and_weights.each { |queue_and_weight| parse_queue(opts, *queue_and_weight) }
    end

    def parse_queue(opts, q, weight = nil)
      [weight.to_i, 1].max.times do
        (opts[:queues] ||= []) << q
      end
      opts[:strict] = false if weight.to_i > 0
    end
  end
end
