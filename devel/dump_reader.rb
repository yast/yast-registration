#! /usr/bin/ruby
# typed: false

# This is a simple reader for the addons dumps,
# tweak it as needed to display more details about the addons.

require "yast"
require "registration/addon"

require_relative "yaml_workaround"

INDENT_WIDTH = 2

# dump addon data on STDOUT, recursively dumps the dependant addons
def dump_addon(a, indent_level = 0)
  prefix = " " * INDENT_WIDTH * indent_level
  puts
  puts prefix + "Display Name: #{a.friendly_name}"
  puts prefix + "ID: #{a.identifier}-#{a.version}-#{a.arch}"
  puts prefix + "EULA: #{a.eula_url}"
  puts prefix + "Free: #{a.free}"

  return unless a.depends_on

  puts prefix + "Depends on:"
  dump_addon(a.depends_on, indent_level + 1)
end

if ARGV[0]
  addons = YAML.load_file(ARGV[0])
  addons.each { |a| dump_addon(a) }
else
  puts "This is a simple reader for registration addon dumps."
  puts
  puts "Usage: dump_reader <file_path>"
  puts
  puts "  <file_path> is the addons dump file, originally stored at"
  puts "  /var/log/YaST2/registration_addons.yml"
  exit 1
end
