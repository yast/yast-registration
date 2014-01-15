# encoding: utf-8

require "yast"
require "registration/scc_hw_detection"

require "json"

# network related libs
require "uri"
require "net/http"
require "socket"

module Yast

  # TODO FIXME: add Yardoc comments
  class SccClient

    attr_accessor :url, :email, :reg_code, :insecure

    # FIXME: internal testing SCC instance, change to the public production server later
    DEFAULT_SCC_URL = "http://10.122.166.25:3000/connect"

    MAX_REDIRECTS = 10

    def initialize(email, reg_code)
      self.url = DEFAULT_SCC_URL
      self.insecure = false
      self.email = email
      self.reg_code = reg_code
    end

    def announce
      announce_handler
    end

    private

    # initial registration via API
    # TODO: proxy support? (http://apidock.com/ruby/Net/HTTP)
    def announce_handler(location = nil, redirects = MAX_REDIRECTS)
      raise "Reached maximum number of HTTP redirects, aborting" if redirects == 0

      scc_url = URI(location || (url + "/announce"))

      http = Net::HTTP.new(scc_url.host, scc_url.port)

      # switch to HTTPS connection
      if scc_url.is_a? URI::HTTPS
        http.use_ssl = true
        http.verify_mode = insecure ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
        Builtins.y2security("Warning: SSL certificate verification disabled") if insecure
      else
        Builtins.y2security("Warning: Using insecure \"#{scc_url.scheme}\" transfer protocol")
      end

      request = Net::HTTP::Post.new(scc_url.request_uri)
      # see https://github.com/SUSE/happy-customer/wiki/Connect-API#wiki-sys_create
      request["Authorization"] = "Token token=\"#{reg_code}\""
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      # TODO FIXME: set "Accept-Language" HTTP header to set the language
      # used for error messages

      request.body = {
        "email" => email,
        "hostname" => Socket.gethostname,
        "hwinfo" => {
          # TODO FIXME: check the expected structure
          "sockets" => SccHwDetection.cpu_info,
          "graphics" => SccHwDetection.gfx_vendor
        }
      }.to_json

      Builtins.y2milestone("Sending data: #{request.body} to #{scc_url}")

      response = http.request(request)

      case response
      when Net::HTTPSuccess then
        # FIXME: better test the type, this looks fragile...
        if response["content-type"] == "application/json; charset=utf-8"
          Builtins.y2milestone("SCC request succeeded")
          return JSON.parse(response.body)
        else
          raise RuntimeError, "Unexpected content-type: #{response['content-type']}"
        end
      when Net::HTTPRedirection then
        location = response['location']

        if location.nil? || location.empty?
          # TODO FIXME
          raise "Wrong redirection from server"
        end

        Builtins.y2milestone("Redirected to #{location}")
        # retry recursively
        announce_handler(location, redirects - 1)
      else
        # TODO error handling
        Builtins.y2error("HTTP Error: #{response.inspect}")
        raise RuntimeError, "HTTP failed: #{response.code}: #{response.message}"
      end
    end

  end
end
