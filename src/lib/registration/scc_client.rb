# encoding: utf-8

require "yast"
require "registration/scc_hw_detection"
require "registration/scc_credentials"

require "json"

# network related libs
require "uri"
require "net/http"
require "socket"

module Yast

  # TODO FIXME: add Yardoc comments
  class SccClient

    attr_accessor :url, :email, :reg_code, :insecure, :credentials

    # FIXME: internal testing SCC instance, change to the public production server later
    DEFAULT_SCC_URL = "http://10.122.166.25:3000/connect"

    MAX_REDIRECTS = 10

    JSON_HTTP_HEADER = {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    def initialize(email, reg_code)
      self.url = DEFAULT_SCC_URL
      self.insecure = false
      self.email = email
      self.reg_code = reg_code
    end

    # initial registration via API
    def announce
      body = {
        "email" => email,
        "hostname" => Socket.gethostname,
        "hwinfo" => {
          # TODO FIXME: check the expected structure
          "sockets" => SccHwDetection.cpu_sockets,
          "graphics" => SccHwDetection.gfx_vendor
        }
      }.to_json

      Builtins.y2milestone("Sending announce data: #{body}")

      # see https://github.com/SUSE/happy-customer/wiki/Connect-API#wiki-sys_create
      # TODO FIXME: set "Accept-Language" HTTP header to set the language
      # used for error messages

      params = {
        :url => URI(url + "/announce"),
        :headers => {"Authorization" => "Token token=\"#{reg_code}\""},
        :body => body,
        :method => :post
      }

      result = json_http_handler(params)

      self.credentials = SccCredentials.new(result["login"], result["password"])
    end

    def register(base_product)
      body = {
        "token" => reg_code,
        "product_ident" => base_product["name"],
        "product_version" => base_product["version"],
        "arch" => base_product["arch"]
      }.to_json

      params = {
        :url => URI(url + "/activate"),
        :body => body,
        :method => :post,
        :credentials => credentials
      }

      json_http_handler(params)
    end

    private

    # generic HTTP(S) transfer for JSON requests/responses
    # TODO: proxy support? (http://apidock.com/ruby/Net/HTTP)
    def json_http_handler(params, redirect_count = MAX_REDIRECTS)
      raise "Reached maximum number of HTTP redirects, aborting" if redirect_count == 0

      target_url = params[:url]
      raise "URL parameter missing" unless target_url

      headers = params[:headers] || {}
      body = params[:body] || ""
      method = params[:method] || :get

      http = Net::HTTP.new(target_url.host, target_url.port)

      # switch to HTTPS connection
      if target_url.is_a? URI::HTTPS
        http.use_ssl = true
        http.verify_mode = insecure ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
        Builtins.y2security("Warning: SSL certificate verification disabled") if insecure
      else
        Builtins.y2security("Warning: Using insecure \"#{target_url.scheme}\" transfer protocol")
      end

      case method
      when :post then
        request = Net::HTTP::Post.new(target_url.request_uri)
      when :put then
        request = Net::HTTP::Put.new(target_url.request_uri)
      when :get then
        request = Net::HTTP::Get.new(target_url.request_uri)
      else
        raise "Unsupported HTTP method: #{method}"
      end

      JSON_HTTP_HEADER.merge(headers).each {|k,v| request[k] = v}
      request.body = body

      # use Basic Auth if credentials are present
      if params[:credentials]
        request.basic_auth(params[:credentials].username, params[:credentials].password)
      end

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
        params[:url] = URI(location)
        Builtins.y2milestone("Redirected to #{location}")

        # retry recursively
        json_http_handler(params, redirect_count - 1)
      else
        # TODO error handling
        Builtins.y2error("HTTP Error: #{response.inspect}")
        raise "HTTP failed: #{response.code}: #{response.message}"
      end
    end

  end
end
