# encoding: utf-8

require "yast"

module Yast

  # TODO FIXME: add Yardoc comments
  class SccHwDetection

    # the most important are ATI and nVidia for which we can offer driver
    # repositories, the rest is not important
    VENDOR_ID_MAPPING = {
      0x1002 => "ati",
      0x10de => "nvidia",
      0x8086 => "intel"
    }

    def self.cpu_info
      lc_all_bak = ENV["LC_ALL"]
      # run "lscpu" in "C" locale to suppress translations
      ENV["LC_ALL"] = "C"
      return `lscpu`
    ensure
      ENV["LC_ALL"] = lc_all_bak
    end

    def self.gfx_vendor
      vendor_id = SCR.Read(Path.new(".probe.display")).first["vendor_id"] - 0x10000
      Builtins.y2milestone("Graphics card vendor_id: #{vendor_id.inspect}")

      VENDOR_ID_MAPPING[vendor_id] || "unknown"
    end
  end

end