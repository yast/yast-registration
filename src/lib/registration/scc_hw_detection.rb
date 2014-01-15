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

    UNKNOWN_VENDOR = "unknown"

    def self.cpu_sockets
      lc_all_bak = ENV["LC_ALL"]
      # run "lscpu" in "C" locale to suppress translations
      ENV["LC_ALL"] = "C"
      ret = `lscpu`

      if ret.match /^Socket\(s\):\s*(\d+)\s*$/
        Builtins.y2milestone("Detected CPU sockets: #{$1}")
        return $1.to_i
      else
        raise "CPU detection failed"
      end
    ensure
      ENV["LC_ALL"] = lc_all_bak
    end

    def self.gfx_vendor
      display_list = SCR.Read(Path.new(".probe.display"))
      return UNKNOWN_VENDOR if display_list.nil? || display_list.empty?

      # use only lower 16 bits for vendor ID, the higher bits contain
      # bus prefix (see TAG_* values, ID_VALUE() and MAKE_ID() macros in <hd/hd.h>)
      # (https://github.com/openSUSE/hwinfo/blob/master/src/hd/hd.h#L83)
      vendor_id = display_list.first["vendor_id"] & 0xffff
      Builtins.y2milestone("Graphics card vendor_id: #{vendor_id} (#{sprintf("%#x", vendor_id)})")

      VENDOR_ID_MAPPING[vendor_id] || UNKNOWN_VENDOR
    end
  end

end