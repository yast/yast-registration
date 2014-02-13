# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2013 Novell, Inc. All Rights Reserved.
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
#
# Summary: Ask user for the SCC credentials
#

# use external rubygem for SCC communication
require "scc_api"

require "tmpdir"
require "fileutils"

module Yast
  class InstSccClient < Client
    include Yast::Logger

    ZYPP_DIR = "/etc/zypp"

    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "registration"

      Yast.import "Popup"
      Yast.import "GetInstArgs"
      Yast.import "Wizard"
      Yast.import "Report"
      Yast.import "Mode"

      # redirect the scc_api log to y2log
      SccApi::GlobalLogger.instance.log = Y2Logger.instance

      show_scc_credentials_dialog

      ret = nil

      continue_buttons = [:next, :back, :close, :abort]
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        if ret == :next
          email = UI.QueryWidget(:email, :Value)
          reg_code = UI.QueryWidget(:reg_code, :Value)

          begin
            register(email, reg_code)
          rescue Exception => e
            log.error("SCC registration failed: #{e}, #{e.backtrace}")
            # TODO: display error details
            Report.Error(_("Registration failed."))
            ret = nil
          end
        end

        # skip the registration
        return :next if ret == :skip
      end

      return ret
    end


    private

    def register(email, reg_code)
      scc = SccApi::Connection.new(email, reg_code)

      # announce (register the system) first
      credentials = run_with_feedback(_("Registering the System..."), _("Contacting the SUSE Customer Center server")) do
        scc.announce
      end

      # ensure the zypp config directories are writable in inst-sys
      ensure_zypp_config_writable

      # write the global credentials
      credentials.write

      # then register the product(s)
      product_services = run_with_feedback(_("Registering the Product..."), _("Contacting the SUSE Customer Center server")) do
        # there will be just one base product, but theoretically there can be more...
        selected_base_products.map do |base_product|
          log.info("Registering base product: #{base_product.inspect}")
          scc.register(base_product)
        end
      end

      add_services(product_services, credentials)
    end

    # add the services to libzypp and load (refresh) them
    def add_services(product_services, credentials)
      # save repositories before refreshing added services (otherwise
      # pkg-bindings will treat them as removed by the service refresh and
      # unload them)
      Pkg.SourceSaveAll

      # each registered product
      product_services.each do |product_service|
        # services for the each product
        product_service.services.each do |service|
          log.info "Adding service #{service.name.inspect} (#{service.url})"

          # TODO FIXME: SCC currenly does not return credentials for the service,
          # just reuse the global credentials and save to a different file
          credentials.file = service.name + "_credentials"
          credentials.write

          Pkg.ServiceAdd(service.name, service.url.to_s)
          # refresh works only for saved services
          Pkg.ServiceSave(service.name)
          Pkg.ServiceRefresh(service.name)
        end
      end
    end

    def scc_credentials_dialog
      VBox(
        Frame(_("SUSE Customer Center Credentials"),
          MarginBox(1, 0.5,
            VBox(
              InputField(Id(:email), _("&Email")),
              VSpacing(0.5),
              InputField(Id(:reg_code), _("Registration &Code"))
            )
          )
        ),
        VSpacing(3),
        PushButton(Id(:skip), _("&Skip Registration"))
      )
    end

    def scc_help_text
      # TODO: improve the help text
      _("Enter SUSE Customer Center credentials here to register the system to get updates and add-on products.")
    end

    def show_scc_credentials_dialog
      Wizard.SetContents(
        _("SUSE Customer Center Registration"),
        scc_credentials_dialog,
        scc_help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next || Mode.normal
      )
    end

    def selected_base_products
      # just for debugging:
      # return [{"name" => "SUSE_SLES", "arch" => "x86_64", "version" => "12-"}]

      # source 0 is the base installation repo, the repos added later are considered as add-ons
      # although they can also contain a different base product
      selected_base_products = Pkg.ResolvableProperties("", :product, "").find_all do |p|
        p["source"] == 0 && p["status"] == :selected
      end

      # filter out not needed data
      product_info = selected_base_products.map{|p| { "name" => p["name"], "arch" => p["arch"], "version" => p["version"]}}

      log.info("Found selected base products: #{product_info}")

      product_info
    end

    def run_with_feedback(header, label, &block)
      Popup.ShowFeedback(header, label)
      yield
    ensure
      Popup.ClearFeedback
    end

    # during installation /etc/zypp directory is not writable (mounted on
    # a read-only file system), the workaround is to copy the whole directory
    # structure into a writable temporary directory and override the original
    # location by "mount -o bind"
    def ensure_zypp_config_writable
      if Mode.installation && !File.writable?(ZYPP_DIR)
        log.info "Copying libzypp config to a writable place"

        # create writable zypp directory structure in /tmp
        tmpdir = Dir.mktmpdir

        log.info "Copying #{ZYPP_DIR} to #{tmpdir} ..."
        ::FileUtils.cp_r ZYPP_DIR, tmpdir

        log.info "Mounting #{tmpdir} to #{ZYPP_DIR}"
        `mount -o bind #{tmpdir} #{ZYPP_DIR}`
      end
    end

  end
end

Yast::InstSccClient.new.main
