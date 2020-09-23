# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE, LLC. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

require "tempfile"

require "yast"
require "transfer/file_from_url"

Yast.import "XML"
Yast.import "Linuxrc"

module Registration
  # Aids Registration::Storage::RegCodes in loading the codes
  # from external storage so that the user does not have to type them
  # each time when doing multiple installations. FATE#316796
  module RegistrationCodesLoader
    include Yast::I18n # missing in yast2-update
    include Yast::Transfer::FileFromUrl
    include Yast::Logger

    REGCODES_NAME_HANDLERS = {
      "regcodes.xml" => :reg_codes_from_xml,
      "regcodes.txt" => :reg_codes_from_txt
    }.freeze

    # @return [Hash{String => String},nil]
    def reg_codes_from_usb_stick
      with_tempfile("regcodes-") do |path|
        REGCODES_NAME_HANDLERS.each do |name, handler|
          next unless get_file_from_url(scheme: "usb", host: "",
                                        urlpath: "/#{name}",
                                        localfile: path,
                                        urltok: {}, destdir: "")
          codes = send(handler, path)
          return codes if codes
        end
      end
      nil
    end

    # Loades registration code from /etc/install.inf
    #
    # Expected format is reg_code: <product>:<registration_code>
    # for example: reg_code: sle15:abcdefghijkl
    #
    # @return [Hash{String => String}, nil] The key of the hash is product name
    #                                       and the value is registration code
    def reg_codes_from_install_inf
      raw_reg_code = Yast::Linuxrc.InstallInf("reg_code") || ""
      raw_reg_code.include?(":") ? [raw_reg_code.split(":", 2)].to_h : nil
    end

    # @param pattern [String] template for tempfile name
    # @yieldparam actual file name
    def with_tempfile(pattern, &block)
      tempfile = Tempfile.new(pattern)
      block.call(tempfile.path)
    ensure
      tempfile.close
      tempfile.unlink
    end

    # @param filename [String]
    # @return [Hash{String => String},nil]
    def reg_codes_from_xml(filename)
      return nil unless File.readable?(filename) && File.file?(filename)
      xml_hash = Yast::XML.XMLToYCPFile(filename)
      parse_xml(xml_hash)
    rescue Yast::XMLDeserializationError => e
      log.error "Invalid reg codes XML: #{e.inspect}"
      return nil
    end

    # @param xml_hash [Hash] as used in AY and returned by Yast::XML.XMLToYCPFile
    # @return [Hash{String => String},nil]
    def parse_xml(xml_hash)
      suse_register = xml_hash.fetch("suse_register", {})
      addons = suse_register.fetch("addons", [])
      pairs = addons.map do |a|
        [a.fetch("name", ""), a.fetch("reg_code", "")]
      end
      Hash[pairs]
    end

    # The format is: lines with a key and a value,
    #   separated by white space
    # @param filename [String]
    # @return [Hash{String => String},nil]
    def reg_codes_from_txt(filename)
      return nil unless File.readable?(filename) && File.file?(filename)
      text = File.read(filename)
      # TODO: report parse errors in log
      pairs = text.each_line.map do |l|
        l.chomp.split(/\s+/, 2)
      end
      Hash[pairs.reject(&:empty?)]
    end
  end
end
