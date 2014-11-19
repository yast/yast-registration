require "uri"

module Registration
  # class to read and query old suse register configuration file
  class SuseRegister
    PATH = "/etc/suseRegister.conf"
    NCC_HOST = "secure-www.novell.com"

    def initialize(root)
      @found = read_conf(root)
    end

    # found suse register with valid content?
    def found?
      @found
    end

    # does it found ncc url in registration?
    def ncc?
      found? && url.host == NCC_HOST
    end

    # url with removed old registration suffix
    def stripped_url
      res = url.dup
      res.path = ""
      res
    end

    private
    attr_reader :url

    def read_conf(root)
      path = File.join(root, PATH)
      return false unless File.exist?(path)

      lines = File.readlines(path)
      url_line = lines.grep(/^\s*url\s*=/).last
      return false unless url_line

      url_s = url_line[/^\s*url\s*=\s*(\S*)/, 1]
      @url = URI.parse(url_s)
      true
    end
  end
end
