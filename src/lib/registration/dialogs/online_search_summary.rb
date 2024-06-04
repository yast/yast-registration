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
        super()
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

      # @macro seeAbstractWidget
      def title
        # TRANSLATORS: title for the dialog which displays modules/extensions to
        # install and packages to register
        _("Changes Summary")
      end

      # @macro seeAbstractWidget
      def help
        # TRANSLATORS: help text for the summary of the online search feature
        _("<p><b>Online Search Changes Summary</b></p>\n" \
          "<p>This screen summarizes which modules/extensions are going to be activated and " \
          "which packages are going to be installed. If you are okay with those changes, click " \
          "the <b>Next</b> button. However, if you prefer to add or remove any item, click the " \
          "<b>Back</b> button to get to the search dialog. Finally, if you decide not to perform " \
          "any change to your system, click the <b>Cancel</b> button.</p>")
      end

    private

      # @return [Array<RemotePackage>] Packages to install
      attr_reader :packages

      # @return [Array<Addon>] Addons to register
      attr_reader :addons

      # Returns a string that contains a list of addons to register
      #
      # @see #collection_summary
      #
      # @return [String] text containing the list of addons
      def addons_text
        collection_summary(_("Modules/extensions to register (%{count})"), addons)
      end

      # Returns a string that contains the list of packages to select
      #
      # @see #collection_summary
      #
      # @return [String] text containing the list of packages
      def packages_text
        collection_summary(_("Selected packages (%{count})"), packages)
      end

      # Returns a string that contains a list with given collection names
      #
      # @param text [String] a translatable text including the %{count} named param
      # @param collection [Arary<#name>] a collection with objects that responds to `#name`
      #
      # @return [String] text list with given collection; an empty string when collection is empty
      def collection_summary(text, collection)
        return "" if collection.empty?

        heading = format(text, count: collection.size)
        Yast::HTML.Heading(heading) + Yast::HTML.List(collection.map(&:name).sort)
      end
    end
  end
end
