# encoding: utf-8

# ***************************************************************************
#
# Copyright (c) 2006 - 2012 Novell, Inc.
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail,
# you may find current contact information at www.novell.com
#
# ***************************************************************************
# File:        installation/general/inst_suse_register
# Module:      Installation
# Summary:     Perform Customer Center Configuration
#              this includes (by calling suse_register):
#                              machine registration
#                              if needed, launch browser for user/customer registration
#                              ZMD configuration
# Authors:     J. Daniel Schmidt <jdsn@suse.de>
#
# Perform Customer Center Configuration
#
# $Id: inst_suse_register.ycp 1 2006-02-17 13:20:02Z jdsn $
module Yast
  class InstSuseRegisterClient < Client
    def main
      Yast.import "UI"
      textdomain "registration"

      Yast.import "FileUtils"
      Yast.import "InstURL"
      Yast.import "URL"
      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "GetInstArgs"
      Yast.import "CustomDialogs"
      Yast.import "Directory"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "String"
      Yast.import "Label"
      Yast.import "Internet"
      Yast.import "Register"
      Yast.import "RegistrationStatus"
      Yast.import "YSR"
      Yast.import "SourceManager"
      Yast.import "Package"
      Yast.import "PackageCallbacks"
      Yast.import "CommandLine"
      Yast.import "NetworkService"
      Yast.include self, "registration/texts.rb"


      # support basic command-line output (bnc#430859)
      @wfm_args = WFM.Args
      Builtins.y2milestone("ARGS: %1", @wfm_args)
      if Ops.greater_than(Builtins.size(@wfm_args), 0) &&
          (Builtins.contains(@wfm_args, "help") ||
            Builtins.contains(@wfm_args, "longhelp") ||
            Builtins.contains(@wfm_args, "xmlhelp"))
        @cmdhelp = _("Registration Module Help")
        Mode.SetUI("commandline")
        # TRANSLATORS: commandline help
        CommandLine.Run({ "id" => "registration", "help" => @cmdhelp })
        Builtins.y2milestone("Registration was called with help parameter.")
        return :auto
      end

      # this operation MUST be first and run in any case, even if registration should be skipped (FATE #302966)
      @confRegSrv = Register.configureRegistrationServer
      if @confRegSrv == :conferror || @confRegSrv == :notrust ||
          @confRegSrv == :silentskip
        Builtins.y2error(
          "Registration can not be run due to SMT configuration error."
        )
        return :auto
      end

      # no network - no suse_register
      # test for existing network connection (bnc#475795)
      if Stage.cont &&
          (!Internet.suse_register || !NetworkService.isNetworkRunning)
        Builtins.y2error(
          "The internet test failed or no network connection is available. Registration will be skipped."
        )
        Internet.do_you = false
        return :auto
      end

      @IAMSLE = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          " [ -e /usr/share/applications/YaST2/customer_center.desktop ] "
        )
      ) == 0 ? true : false

      # Register::initialize() is mandatory - never remove it
      Register.initialize

      @registration_status = {}

      @ui = UI.GetDisplayInfo
      @textmode = Ops.get_boolean(@ui, "TextMode")

      # strings for main (wizard) layout

      # Translators: This is title/brand - verify how to translate it correctly
      @title_nccc = _("Novell Customer Center Configuration")

      # Translators: Module Title for the Box
      @title_box = _("Online Update Configuration") # (#165509)

      # alternative short title text
      @title_short = _("Registration")
      @title_long = _("Support Registration")

      # select title to use
      # use new default title
      @title = @title_short


      # Translators: limit to 2x 50 charachters - if more needed take 3x 50 chars but NOTHING more
      @nccc_top = _(
        "Get technical support and product updates and\nmanage subscriptions with Novell Customer Center."
      )
      # Translators: limit to 2x 50 charachters - if more needed take 3x 50 chars but NOTHING more
      @opensuse_top = _(
        "Get technical support and product updates\nby registering this installation."
      )


      @nccc_heading = ""
      # if we are SLES then switch to NCCC title  (#294454)
      if @IAMSLE
        @title = @title_nccc
        @nccc_heading = @nccc_top
      else
        @title = @title_short
        @nccc_heading = @opensuse_top
      end


      @nccc_configure = _("Configure Now (Recommended)")
      @nccc_noconfigure = _("Configure Later")
      # alternative strings for the main dialog
      @nccc_register_now = _("Register Now (Recommended)")
      @nccc_register_later = _("Register Later")

      @nccc_sub_comment = _("Include for Convenience")
      @nccc_sub_hwinfo = _("Hardware Profile")
      @nccc_cur_reg_stat = _("Registration Status")
      @nccc_sub_optional = _("Optional Information")
      @nccc_forcereg = _("Registration Code")
      @nccc_sub_showbtn = _("Details...")
      @nccc_privacy_detail = _("Registration and Privacy Details")


      #  strings for success popup
      @nccc_success_msg = _("Your configuration was successful.")
      @nccc_success_msg_registration = _("Your registration was successful.")
      @nccc_success_server_added = _(
        "An update server has been added to your configuration."
      )
      @nccc_success_server_added = Ops.get_string(@TXT, "reposUpdated_old", "")
      @nccc_error_no_server_added = _(
        "No update server could be added to your configuration."
      )
      @nccc_no_source_changes0 = _(
        "No software repository needed to be changed."
      )
      @nccc_no_source_changes = _(
        "Software repositories did not need to be changed."
      )
      # caption for details view
      @success_detail_label_old = _("New Update Server")
      @success_detail_label_new = _("Updated software repositories")
      @success_detail_label = @success_detail_label_new

      # strings for manual interaction popup
      @mi_required = _("Manual Interaction Required")
      @mi_needinfo = _("Needed Information")
      @mi_browser_btn = _("Continue")
      @mi_start_browser = _(
        "A Web browser will start in which to complete\nthe configuration on the opened Web site."
      )


      @title_regularly_run = _("Regularly Synchronize with the Customer Center")

      # string for show information popup
      @transmit_info = _("Registration and Privacy Information")

      #  strings for conflict popup
      @conflict_need_info = _(
        "The server requires additional system information. Activating \nsubmission of the hardware profile automatically."
      )

      #  nonroot-message strings
      @nonroot_title = _("Update Source Issues")
      @nonroot_message = _(
        "Registering as a regular user does not include the update source\n" +
          "in the Online Update YaST module. If you continue and later want \n" +
          "to update with Online Update, the source must be added manually.\n" +
          "Other tools, such as Software Updater in the panel, can still be \n" +
          "used. Alternatively, cancel then register through YaST as root \n" +
          "so the sources are available to all tools."
      )



      # error messages
      @data_invalid = _("Error: Data received is invalid.")
      @retrieve_error = _("Error: Could not retrieve data.")
      @no_browser_msg = _(
        "No Web browser available.\nRun the suse_register command manually."
      )
      @no_product_msg = _(
        "No product found to be registered.\n" +
          "You do not need to register this installation.\n" +
          "Please add update sources yourself."
      )
      @no_w3m_msg = _(
        "Your registration requires interactive input that is not\n" +
          "supported in text mode. Run YaST2 in the graphical mode or\n" +
          "run the suse_register command manually."
      )

      # help text for dialog "Novell Customer Center Configuration"
      @help_title = Builtins.sformat("<p><b>%1</b></p>", @title)
      @help_para1 = _(
        "<p>\n" +
          "Configure your system to enable online updates by registering it with Novell.\n" +
          "To do this now, select <b>Configure Now</b>. Delay the registration with\n" +
          "<b>Configure Later</b>.\n" +
          "</p>"
      )

      @help_para2 = _(
        "<p>\n" +
          "To simplify the registration process, include information from your system\n" +
          "with <b>Optional Information</b> and <b>Hardware Profile</b>. \n" +
          "<b>Details</b> shows the maximum amount of information that can be involved\n" +
          " in your registration. To obtain this information, it contacts the Novell\n" +
          "server to query what information is needed for your product. Only the identity\n" +
          "of the installed product is sent in this initial exchange.\n" +
          "</p>"
      )

      @help_para3 = _(
        "<p>\n" +
          "If you purchased your copy of this product, enable <b>Registration Code</b>\n" +
          "so you are prompted for your product code. \n" +
          "This registers you for the installation support included with your product.\n" +
          "</p>"
      )

      @help_para4 = _(
        "<p>\n" +
          "No information is passed to anyone outside Novell. The data is used for\n" +
          "statistical purposes and to enhance your convenience regarding driver support\n" +
          "and your Web account. Find a detailed privacy policy in <b>Details</b>. View\n" +
          "the transmitted information in the log file <tt>~/.suse_register.log</tt>.\n" +
          "</p>"
      )

      @help_para5 = _(
        "<p>\n" +
          "<b>Regularly Synchronize with the Customer Center</b> checks that your update \n" +
          "sources are still valid and adds any new ones that may be available.\n" +
          "It additionally sends any modifications to your included data to Novell, such \n" +
          "as hardware information if <b>Hardware Information</b> is activated.\n" +
          "This option does not remove any sources added manually.\n" +
          "</p>"
      )

      @help_para6 = _(
        "<p>\n" +
          "The registration process will contact a Novell server (or a local registration server if your company provides one).\n" +
          "Make sure that the network and proxy settings are correct.\n" +
          "You can go back to the network setup to check or change the settings.\n" +
          "</p>\n"
      )

      #  START - Help Texts for OPEN-SLX

      @help_para1_openslx = _(
        "<p>\n" +
          "Configure your system to enable online updates by registering it with Open-SLX.\n" +
          "To do this now, select <b>Configure Now</b>. Delay the registration with\n" +
          "<b>Configure Later</b>.\n" +
          "</p>"
      )

      @help_para2_openslx = _(
        "<p>\n" +
          "To simplify the registration process, include information from your system\n" +
          "with <b>Optional Information</b> and <b>Hardware Profile</b>. \n" +
          "<b>Details</b> shows the maximum amount of information that can be involved\n" +
          " in your registration. To obtain this information, it contacts the Open-SLX\n" +
          "server to query what information is needed for your product. Only the identity\n" +
          "of the installed product is sent in this initial exchange.\n" +
          "</p>"
      )

      @help_para4_openslx = _(
        "<p>\n" +
          "No information is passed to anyone outside Open-SLX. The data is used for\n" +
          "statistical purposes and to enhance your convenience regarding driver support\n" +
          "and your Web account. Find a detailed privacy policy in <b>Details</b>. View\n" +
          "the transmitted information in the log file <tt>~/.suse_register.log</tt>.\n" +
          "</p>"
      )

      @help_para5_openslx = _(
        "<p>\n" +
          "<b>Regularly Synchronize with the Customer Center</b> checks that your update \n" +
          "sources are still valid and adds any new ones that may be available.\n" +
          "It additionally sends any modifications to your included data to Open-SLX, such \n" +
          "as hardware information if <b>Hardware Information</b> is activated.\n" +
          "This option does not remove any sources added manually.\n" +
          "</p>"
      )

      @help_para6_openslx = _(
        "<p>\n" +
          "The registration process will contact an Open-SLX server (or a local registration server if your company provides one).\n" +
          "Please make sure that the network and proxy settings are correct.\n" +
          "You can step back to the network setup to check or change the settings.\n" +
          "</p>"
      )

      #  END - Help Texts for OPEN-SLX

      @help = ""

      if @IAMSLE
        @help = Ops.add(
          Ops.add(
            Ops.add(Ops.add(@help_title, @help_para1), @help_para2),
            Register.display_forcereg ? @help_para3 : ""
          ),
          @help_para4
        )
        @help = Ops.add(@help, @help_para6) if !Mode.normal
      else
        # for now disable Open-SLX help texts (bnc#544907)
        # help = help_title + help_para1_openslx + help_para2_openslx + help_para4_openslx;
        # if (! Mode::normal()) help = help + help_para6_openslx;
        @help = Ops.add(
          Ops.add(Ops.add(@help_title, @help_para1), @help_para2),
          @help_para4
        )
        @help = Ops.add(@help, @help_para6) if !Mode.normal
      end

      @help = Ops.add(
        Ops.add(@help, Ops.get_string(@HELP, "localRegistrationChapter1", "")),
        Ops.get_string(@HELP, "localRegistrationChapter2", "")
      )

      #  further strings
      @checking = _("Checking...")
      @error = _("Error")
      @server_error = _("An error occurred while connecting to the server.")
      @details = _("Details...")
      @error_msg = _("Error")
      @starting_browser = _("Starting browser...")
      @error_target_init_failed = _(
        "Initialization failed.\nCan not interact with the package system."
      )
      @message_install_missing_packages = _(
        "In order to register properly the system\nneeds to install the following packages."
      )

      # other string variables
      @information_text = ""
      @error_msg_details = ""

      # strings for registration status
      @subscription_status_readable = {
        #translators: active - describes an 'active' subscription
        "ACTIVE"  => _(
          "active"
        ),
        #translators: expired - describes an 'expired' subscription
        "EXPIRED" => _(
          "expired"
        ),
        #translators: active - describes a 'returned' or a 'refunded' subscription
        "RMA"     => _(
          "returned or refunded"
        )
      }

      @subscription_type_readable = {
        #translators: full version - describes a subscription for a full product without limitation
        "FULL"        => _(
          "full version"
        ),
        #translators: evaluation - describes an evaluation subscription (limitations may be applied)
        "EVALUATION"  => _(
          "evaluation"
        ),
        #translators: full version - describes a provisional subscription (valid only for a short period of time)
        "PROVISIONAL" => _(
          "provisional"
        )
      }

      @registration_errorcode_readable = {
        # translators: short status message for the registration/subscription status, should be as short as possible
        "OK"                      => _(
          "Registration is successful."
        ),
        # translators: short status message for the registration/subscription status, should be as short as possible
        "ERR_SUB_EXP"             => _(
          "Subscription is expired."
        ),
        # translators: short status message for the registration/subscription status, should be as short as possible
        "ERR_SUB_EXP_alternative" => _(
          "Registration is expired."
        ),
        # translators: short status message for the registration/subscription status, should be as short as possible
        "ERR_NO_CODE"             => _(
          "Registration code is missing."
        ),
        # translators: short status message for the registration/subscription status, should be as short as possible
        "ERR_INV_CODE"            => _(
          "Registration code is invalid."
        ),
        # translators: short status message for the registration/subscription status, should be as short as possible
        "ERR_LOCKED"              => _(
          "Registration code does not match mail address."
        )
      }

      # translators: heading for the status of the registration AT a certain POINT in time (not a period), the status may have changed the other second
      @reg_stat_heading = "<p>" + _("Registration Status at: <b>%1</b>") + "</p>"
      # translators: heading for a list of products, 1: product name, 2: architecture (x86, x86_64, ppc,...), 3: release (CD, DVD,...)
      @reg_stat_product = _("Product: <b>%1</b> (%2, %3)")
      # translators: heading for the subscription (of a product): 1: status (active, expired,...), 2: type (full version, provisional,...)
      @reg_stat_subscription = _("Subscription: <b>%1</b> (%2)")
      # translators: heading for a (error) message of a subscription: 1: translated text
      @reg_stat_message = _("Message: %1")
      # translators: heading for the date of the expiry of a subscription
      @reg_stat_expiry = _("Expiry: %1")
      # translators: error message for the case that no registration status for any product is available
      @reg_stat_missing = "<p><b>" +
        _("No status information about registered products available.") + "</b></p>"

      # dialogs for the registration status
      @registration_status_missing_dialog = VBox(
        Label(Opt(:boldFont), _("Registration status is not available.")),
        ButtonBox(PushButton(Id(:close), Label.CloseButton))
      )




      # general dialogs

      # default is true, see statement in layout term
      @configure_status = true

      # --   MAIN (WIZARD) LAYOUT  --
      @sr_layout = nil

      @expertMenu = [
        Item(
          Id(:localRegistrationServer),
          Ops.get_string(@TXT, "localRegistrationServer", "")
        ),
        Item(Id(:showinfo), @nccc_privacy_detail)
      ]


      @sr_layout = HVSquash(
        VBox(
          Label(@nccc_heading), #,`PushButton(`id(`registration_status_with_repos), nccc_cur_reg_stat + " with repos" )
          #,`PushButton(`id(`registration_status_without_repos), nccc_cur_reg_stat + " without repos" )
          VSpacing(0.5),
          Frame(
            @title,
            RadioButtonGroup(
              Id(:sr_perform),
              MarginBox(
                2,
                0.5,
                VBox(
                  Left(
                    RadioButton(
                      Id(:noconfigure),
                      Opt(:notify),
                      @nccc_noconfigure
                    )
                  ),
                  Left(
                    RadioButton(
                      Id(:configure),
                      Opt(:notify),
                      @nccc_configure,
                      true
                    )
                  ),
                  Left(
                    Id(:includeinfo),
                    HBox(
                      HSpacing(3.0),
                      VBox(
                        VSpacing(0.5),
                        Left(Label(@nccc_sub_comment)),
                        Left(
                          CheckBox(
                            Id(:hwinfo),
                            Opt(:notify),
                            @nccc_sub_hwinfo,
                            Register.submit_hwdata
                          )
                        ),
                        Left(
                          CheckBox(
                            Id(:optional),
                            Opt(:notify),
                            @nccc_sub_optional,
                            Register.submit_optional
                          )
                        ),
                        Register.display_forcereg ?
                          Left(
                            CheckBox(
                              Id(:forcereg),
                              Opt(:notify),
                              @nccc_forcereg,
                              false
                            )
                          ) :
                          Empty(),
                        VSpacing(0.5),
                        # active in SLE products only
                        @IAMSLE ?
                          Left(
                            CheckBox(
                              Id(:regularly_run),
                              Opt(:notify),
                              @title_regularly_run,
                              Register.register_regularly
                            )
                          ) :
                          Empty(),
                        Right(
                          HBox(
                            @IAMSLE ?
                              MenuButton(_("Advanced"), @expertMenu) :
                              Empty()
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          ),
          VSpacing(0.4),
          PushButton(Id(:registration_status), @nccc_cur_reg_stat)
        )
      )


      @contents = VBox(VSpacing(0.5), @sr_layout, VSpacing(0.5))




      # --      SHOW INFO POPUP     --
      @showinformation = HBox(
        HSpacing(0.5),
        MinSize(
          75,
          22,
          VBox(
            Label(@transmit_info),
            RichText(Id(:information_text), @information_text),
            PushButton(Id(:info_close), Label.CloseButton)
          )
        ),
        HSpacing(0.5)
      )






      # --  MANUAL INTERACTION POPUP  --
      @manual_interaction = MinSize(
        70,
        25,
        HBox(
          VBox(
            Left(Label(Opt(:boldFont), @mi_required)),
            VSpacing(0.5),
            Left(Label(@mi_start_browser)),
            Left(Label(@mi_needinfo)),
            RichText(Id(:needinfo), ""),
            ButtonBox(
              PushButton(Id(:start_browser), Opt(:okButton), @mi_browser_btn),
              HSpacing(3),
              PushButton(Id(:cancel), Opt(:cancelButton), Label.CancelButton)
            )
          )
        )
      ) #`HBox(




      # --      CCC CONFLICT POPUP      --
      @ccc_conflict = VBox(
        Left(Label(Opt(:boldFont), @title)),
        VSpacing(0.5),
        Left(Label(@conflict_need_info)),
        PushButton(Id(:ok), Label.OKButton)
      )



      # --      CCC ERROR POPUP      --
      @error_message = VBox(
        Left(Label(Opt(:boldFont), @error)),
        VSpacing(0.5),
        Left(Label(Id(:err_description), @server_error)),
        HBox(
          HWeight(1, PushButton(Id(:back), Label.BackButton)),
          HSpacing(3),
          # reactivated skipping the registration (#240174)
          HWeight(1, PushButton(Id(:skip), Label.SkipButton)),
          HSpacing(3),
          HWeight(1, PushButton(Id(:err_detail), @details))
        )
      )



      # --      CCC ERROR POPUP      --
      @error_message_details = MinSize(
        60,
        20,
        VBox(
          Left(Label(Opt(:boldFont), @error_msg)),
          VSpacing(0.5),
          RichText(Id(:errordetail), ""),
          PushButton(Id(:ok), Label.OKButton)
        )
      )



      # --      CCC ERROR POPUP PLAINTEXT     --
      @error_message_details_pt = MinSize(
        60,
        20,
        VBox(
          Left(Label(Opt(:boldFont), @error_msg)),
          VSpacing(0.5),
          RichText(Id(:errordetail), Opt(:plainText), ""),
          PushButton(Id(:ok), Label.OKButton)
        )
      )


      # --    SUCCESS DETAILS     --
      @nccc_success_detail = MinSize(
        60,
        7,
        VBox(
          Left(Label(Opt(:boldFont), @success_detail_label)),
          VSpacing(0.5),
          RichText(Id(:success_detail_richtext), Opt(:plainText), ""),
          PushButton(Id(:ok), Label.OKButton)
        )
      )

      # ----------------------------------- END FUNCTIONS -------------------------------------------------------------


      # check if we are in installation workflow or running independently
      Wizard.CreateDialog if Mode.normal

      @enable_back = GetInstArgs.enable_back
      # we always need the next button
      Wizard.SetContents(@title, @contents, @help, @enable_back, true)
      Wizard.SetTitleIcon("yast-product-registration") # (#211552)

      #y2debug ("%1", UI::DumpWidgetTree());


      return :auto if !Register.iamroot


      @loopend = false
      @ret = nil
      @SRstatus = nil
      @manual_interaction_overview = ""
      @xenType = nil
      begin
        @ret = Wizard.UserInput

        if @ret == :abort
          break if Mode.normal
          break if Popup.ConfirmAbort(:incomplete)
        elsif @ret == :help
          Wizard.ShowHelp(@help)
        elsif @ret == :configure || @ret == :noconfigure
          @configure_status = Convert.to_boolean(
            UI.QueryWidget(Id(:configure), :Value)
          )
        elsif @ret == :hwinfo || @ret == :optional || @ret == :forcereg ||
            @ret == :regularly_run
          Register.submit_hwdata = Convert.to_boolean(
            UI.QueryWidget(Id(:hwinfo), :Value)
          )
          Register.submit_optional = Convert.to_boolean(
            UI.QueryWidget(Id(:optional), :Value)
          )
          Register.force_registration = Convert.to_boolean(
            UI.QueryWidget(Id(:forcereg), :Value)
          )
          if @IAMSLE
            Register.register_regularly = Convert.to_boolean(
              UI.QueryWidget(Id(:regularly_run), :Value)
            )
          end
        elsif @ret == :localRegistrationServer
          if registrationServerSettings
            Register.force_new_reg_url = true
            if Register.setupRegistrationServer(nil) != :ok
              @configure_status = false
            end
            Register.force_new_reg_url = false
          end
        elsif @ret == :showinfo
          @information_text = Register.suseRegisterListParams

          if @information_text != ""
            UI.OpenDialog(@showinformation)
            UI.ChangeWidget(Id(:information_text), :Value, @information_text)
            @info_ret = nil
            begin
              @info_ret = UI.UserInput
              if Ops.is_string?(@info_ret)
                launchBrowser(Convert.to_string(@info_ret))
              end
            end until @info_ret == :info_close || @info_ret == :cancel

            UI.CloseDialog
          else
            @error_msg_details = YSR.get_errormsg
            report_error
            @error_msg_details = ""
          end
        #else if (ret == `registration_status_with_repos)
        #{
        #    show_registration_status($[`repos : ["added service nu_novell_com", "SLE-11-SP2 (nu_novell_com)", "SLE-11-SP2-SDK (nu_novell_com)", "SLE-11-SP2-Updates (nu_novell_com)"]]);
        #}
        #else if (ret == `registration_status_without_repos)
        #{
        #    show_registration_status($[ `repos : [] ]);
        #}
        elsif @ret == :registration_status
          show_registration_status({})
        elsif @ret == :next
          if @configure_status == true
            if @IAMSLE && @xenType == nil
              # once checking for XEN    (bnc#418287)
              @xenType = Register.xenType

              if @xenType == :xen0
                @installPackage = "xen-tools"
                if !Package.Installed(@installPackage)
                  Builtins.y2milestone(
                    "Xen dom0 detected. Asking the user if the following packages should be installed: %1",
                    @installPackage
                  )
                  Package.InstallMsg(
                    @installPackage,
                    _(
                      "Xen Dom0 detected. The following package needs to be installed."
                    )
                  )
                else
                  Builtins.y2milestone(
                    "All needed packages are already installed: %1",
                    @installPackage
                  )
                end
              elsif @xenType == :xenU
                @installPackage = "xen-tools-domU"
                @removePackage = "xen-tools"

                @xenDomU = _("Xen DomU detected.")
                @installMsg = Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(@xenDomU, "<br>"),
                      _("The following package needs to be installed.")
                    ),
                    "<br>"
                  ),
                  Builtins.sformat("%1", @installPackage)
                ) #  (bnc#444638)
                @removeMsg = Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(
                        Ops.add(
                          Ops.add(@xenDomU, "<br>"),
                          Builtins.sformat(
                            _(
                              "To count this installation correctly the package %1 needs to be installed."
                            ),
                            @installPackage
                          )
                        ),
                        "<br>"
                      ),
                      _(
                        "Therefore the following package needs to be removed first."
                      )
                    ),
                    "<br>"
                  ),
                  Builtins.sformat("%1", @removePackage)
                ) #  (bnc#444638)


                Package.RemoveMsg(@removePackage, @removeMsg)

                if !Package.Installed(@removePackage)
                  if Package.InstallMsg(@installPackage, @installMsg)
                    Builtins.y2milestone(
                      "Sucessfully installed: %1",
                      @installPackage
                    )
                  else
                    Builtins.y2error("Could not install: %1", @installPackage)
                  end
                else
                  Builtins.y2error(
                    "In a Xen DomU package %1 is installed rather than %2. Registration will continue nevertheless.",
                    @removePackage,
                    @installPackage
                  )
                  Popup.Notify(
                    Ops.add(
                      Ops.add(
                        Ops.add(
                          Ops.add(@xenDomU, "\n"),
                          Builtins.sformat(
                            _(
                              "The package %1 should have been installed and %2 removed."
                            ),
                            @installPackage,
                            @removePackage
                          )
                        ),
                        "\n"
                      ),
                      _(
                        "Registration will continue now although the registration server may miscount this installation."
                      )
                    )
                  )
                end
              elsif @xenType == nil
                Builtins.y2error(
                  "Detecting XEN failed. Assuming XEN is disabled. Maybe the registration will not count this machine correctly."
                )
                @xenType = :unknown
              end
            end

            # call suseRegister
            @SRstatus = Register.suseRegister(nil)

            # error code 4: needinfo - manual interaction
            if @SRstatus == 4
              # get the details overview
              @manual_interaction_overview = YSR.get_registerReadableText # (bnc#435869)
              if @manual_interaction_overview == nil
                @manual_interaction_overview = ""
              end

              UI.OpenDialog(@manual_interaction)
              UI.SetFocus(Id(:start_browser))
              UI.ChangeWidget(
                Id(:needinfo),
                :Value,
                @manual_interaction_overview
              )
              @mi_ret = nil
              @mi_loopend = false
              @recheck = true
              @browserrun = true
              begin
                @recheck = true
                @mi_ret = UI.UserInput
                if @mi_ret == :start_browser
                  # now we launch the browser
                  UI.ChangeWidget(Id(:needinfo), :Value, @starting_browser)
                  @browserURL = YSR.get_manualURL
                  @browserrun = launchBrowser(@browserURL)
                  # deactivate force_registration after each suse_register call (#bugNo.)
                  Register.force_registration = false
                elsif @mi_ret == :cancel
                  @recheck = false
                  @mi_loopend = true
                elsif Ops.is_string?(@mi_ret)
                  # launch browser
                  @browserrun = launchBrowser(Convert.to_string(@mi_ret))
                  @recheck = false
                end


                if @recheck && @browserrun
                  # show the user, that we are doing something
                  UI.ChangeWidget(Id(:needinfo), :Value, @checking)

                  @SRstatus = Register.suseRegister(nil)

                  if @SRstatus == 0 || @SRstatus == 3
                    # error 0: everything is done, quit
                    # error 3: madatory data conflict - handle outside of manual interaction
                    @mi_loopend = true
                  elsif @SRstatus == 4
                    # still needinfo, change displayed information and stay in manual interaction
                    @manual_interaction_overview = YSR.get_registerReadableText # (bnc#435869)
                    UI.ChangeWidget(
                      Id(:needinfo),
                      :Value,
                      @manual_interaction_overview
                    )
                  else
                    # unknown error, let the user find an exit :)
                    @mi_loopend = true
                  end
                end


                if !@browserrun
                  Builtins.y2error(
                    "Registration can not finish with manual interaction because no webbrowser was found."
                  )
                  Popup.Message(@no_browser_msg)
                  @mi_loopend = true
                end
              end until @mi_loopend

              # we are done with manual interaction
              UI.CloseDialog

              @configure_status = false if @mi_ret == :cancel
            end



            # no NO MORE suse_register calls below this line !!
            # ---------------------------------------------------------------------------------


            #  handle error codes from FIRST suse_register call AND from manual interaction
            if @SRstatus == 3
              # error code 3 means:
              # conflict between transmitted data and data to be transmit according to customer contract
              # hwconfig is needed
              UI.OpenDialog(@ccc_conflict)
              UI.SetFocus(Id(:ok))
              UI.UserInput
              UI.CloseDialog
              Register.submit_hwdata = true
            end


            # error code 0 means: everything is OK
            if @SRstatus == 0
              # get the taskList
              @taskList = YSR.getTaskList
              @repoSummary = []

              if @taskList != {}
                @oldMessage = _("Setting up online update source...")
                @newMessage = _("Updating software repositories...")
                UI.OpenDialog(VBox(Label(@newMessage)))

                # add/delete/change repositories
                @repoSummary = Register.updateSoftwareRepositories(
                  @taskList,
                  true
                )

                UI.CloseDialog
              end

              # show new status overview and the added repos
              show_registration_status({ :repos => @repoSummary })

              # we are done - finally
              @loopend = true
            end


            #  show a message when there are no products to register
            if @SRstatus == 100 || @SRstatus == 101
              Popup.Message(@no_product_msg)
              Builtins.y2error(
                "No products to be registered. SuseRegister returned with exit code: %1",
                @SRstatus
              )
              @loopend = true
            end


            # error handling - no browser available for interactive mode
            if @SRstatus == 198
              Popup.Message(@no_browser_msg)
              Builtins.y2error(
                "No browser found to display registration website. SuseRegister returned with exit code: %1",
                @SRstatus
              )
              @loopend = true
            end


            # error handling - initialization of target failed
            if @SRstatus == 113
              Popup.Message(@error_target_init_failed)
              Builtins.y2error("Initialization of target failed.")
              @loopend = true
            end


            # handle any other error codes
            if Builtins.contains(
                [0, 1, 3, 4, 100, 101, 113, 198, 199],
                @SRstatus
              ) == false
              Builtins.y2error(
                "An error occurred. SuseRegister exit code (or internal error status) is: %1",
                @SRstatus
              )
              # display error message
              @error_msg_details = YSR.get_errormsg
              report_error
              @error_msg_details = ""
            end 

            #                DOCUMENTATION OF ERROR CODES
            #                exit codes of suseRegister:
            #                * 0:   everything ok - we are done
            #                * 1:   needinfo auto - internal status, should create a loop until it is != 1
            #                * 2:   error
            #                * 3:   conflict - data sent is in conflict with the data needed according to contract
            #                * 4:   needinfo browser - manual interaction is required
            #                * 100: no product found that can be registered
            #                * 101: no product found that can be registered
            #
            #                internal codes:
            #                # relating to the registration process
            #                * 111: a generic unknown error uccurred during a SuseRegister call
            #                * 112: the initialization of SuseRegister failed; no special message is used for that though
            #                * 113: the initialization if the target failed - no interaction with the package system possible
            #
            #                # generic errors/failures
            #                * 198: the system did not find any browser to let the user perform the manual interaction part of the registration
            #                * 199: failed to start Source Manager
          else
            # skipping - no online update!!
            @loopend = true
            @ret = :skip
          end
        end

        # update main widget settings - they may have changed
        if @configure_status
          UI.ChangeWidget(Id(:configure), :Value, true)
        else
          UI.ChangeWidget(Id(:noconfigure), :Value, true)
        end

        # gray out if later is selected (#178042)
        UI.ChangeWidget(Id(:includeinfo), :Enabled, @configure_status)

        UI.ChangeWidget(Id(:hwinfo), :Value, Register.submit_hwdata)
        # (#165841)
        if Register.display_forcereg
          UI.ChangeWidget(Id(:forcereg), :Value, Register.force_registration)
        end
      end until @loopend || @ret == :back



      if Mode.normal
        Wizard.CloseDialog
      else
        if @ret == :skip
          # skipping suse register - no online update
          Internet.do_you = false
          # disable regular registrations when registration was skipped initially (#366687)
          Register.register_regularly = false
          @ret = :next
        else
          # ok we can do online update
          Internet.do_you = true
        end
      end

      # always return a proper return value
      if !Builtins.contains([:next, :abort, :back], Convert.to_symbol(@ret))
        @ret = :next
      end

      # Register::finish mandatory as well - do not remove (#366687)
      Register.finish

      Convert.to_symbol(@ret)
    end

    def registration_status_dialog(with_repo)
      VBox(
        MinSize(
          75,
          10,
          VBox(
            Label(@nccc_cur_reg_stat),
            RichText(Id(:information_text_status), "")
          )
        ),
        with_repo ?
          MinSize(
            75,
            4,
            VBox(
              Label(@success_detail_label),
              RichText(Id(:information_text_repos), Opt(:plainText), "")
            )
          ) :
          Empty(),
        ButtonBox(PushButton(Id(:ok), Label.OKButton))
      )
    end




    # --       SUCCESS MESSAGE    --
    def registration_status_short_dialog(message)
      inner = VBox(
        Left(Label(Opt(:boldFont), @title)),
        VSpacing(0.5),
        Left(Label(message)),
        VSpacing(0.5),
        HBox(
          HWeight(1, PushButton(Id(:ok), Label.OKButton)),
          HSpacing(3),
          HWeight(1, PushButton(Id(:details), @details))
        )
      )
      spacing = 0.5
      VBox(
        VSpacing(spacing),
        HBox(HSpacing(spacing), inner, HSpacing(spacing)),
        VSpacing(spacing)
      )
    end



    # ---------------------------------- LOCAL FUNCTIONS ------------------------------------------------------------


    def report_error
      # function to display an error message
      # and offer a detailled view of the error message

      Builtins.y2error(
        "Registration is reporting an error to the user: %1",
        @error_msg_details
      )

      UI.OpenDialog(@error_message)
      UI.SetFocus(Id(:skip))
      _retry = nil
      begin
        _retry = Convert.to_symbol(UI.UserInput)

        if _retry == :skip
          @configure_status = false
        elsif _retry == :err_detail
          # switch to plaintext if error output is one or two lines (#239570)
          if Builtins.contains(
              [0, 1],
              Builtins.size(Builtins.splitstring(@error_msg_details, "\n"))
            )
            UI.OpenDialog(@error_message_details)
          else
            UI.OpenDialog(@error_message_details_pt)
          end
          UI.ChangeWidget(Id(:errordetail), :Value, @error_msg_details)
          UI.UserInput
          UI.CloseDialog
        end
      end until Builtins.contains([:skip, :back, :abort, :cancel], _retry)

      UI.CloseDialog
      true
    end


    def su_exec(user, group, command)
      # introduce cleanup function to also cleanup the xauth entry (bnc#702638)
      exec = Builtins.sformat(
        "\n" +
          "#!/bin/bash -x\n" +
          "\n" +
          "user=%1\n" +
          "group=%2\n" +
          "cmd=\"%3\"\n" +
          "\n" +
          "fakehome=/var/lib/YaST2/$user-fakehome\n" +
          "umask 0077\n" +
          "\n" +
          "XA=/root/.xauth\n" +
          "mkdir -p $XA\n" +
          "DELETEXAEXPORT=no\n" +
          "[ ! -e $XA/export ] && DELETEXAEXPORT=yes\n" +
          "grep ^$user$ $XA/export >/dev/null 2>&1  || echo $user >> $XA/export\n" +
          "\n" +
          "mkdir -p $fakehome\n" +
          "chmod 700 $fakehome\n" +
          "tmp=$(mktemp $fakehome/.Xauthority.XXXXXX) || exit 1\n" +
          "chmod 600 $tmp\n" +
          "chown $user:$group $tmp $fakehome\n" +
          "\n" +
          "\n" +
          "function cleanup\n" +
          "{\n" +
          "  if [ \"x$DELETEXAEXPORT\" = \"xyes\" ]\n" +
          "  then\n" +
          "    rm -f $XA/export\n" +
          "  else\n" +
          "    sed -i --follow-symlinks \"/^$user$/d\" $XA/export\n" +
          "  fi\n" +
          "  \n" +
          "  rm -rf $fakehome\n" +
          "}\n" +
          "\n" +
          "\n" +
          "trap \"cleanup\" EXIT INT HUP TERM\n" +
          "\n",
        user,
        group,
        command
      )


      # screen jail can be removed - no longer used (#367719)
      # create a script to run a system call as different user
      # thanks to werner (script)
      # unset DESKTOP_SESSION : (#207332)
      # gracefully handle situations where hostname errors with -f or -s
      # thus only call 'hostname' and strip the name via shell (bnc#179614), (bnc#718334)
      if !@textmode
        exec = Ops.add(
          exec,
          "\n" +
            "if test \"${DISPLAY%:*}\" = \"localhost\" ; then\n" +
            "    hname=$(hostname)\n" +
            "    hname=${hname%%.*}\n" +
            "    disp=${hname}/unix:${DISPLAY#*:}\n" +
            "else\n" +
            "    disp=\"${DISPLAY}\"\n" +
            "fi\n" +
            "\n" +
            "unset DESKTOP_SESSION\n" +
            "\n" +
            ": ${XAUTHORITY:=$HOME/.Xauthority}\n" +
            "if test ! -e $XAUTHORITY ; then\n" +
            "    su -s /bin/bash -- $user -c \"cd; $cmd\"\n" +
            "    exit 0\n" +
            "fi\n" +
            "exec 4< ${XAUTHORITY}\n" +
            "su -s /bin/bash -- $user -c \"xauth -qif <(cat 0<&4) extract - $disp | xauth -qf $tmp merge -\"\n" +
            "exec 4<&-\n" +
            "\n" +
            "su -s /bin/bash -- $user -c \"cd; XAUTHORITY=$tmp $cmd\"\n" +
            "\n" +
            "exit 0"
        )
      else
        # screen jail can be removed - no longer used (#367719)
        exec = Ops.add(exec, "su -s /bin/bash -- $user -c \"cd; $cmd\"")
      end

      Builtins.y2milestone("using su_exec to launch browser")

      exec
    end



    def browser_command(url)
      # create the command string to launch a browser
      bcmd = "/bin/false"
      cmd_ok = false
      required_package = ""
      checkBinary = ""

      if @textmode
        bcmd = " w3m "
        required_package = "w3m"
        checkBinary = "/usr/bin/w3m"
      else
        bcmd = " MOZ_DISABLE_PANGO=1 /usr/bin/xulrunner /usr/share/YaST2/yastbrowser/application.ini -url "
        required_package = "mozilla-xulrunner190"
        checkBinary = "/usr/bin/xulrunner"
      end

      # (bnc#443781)
      cmd_ok = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("test -x %1", checkBinary)
        )
      ) == 0 ? true : false
      if !cmd_ok
        if !Package.Installed(required_package)
          Package.InstallAllMsg([required_package], nil)
        end
        cmd_ok = Convert.to_integer(
          SCR.Execute(
            path(".target.bash"),
            Builtins.sformat("test -x %1", checkBinary)
          )
        ) == 0 ? true : false
      end

      if !cmd_ok
        Builtins.y2error(
          "No browser found for interactive registration. A needed package was not installed: %1",
          required_package
        )
        return "nobrowser"
      else
        Builtins.y2milestone(
          "A browser was found to show the interactive registration: %1",
          required_package
        )
      end


      # add url to browser command
      bcmd = Ops.add(Ops.add(Ops.add(bcmd, "'"), url), "'")

      if Register.use_proxy
        # (#165891) - (#208651) fixed in Register.ycp
        bcmd = Ops.add(
          Ops.add(Ops.add(" http_proxy='", Register.http_proxy), "' "),
          bcmd
        )
        bcmd = Ops.add(
          Ops.add(Ops.add(" https_proxy='", Register.https_proxy), "' "),
          bcmd
        )
      end

      # add su call to not run a browser as root during installation
      bcmd = su_exec("suse-ncc", "suse-ncc", bcmd)

      bcmd
    end


    def launchBrowser(url)
      retval = false
      Builtins.y2milestone(
        "Just about to start a browser for manual interaction in registration."
      )
      # check for valid url
      parsed = URL.Parse(url)
      if parsed == {}
        Builtins.y2error(
          "The URL to open in the registration browser has an invalid format: %1",
          parsed
        )
        return false
      end
      # no rebuild of the url - parser seems to only parse one parameter in URL

      uri = String.FirstChunk(url, "\n") # (#167225)
      # get command to run correct browser and execute it
      command = browser_command(uri)
      if command == "nobrowser"
        Builtins.y2error(
          "Could not find a browser to display the registration website."
        )
        return false
      end


      if @textmode
        Builtins.y2milestone("Launching textmode browser with: %1", command)
        retval = UI.RunInTerminal(command) == 0 ? true : false
      else
        Builtins.y2milestone("Launching graphical borwser with: %1", command)
        retval = Convert.to_integer(SCR.Execute(path(".target.bash"), command)) == 0 ? true : false
      end

      Builtins.y2milestone(
        "The registration browser returned with error code: %1",
        retval
      )

      UI.RedrawScreen
      retval
    end



    def registrationServerSettings
      Builtins.y2milestone(
        "Asking the user for custom registration server settings."
      )
      curRegURL = Register.smt_server
      curRegURL = "https://" if curRegURL == nil
      curRegCert = Register.smt_server_cert
      curRegCert = "" if curRegCert == nil

      askForRegSettings = VBox(
        VSpacing(0.5),
        Label(Ops.get_string(@TXT, "localRegistrationServer", "")),
        VSpacing(1.5),
        InputField(
          Id(:newRegistrationServer),
          Ops.get_string(@TXT, "registrationServer", ""),
          curRegURL
        ),
        VSpacing(0.5),
        InputField(
          Id(:newRegistrationServerCert),
          Ops.get_string(@TXT, "serverCACertificateLocation", ""),
          curRegCert
        ),
        VSpacing(1),
        ButtonBox(
          PushButton(Id(:ok), Label.OKButton),
          PushButton(Id(:cancel), Label.CancelButton)
        )
      )

      UI.OpenDialog(askForRegSettings)

      ret = nil
      status = false

      while true
        ret = UI.UserInput

        if ret == :cancel || ret == :abort
          status = false
          break
        elsif ret == :ok
          curRegURL = Convert.to_string(
            UI.QueryWidget(Id(:newRegistrationServer), :Value)
          )
          curRegCert = Convert.to_string(
            UI.QueryWidget(Id(:newRegistrationServerCert), :Value)
          )

          # check urls for sanity
          parsed = URL.Parse(curRegURL)
          if parsed == nil || parsed == {} ||
              Ops.get_string(parsed, "scheme", "") != "https"
            Builtins.y2error(
              "The selected registration URL has an invalid format: %1",
              parsed
            )
            Popup.Message(Ops.get_string(@TXT, "urlHasToBeHttps", ""))
            next
          else
            Register.smt_server = curRegURL
            Register.smt_server_cert = curRegCert
            Builtins.y2milestone("New registration server: %1", curRegURL)
            Builtins.y2milestone(
              "New registration server CA certificate location: %1",
              curRegCert
            )
            status = true
            break
          end
        end
      end

      UI.CloseDialog
      status
    end

    # refresh the current registration status
    # return true if a correct and parsable status is present and false otherwise
    def refresh_registration_status
      @registration_status = RegistrationStatus.ParseStatusXML(
        RegistrationStatus.RegFile
      )
      Builtins.y2milestone(
        "Current registration status: %1",
        @registration_status
      )
      Ops.get_string(@registration_status, "__parser_status", "1") == "0" ? true : false
    end

    def overall_registration_status
      pall = Ops.get_map(@registration_status, "products", {})
      pnum_all = Builtins.size(pall)
      pnum_ok = 0
      pnum_err = 0
      Builtins.foreach(pall) do |k, m|
        m_errorcode = Builtins.toupper(
          Builtins.sformat("%1", Ops.get_string(m, "errorcode", "NOTOK"))
        )
        m_result = Builtins.tolower(
          Builtins.sformat("%1", Ops.get_string(m, "result", "error"))
        )
        if m_errorcode != "OK" || m_result != "success"
          pnum_err = Ops.add(pnum_err, 1)
        else
          pnum_ok = Ops.add(pnum_ok, 1)
        end
      end
      ret = :error
      if Ops.greater_than(pnum_all, 0) && pnum_ok == pnum_all && pnum_err == 0
        ret = :success
      elsif Ops.greater_than(pnum_all, 0) && Ops.greater_than(pnum_err, 0) &&
          Ops.less_than(pnum_err, pnum_all) &&
          Ops.add(pnum_err, pnum_ok) == pnum_all
        ret = :partial
      elsif pnum_all == 0
        ret = :noproducts
      else
        ret = :error
      end

      ret
    end

    def registration_status_formatted(format)
      rs = ""
      if format == :simple_html
        rs = Ops.add(
          rs,
          Builtins.sformat(
            @reg_stat_heading,
            Ops.get_string(@registration_status, "_generated_fmt", "")
          )
        )
        if Ops.is_map?(Ops.get(@registration_status, "products")) &&
            Ops.greater_than(
              Builtins.size(Ops.get_map(@registration_status, "products", {})),
              0
            )
          rs = Ops.add(rs, "<p><ul>")
          Builtins.foreach(Ops.get_map(@registration_status, "products", {})) do |prodkey, prod|
            sub = Ops.get_map(prod, "subscription", {})
            prodinfo = Ops.get_map(prod, "_productinfo", {})
            sub_status = Ops.get(
              @subscription_status_readable,
              Builtins.toupper(Ops.get_string(sub, "status", "")),
              ""
            )
            sub_type = Ops.get(
              @subscription_type_readable,
              Builtins.toupper(Ops.get_string(sub, "type", "")),
              ""
            )
            sub_expiry = Builtins.sformat(
              "%1",
              Ops.get_string(sub, "_expiration_fmt", "")
            )
            errorcode = Builtins.toupper(Ops.get_string(prod, "errorcode", ""))
            product_name_version = Builtins.sformat(
              "%1 %2",
              Ops.get_string(prod, "product", ""),
              Ops.get_string(prod, "version", "")
            )
            if Builtins.haskey(prodinfo, "summary")
              product_name_version = Ops.get_string(
                prodinfo,
                "summary",
                product_name_version
              )
            end
            rs = Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(rs, "<li>"),
                      Builtins.sformat(
                        @reg_stat_product,
                        product_name_version,
                        Ops.get_string(prod, "arch", ""),
                        Ops.get_string(prod, "release", "")
                      )
                    ),
                    sub_status != "" && sub_type != "" ?
                      Ops.add(
                        "<br />",
                        Builtins.sformat(
                          @reg_stat_subscription,
                          sub_status,
                          sub_type
                        )
                      ) :
                      ""
                  ),
                  errorcode != "OK" ?
                    Ops.add(
                      "<br />",
                      Builtins.sformat(
                        @reg_stat_message,
                        Ops.get(@registration_errorcode_readable, errorcode, "")
                      )
                    ) :
                    ""
                ),
                sub_expiry != "" ?
                  Ops.add(
                    "<br />",
                    Builtins.sformat(@reg_stat_expiry, sub_expiry)
                  ) :
                  ""
              ),
              "</li>"
            )
          end
          rs = Ops.add(rs, "</ul></p>")
        else
          rs = Ops.add(rs, @reg_stat_missing)
        end
      else
        rs = Builtins.sformat("%1", @registration_status)
      end

      rs
    end

    def show_registration_status(options)
      options = deep_copy(options)
      # make a refresh, no matter what might have happened before
      have_status = refresh_registration_status
      if !have_status
        UI.OpenDialog(@registration_status_missing_dialog)
        UI.UserInput
        UI.CloseDialog
        return
      end

      changed_repos = @nccc_no_source_changes
      show_repos = Builtins.haskey(options, :repos)
      if show_repos &&
          Ops.is(Ops.get_list(options, :repos, []), "list <string>") &&
          Ops.greater_than(Builtins.size(Ops.get_list(options, :repos, [])), 0)
        changed_repos = Builtins.mergestring(
          Ops.get_list(options, :repos, []),
          "\n"
        )
      end

      # process registration_status
      reg_overall = overall_registration_status
      reg_message = {
        :success    => @nccc_success_msg,
        # translators: failed partially - means: some products were registered, some were not.
        :partial    => _(
          "Registration failed partially."
        ),
        # translators: failed - means: No products were registered.
        :error      => _(
          "Registration failed."
        ),
        # translators: No products found to be registered - means: None of the currently installed products needs (or can be) registered.
        :noproducts => _(
          "No products found to be registered."
        )
      }
      # translators: unknown status - meaning: fallback message if the the registration status could not be computed
      reg_status_unknown = _("unknown status")
      UI.OpenDialog(
        registration_status_short_dialog(
          Ops.get(reg_message, reg_overall, reg_status_unknown)
        )
      )
      UI.SetFocus(Id(:ok))

      sret = nil
      begin
        sret = Convert.to_symbol(UI.UserInput)
        if sret == :details
          UI.OpenDialog(registration_status_dialog(show_repos))
          UI.SetFocus(Id(:ok))
          UI.ChangeWidget(
            Id(:information_text_status),
            :Value,
            registration_status_formatted(:simple_html)
          )
          if show_repos
            UI.ChangeWidget(Id(:information_text_repos), :Value, changed_repos)
          end
          UI.UserInput
          UI.CloseDialog
        end
      end until sret == :ok || sret == :close
      UI.CloseDialog

      nil
    end
  end
end

Yast::InstSuseRegisterClient.new.main
