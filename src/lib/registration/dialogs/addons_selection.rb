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
require "registration/ui/abort_confirmation"
require "registration/controllers/addons_selection"
require "registration/widgets/master_detail_selector"

module Registration
  module Dialogs
    # The dialog to display the addons selection for registered products
    class AddonsSelection < CWM::Dialog
      Yast.import "Stage"

      # @return [Registration::Registration] the object handling the communication with SCC
      attr_reader :registration

      # Constructor
      #
      # @param registration [Registration::Registration]
      def initialize(registration)
        textdomain "registration"

        @registration = registration

        super()
      end

      # @macro seeDialog
      def title
        _("Extension and Module Selection")
      end

      # @macro seeDialog
      def contents
        VBox(
          Left(Heading(_("Available Extensions and Modules"))),
          addons_selector_widget
        )
      end

      # @macro seeDialog
      def run
        ret = super until continue_actions.include?(ret)

        case ret
        when :next
          ret = handle_next_action
        when :cancel, :abort
          ret = handle_cancel_action
        end

        ret
      end

      # Handles the cancel action
      #
      # @return [nil, :abort] nil if user regrets about canceling; :abort otherwise
      def handle_cancel_action
        return nil if Yast::Stage.initial && !UI::AbortConfirmation.run

        controller.restore_selection
        :abort
      end

      # Handles the next action
      #
      # This action will be canceled if there are selected too many addons requiring a registration
      # code. Ssee {Registration::Controllers::AddonsSelection#supported_addon_count}
      #
      # @return [nil, :skip, :abort] nil if there are too many addons requiring reg. code;
      #                              :skip when there are no selected addons;
      #                              :next otherwise
      def handle_next_action
        return nil unless controller.supported_addon_count?

        controller.selected_items.empty? ? :skip : :next
      end

      # @return [Array<Symbol>]
      def continue_actions
        @continue_actions ||= [:next, :back, :cancel, :abort, :skip]
      end

      # @macro seeDialog
      def help
        [
          _("<p>Here you can select available extensions and modules for your system.</p>"),
          _("<p>Please note, that some extensions or modules might need "\
            "specific registration code.</p>"),
          _("<p>If you want to remove any extension or module you need to log "\
            "into the SUSE Customer Center and remove them manually there.</p>"),
          _("<p>The extensions and modules can have several states depending on " \
            "how they were selected to be installed or not (see the legend below). Note "\
            "that an extension or module can be selected by the user, pre-selected as a "\
            "recommended addon, or auto selected as a dependency of another extension "\
            "or module.</p>")
        ].join
      end

    private

      # Addons selector widget
      #
      # @return [Registration::Widgets::MasterDetailSelector]
      def addons_selector_widget
        @addons_selector_widget ||= ::Registration::Widgets::MasterDetailSelector.new(controller)
      end

      # Addons selection controller
      #
      # @return [Registration::Controllers::AddonsSelection]
      def controller
        @controller ||= ::Registration::Controllers::AddonsSelection.new(registration)
      end
    end
  end
end
