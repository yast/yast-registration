# encoding: utf-8


require "fileutils"

module Yast

  # TODO FIXME: add Yardoc comments
  class SccCredentials

    attr_accessor :username, :password

    DEFAULT_CREDENTIALS_FILE = "/etc/zypp/credentials.d/SCCcredentials"

    def initialize(user, password)
      self.username = user
      self.password = password
    end

    def self.read_file(file = DEFAULT_CREDENTIALS_FILE)
      content = File.read(file)

      user, passwd = parse_credentials(content)
      SccCredentials.new(user, passwd)
    end

    def write_file(file = DEFAULT_CREDENTIALS_FILE)
      # create the target directory if it is missing
      dirname = File.dirname(file)
      FileUtils.mkdir_p(dirname) unless File.exist?(dirname)

      File.write(file, serialize)
    end

    private

    def self.parse_credentials(input)
      user = nil
      passwd = nil

      if input.match /^\s*username\s*=\s*(\S+)\s*$/
        user = $1
      end

      if input.match /^\s*password\s*=\s*(\S+)\s*$/
        passwd = $1
      end

      return [ user,  passwd ]
    end

    def serialize
      "username=#{username}\npassword=#{password}\n"
    end

  end
end
