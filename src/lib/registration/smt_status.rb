
require "uri"
require "yast"

require "registration/downloader"

module Registration
  # Check SMT server status, check supported API
  class SmtStatus
    include Yast::Logger

    attr_reader :url, :insecure

    def initialize(url, insecure: false)
      @url = url.is_a?(URI) ? url : URI(url)
      @insecure = insecure
    end

    # check whether (old) NCC API is present at the server
    def ncc_api_present?
      download_url = ncc_api_url
      log.info "Checking NCC API presence: #{download_url}"

      begin
        Downloader.download(download_url, insecure: insecure)
        log.info "NCC API found"
        return true
      rescue DownloadError
        log.info "Download failed, NCC API probably not present"
        return false
      end
    end

    private

    # created NCC API URL for testing API presence
    def ncc_api_url
      # create an URI copy, the URL will be modified
      ncc_url = url.dup

      # NCC API should provide "/center/regsvc?command=listproducts" query
      ncc_url.path = "/center/regsvc"
      ncc_url.query = "command=listproducts"

      ncc_url
    end
  end
end
