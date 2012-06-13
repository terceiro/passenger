if GC.respond_to?(:copy_on_write_friendly?) && !GC.copy_on_write_friendly?
	GC.copy_on_write_friendly = true
end

source_root = File.expand_path(File.dirname(__FILE__) + "/../..")
Dir.chdir("#{source_root}/test")

require 'rubygems'
require 'json'
begin
	CONFIG = JSON.load(File.read('config.json'))
rescue Errno::ENOENT
	STDERR.puts "*** You do not have the file test/config.json. " <<
		"Please copy test/config.json.example to " <<
		"test/config.json, and edit it."
	exit 1
end

AGENTS_DIR = "#{source_root}/agents"

$LOAD_PATH.unshift("#{source_root}/lib")
$LOAD_PATH.unshift("#{source_root}/test")

require 'fileutils'
require 'support/test_helper'
require 'phusion_passenger'
PhusionPassenger.locate_directories
require 'phusion_passenger/debug_logging'
require 'phusion_passenger/utils/tmpdir'

include TestHelper

# Seed the pseudo-random number generator here
# so that it doesn't happen in the child processes.
srand

trap "QUIT" do
	puts caller
end

Spec::Runner.configure do |config|
	config.append_before do
		# Suppress warning messages.
		PhusionPassenger::DebugLogging.log_level = -1
		PhusionPassenger::DebugLogging.log_file = nil
		PhusionPassenger::DebugLogging.stderr_evaluator = nil
		
		# Create the temp directory.
		PhusionPassenger::Utils.passenger_tmpdir
	end
	
	config.append_after do
		tmpdir = PhusionPassenger::Utils.passenger_tmpdir(false)
		if File.exist?(tmpdir)
			remove_dir_tree(tmpdir)
		end
	end
end

module LoaderSpecHelper
	def self.included(klass)
		klass.before(:each) do
			@stubs = []
			@apps = []
		end
		
		klass.after(:each) do
			begin
				@apps.each do |app|
					app.close
				end
				# Wait until all apps have exited, so that they don't
				# hog memory for the next test case.
				eventually(5) do
					@apps.all? do |app|
						!PhusionPassenger::Utils.process_is_alive?(app.pid)
					end
				end
			ensure
				@stubs.each do |stub|
					stub.destroy
				end
			end
		end
	end
	
	def before_start(code)
		@before_start = code
	end
	
	def after_start(code)
		@after_start = code
	end
	
	def register_stub(stub)
		@stubs << stub
		File.prepend(stub.startup_file, "#{@before_start}\n")
		File.append(stub.startup_file, "\n#{@after_start}")
		return stub
	end
	
	def register_app(app)
		@apps << app
		return app
	end

	def perform_request(options)
		socket = @loader.connect_and_send_request(options)
		headers = {}
		line = socket.readline
		while line != "\r\n"
			key, value = line.strip.split(/ *: */, 2)
			headers[key] = value
			line = socket.readline
		end
		body = socket.read
		socket.close
		return [headers, body]
	end
end
