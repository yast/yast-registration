# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "cwm/dialog"

module Registration
  module Dialogs
    class OnlineSearchSummary < CWM::Dialog
      include Yast::I18n

      # Constructor
      #
      # @param packages [Array<RemotePackage>] Packages to install
      # @param addons [Array<Addon>] Addons to register
      def initialize(packages, addons)
        textdomain "registration"
        @packages = packages
        @addons = addons
      end

      # @macro seeDialog
      def contents
        VBox(
          RichText(Id(:summary), addons_text + packages_text)
        )
      end

      # @macro seeDialog
      def abort_button
        Yast::Label.CancelButton
      end

      def title
        # TRANSLATORS: title for the dialog which displays modules/extensions to
        # install and packages to register
        _("Changes Summary")
      end

    private

      # @return [Array<RemotePackage>] Packages to install
      attr_reader :packages

      # @return [Array<Addon>] Addons to register
      attr_reader :addons

      # Returns a string that contains a list of addons to register
      #
      # @return [String] text containing the list of addons; an empty string
      #   is returned if there are no addons
      def addons_text
        return "" if addons.empty?
        heading = format(_("Modules/extensions to register (%{count})"), count: addons.size)
        Yast::HTML.Heading(heading) + Yast::HTML.List(addons.map(&:name).sort)
      end

      # Returns a string that contains the list of packages to select
      #
      # @return [String] text containing the list of packages
      def packages_text
        return "" if packages.empty?
        heading = format(_("Selected packages (%{count})"), count: packages.size)
        Yast::HTML.Heading(heading) + Yast::HTML.List(packages.map(&:name).sort)
      end
    end
  end
end
