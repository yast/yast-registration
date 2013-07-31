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
# File:	modules/Register.ycp
# Package:	Installation
# Summary:	Registration related stuff
# Authors:	J. Daniel Schmidt <jdsn@suse.de>
#
# $Id: Register.ycp 1 2005-03-13 08:45:05Z jdsn $
require "yast"

module Yast
  class RegisterClass < Module
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "registration"

      Yast.import "FileUtils"
      Yast.import "Mode"
      Yast.import "String"
      Yast.import "Misc"
      Yast.import "Stage"
      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "URL"
      Yast.import "Linuxrc"
      Yast.import "YSR"
      Yast.import "ProductFeatures"
      Yast.import "SourceManager"
      Yast.import "Installation"
      Yast.import "RegisterCert"
      Yast.import "Arch"

      # --------------------------------------------------------------
      # START: Locally defined data
      # --------------------------------------------------------------

      @services_file = Builtins.sformat(
        "%1/update_services",
        SCR.Read(path(".target.tmpdir"))
      )
      @isInitializedSR = false
      @isInitializedTarget = false
      @contextDataSR = nil
      @argsDataSR = nil
      @initialSRstatus = nil
      @repoUpdateSuccessful = true # flag success of repo changes for saveLastZmdConfig (bnc#435696)

      # ------------------------------------------------------------------
      # END:   Locally defined data
      # ------------------------------------------------------------------

      # --------------------------------------------------------------
      # START: Globally defined data, access via Register::<variable>
      # --------------------------------------------------------------

      @autoYaSTModified = false
      @do_registration = false
      @iamroot = false

      @submit_optional = false
      @submit_hwdata = false
      @force_registration = false
      @display_forcereg = true
      @register_regularly = false # (FATE #301822)
      @disable_w3m = false
      @use_proxy = false
      @http_proxy = ""
      @https_proxy = ""
      @smt_server = "" # (FATE #302966)
      @smt_server_cert = "" # (FATE #302966)
      @force_new_reg_url = false

      @registration_data = {}
    end

    # ------------------------------------------------------------------
    # END: Globally defined data, access via Register::<variable>
    # ------------------------------------------------------------------


    # ------------------------------------------------------------------
    # START: Locally defined functions
    # ------------------------------------------------------------------


    # amIroot()
    #
    # checks if running as root
    # returns true if running as root - else returns false
    #
    def amIroot
      # check if we are root
      userid = Convert.convert(
        SCR.Execute(path(".target.bash_output"), "id -u"),
        :from => "any",
        :to   => "map <string, any>"
      )
      Builtins.y2milestone("running with user id %1", userid)
      String.FirstChunk(Ops.get_string(userid, "stdout", "1"), "\n") == "0" ? true : false
    end



    # mountFloppy()
    #
    # mount a floppy disk
    # @return map with status information
    #
    def mountFloppy
      # floppy mount support (FATE #303335)
      drives = Convert.to_list(SCR.Read(path(".probe.floppy")))

      return { "mounted" => false } if Builtins.size(drives) == 0

      fddevice = Ops.get_string(drives, [0, "dev_name"], "/dev/fd0")
      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      tmpdir = "/tmp" if tmpdir == nil
      mpoint = Ops.add(tmpdir, "/fd")

      # create mount point directory
      SCR.Execute(path(".target.mkdir"), mpoint)

      Builtins.y2milestone(
        "Trying to mount %1 as floppy drive to load the SMT certificate file from.",
        fddevice
      )

      result = Convert.to_boolean(
        SCR.Execute(path(".target.mount"), [fddevice, mpoint], "-o ro")
      )

      { "mounted" => result, "mpoint" => mpoint, "device" => fddevice }
    end



    # umountFloppy()
    #
    # umount a floppy disk
    # @return void
    #
    def umountFloppy(mpoint)
      return if mpoint == nil || mpoint == ""
      SCR.Execute(path(".target.umount"), mpoint)

      nil
    end


    # certificateError()
    #
    # report error messages if SMT certificate file is not found
    # @return symbol yes, no or retry
    #
    def certificateError(heading, type)
      heading = _("Unknown error") if heading == nil || heading == ""

      errorrMessage = ""
      question = _("Do you want to skip registration?")
      otherwise = Builtins.sformat(
        _(
          "If you select %1, registration will most likely fail.\n" +
            "You can copy the certificate file to the system manually\n" +
            "and then specify its path by choosing %2.\n"
        ),
        Builtins.deletechars(Label.ContinueButton, "&"),
        Builtins.deletechars(Label.FileName, "&")
      )
      errorMessage = ""

      if type == :floppy
        errorMessage = _(
          "Could not load the SMT certificate file from floppy disk."
        )
      elsif type == :url
        errorMessage = _(
          "Could not download the SMT certificate file from specified URL."
        )
      elsif type == :file
        errorMessage = _(
          "Could not find the SMT certificate file in specified path."
        )
      else
        errorMessage = _(
          "Unknown error occurred while retrieving SMT certificate file."
        )
      end

      errorMessage = Ops.add(
        Ops.add(Ops.add(Ops.add(errorMessage, "\n\n"), question), "\n\n"),
        otherwise
      )
      Popup.AnyQuestion3(
        heading,
        errorMessage,
        _("Skip"),
        Label.ContinueButton,
        Label.FileName,
        :focus_yes
      )
    end





    # suseRegisterURL()
    #
    # get or set the suseRegisterURL
    # @return current url
    def suseRegisterURL(url)
      # nil, empty string, unparsable urls and non-https urls as parameter means 'get url' else 'set url'

      cururl = nil
      urlmap = {}
      suseRegisterConf = "/etc/suseRegister.conf"

      SCR.RegisterAgent(
        path(".temporary_suseregister_agent"),
        term(
          :ag_ini,
          term(
            :IniAgent,
            suseRegisterConf,
            {
              "options"  => [
                "line_can_continue",
                "global_values",
                "join_multiline",
                "comments_last",
                "flat"
              ],
              "comments" => ["^[ \t]*#.*$", "^[ \t]*$"],
              "params"   => [
                {
                  "match" => [
                    "([a-zA-Z0-9_-]+)[ \t]*=[ \t]*([^ \t]*)",
                    "%s = %s"
                  ]
                }
              ]
            }
          )
        )
      )

      # in case the smt server was already changed do not change it again (to support mobile PCs in different environments)
      mod = Convert.to_string(
        SCR.Read(path(".temporary_suseregister_agent.smturlmodified"))
      )
      mod = "false" if @force_new_reg_url

      if mod == "true"
        url = nil
        Builtins.y2milestone(
          "SMT server has already been modified. I will not change it again."
        )
      end

      cururl = Convert.to_string(
        SCR.Read(path(".temporary_suseregister_agent.url"))
      )
      urlmap = URL.Parse(url)

      if url != nil && url != "" && urlmap != {} &&
          Ops.get_string(urlmap, "scheme", "") == "https"
        SCR.Write(path(".temporary_suseregister_agent.url"), url)
        cururl = Convert.to_string(
          SCR.Read(path(".temporary_suseregister_agent.url"))
        )
        if url == cururl
          SCR.Write(
            path(".temporary_suseregister_agent.smturlmodified"),
            "true"
          )
        end
      end

      SCR.UnregisterAgent(path(".temporary_suseregister_agent"))
      cururl
    end


    # setupRegistrationServer()
    #
    # write SMT server settings to  (FATE #302966)
    # @return symbol that says if we can perform the registration
    #
    def xenType
      Builtins.y2milestone(
        "Checking if this machine is a XEN instance or host."
      )

      if Arch.is_xen
        Builtins.y2milestone("XEN enabled. Now detecting type.")

        if Arch.is_xen0
          Builtins.y2milestone("Detected XEN0.")
          return :xen0
        elsif Arch.is_xenU
          Builtins.y2milestone("Detected XENU")
          return :xenU
        end
      else
        Builtins.y2milestone("XEN is disabled.")
        return :noXen
      end

      Builtins.y2error(
        "An error occurred while detecting XEN. Assuming: XEN is disabled."
      )
      :unknown
    end



    # setupRegistrationServer()
    #
    # write SMT server settings to  (FATE #302966)
    # @return symbol that says if we can perform the registration
    #
    def setupRegistrationServer(mode)
      # in case smt_server is undefined nothing needs to be done
      return :ok if @smt_server == nil || @smt_server == ""

      ay = false # are we running in autoYaST mode?
      trust = false
      if mode == :autoyast
        trust = true
        ay = true
      end

      smtpemPath = "/etc/ssl/certs"
      smtpemFile = Ops.add(smtpemPath, "/registration-server.pem")

      # check if smt_server is a valid url
      smt_server_parsed = URL.Parse(@smt_server)
      if smt_server_parsed == {} ||
          Ops.get_string(smt_server_parsed, "host", "") == "" ||
          Ops.get_string(smt_server_parsed, "scheme", "") != "https"
        Builtins.y2milestone(
          "The string '%1' could not be parsed and validated as URL to be used as SMT server.",
          @smt_server
        )
        return :conferror if ay

        no_smt1 = _(
          "The registration server URL could not be validated as URL."
        )
        no_smt2 = _("Registration can not be performed.")
        no_smt3 = _("Change the URL and retry.")
        no_smt_current = Builtins.sformat(
          _("The current registration server URL is\n%1"),
          @smt_server
        )

        no_smt_server = Builtins.sformat(
          "%1\n%2\n%3\n\n%4",
          no_smt1,
          no_smt2,
          no_smt3,
          no_smt_current
        )

        Popup.Error(no_smt_server)
        return :conferror
      end


      # write SMT server URL to /etc/suseRegister.conf
      if @smt_server == suseRegisterURL(@smt_server)
        Builtins.y2milestone(
          "Setup custom SMT server as registration server successful: %1",
          @smt_server
        )
      else
        Builtins.y2error(
          "Failed to setup custom SMT server as registration server: %1",
          @smt_server
        )
      end



      # ----------===============================================-------------- //

      certmode = nil

      # never ever load a certificate file for a *.novell.com smt server
      if Builtins.regexpmatch(
          Ops.get_string(smt_server_parsed, "host", ""),
          ".+.novell.com$"
        )
        Builtins.y2milestone(
          "Registration detected a *.novell.com domain. For security reasons, there will be no certificate handling in this case."
        )
        Builtins.y2milestone(
          "In order to register at a *.novell.com domain, please make sure your registration server uses a trusted certificate and set regcert=done."
        )
        # allow override with  regcert="done" (bnc#413231)
        if @smt_server_cert == "done"
          certmode = :done
        else
          certmode = :none
        end
      elsif @smt_server_cert == nil || @smt_server_cert == ""
        certmode = :url
      elsif Builtins.regexpmatch(@smt_server_cert, "^(https?|ftp)://.+")
        certmode = :url
      elsif Builtins.regexpmatch(@smt_server_cert, "^floppy/.+")
        certmode = :floppy
      elsif Builtins.regexpmatch(@smt_server_cert, "^/.+")
        certmode = :path
      elsif @smt_server_cert == "ask"
        certmode = :ask
      elsif @smt_server_cert == "done"
        certmode = :done
      else
        certmode = :none
      end


      if !Builtins.contains(
          [:none, :done, :url, :floppy, :ask, :path],
          certmode
        )
        Builtins.y2error(
          "No SMT certificate file retrieval-mode found to handle current configuration. This should not happen!"
        )
        return :conferror
      end

      certTmpFile = Builtins.sformat(
        "%1/__tmpSMTcert.crt",
        SCR.Read(path(".target.tmpdir"))
      )

      # check for existing certificate (bnc#376000)
      certExists = false
      certExists = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("[ -f  %1 ]", smtpemFile)
        )
      ) == 0 ? true : false
      if certmode != :url && certExists
        # do nothing to refetch the certificate if manual interaction is necessary
        Builtins.y2milestone(
          "Existing SMT certificate found and keeping it. To renew the SMT certificate please assign a URL as value to the key 'regcert' in /var/lib/YaST2/install.inf"
        )
        return :ok
      end

      if certmode == :url
        certParse = URL.Parse(@smt_server_cert)

        # if no smt_server_cert is passed then we fall back to predefined smt_server_cert
        if @smt_server_cert == nil || @smt_server_cert == "" || certParse == {}
          certUrl = deep_copy(smt_server_parsed)
          Ops.set(certUrl, "scheme", "http")
          Ops.set(certUrl, "port", "80")
          Ops.set(certUrl, "path", "/smt.crt")
          @smt_server_cert = URL.Build(certUrl)
          certParse = deep_copy(certUrl)
        end
        Builtins.y2milestone(
          "Using %1 as URL to download the SMT certificate file.",
          @smt_server_cert
        )

        # download cert
        curlcmd = Builtins.sformat(
          "curl -f --connect-timeout 60  --max-time 120  '%1'   -o  %2",
          @smt_server_cert,
          certTmpFile
        )
        if SCR.Execute(path(".target.bash"), curlcmd) != 0
          if certExists
            # do nothing to refetch the certificate if manual interaction is necessary
            Builtins.y2milestone(
              "Could not download the current SMT certificate but existing certificate found and keeping it. To renew the SMT certificate please make sure it is available on the registration server."
            )
            return :ok
          end

          Builtins.y2error(
            "Could not download the SMT certificate file from specified URL %1",
            @smt_server_cert
          )
          return :conferror if ay

          # translators: this is a heading for an error message - so no punctuation
          urlError = _("Downloading SMT certificate file failed")
          errret = certificateError(urlError, :url)

          if errret == :yes
            Builtins.y2warning(
              "No SMT certificate could be retrieved (floppy mount error). User selected to skip Registration."
            )
            return :silentskip
          elsif errret == :no
            Builtins.y2warning(
              "No SMT certificate could be retrieved (floppy mount error). User selected to NOT skip Registration. Most likely Registration will fail now."
            )
            return :ok
          else
            certmode = :ask
          end

          certTmpFile = nil
        end
      end

      if certmode == :floppy
        # mount and copy
        mf = mountFloppy
        if !Ops.get_boolean(mf, "mounted", false)
          umountFloppy(Ops.get_string(mf, "mpoint", "/dev/fd0"))
          Builtins.y2error(
            "Could not mount floppy disk to copy the SMT certificte file from. The device that was used was %1",
            Ops.get_string(mf, "device", "")
          )
          if ay
            Builtins.y2error(
              "No SMT certificate file available. As we are in autoYaST mode Registration will be skipped. Please run it manually."
            )
            return :silentskip
          else
            # translators: this is a heading for an error message - so no punctuation
            fdMountError = _("Could not mount floppy disk")
            errret = certificateError(fdMountError, :floppy)

            if errret == :yes
              Builtins.y2warning(
                "No SMT certificate could be retrieved (floppy mount error). User selected to skip Registration."
              )
              return :silentskip
            elsif errret == :no
              Builtins.y2warning(
                "No SMT certificate could be retrieved (floppy mount error). User selected to NOT skip Registration. Most likely Registration will fail now."
              )
              return :ok
            else
              certmode = :ask
            end
          end
        else
          fdpath = Builtins.regexpsub(@smt_server_cert, "^floppy/(.+)$", "\\1")
          cp2tmp = Builtins.sformat(
            "/bin/cp -a  %1  %2 ",
            Ops.add(
              Ops.add(Ops.get_string(mf, "mpoint", "/media/floppy"), "/"),
              fdpath
            ),
            certTmpFile
          )
          if SCR.Execute(path(".target.bash"), cp2tmp) != 0
            Builtins.y2error(
              "Could not copy the specified SMT certificate file from floppy disk."
            )
            return :silentskip if ay

            # translators: this is a heading for an error message - so no punctuation
            fdCopyError = _("Could not read file on floppy disk")
            errret = certificateError(fdCopyError, :floppy)

            if errret == :yes
              Builtins.y2warning(
                "No SMT certificate could be retrieved (could not copy from floppy). User selected to skip Registration."
              )
              return :silentskip
            elsif errret == :no
              Builtins.y2warning(
                "No SMT certificate could be retrieved (could not copy from floppy). User selected to NOT skip Registration. Most likely Registration will fail now."
              )
              return :ok
            else
              certmode = :ask
            end
          end

          umountFloppy(Ops.get_string(mf, "mpoint", "/dev/fd0"))
        end
      end

      if certmode == :path
        # try to copy cert if valid path,  else ask   // copy

        cp2tmp = Builtins.sformat(
          " [ -f  %1 ]  &&  /bin/cp -a  %1  %2 ",
          @smt_server_cert,
          certTmpFile
        )
        if SCR.Execute(path(".target.bash"), cp2tmp) != 0
          Builtins.y2error("Could not copy local SMT certificate file")
          return :silentskip if ay

          # translators: this is a heading for an error message - so no punctuation
          fileCopyError = _("Could not find SMT certificate file in local path")
          errret = certificateError(fileCopyError, :file)
          if errret == :yes
            Builtins.y2warning(
              "No SMT certificate could be retrieved (could not copy local file). User selected to skip Registration."
            )
            return :silentskip
          elsif errret == :no
            Builtins.y2warning(
              "No SMT certificate could be retrieved (could not copy local file). User selected to NOT skip Registration. Most likely Registration will fail now."
            )
            return :ok
          else
            certmode = :ask
          end
        end
      end

      if certmode == :ask
        if ay
          Builtins.y2error(
            "SMT certificate was configured to be asked for. AutoYaST does not support interactive dialogs. Registration will be skipped."
          )
          return :silentskip
        end

        basepath = "/tmp"
        certFile = ""
        selectCertLabel = _("Select SMT certificate file")
        exitloop = false
        begin
          begin
            certFile = UI.AskForExistingFile(basepath, "*.crt", selectCertLabel)
          end while certFile == ""

          if certFile == nil
            skipReg = _(
              "Do you really want to cancel and thereby skip registration?"
            )
            if Popup.YesNo(skipReg)
              Builtins.y2milestone(
                "User selected to cancel manual certificate dialog and thereby skip registration"
              )
              return :conferror
            else
              next
            end
          end

          cp2tmp = Builtins.sformat(
            "/bin/cp -a  %1  %2 ",
            certFile,
            certTmpFile
          )
          if SCR.Execute(path(".target.bash"), cp2tmp) == 0
            Builtins.y2milestone("Found user specified SMT certificate file")
            exitloop = true
          else
            Builtins.y2milestone("Could not copy local file as SMT certificate")
            fileErrorHeader = _("Could not copy certificate file")
            fileErrorMsg = _("Do you want to retry?")
            if !Popup.YesNoHeadline(fileErrorHeader, fileErrorMsg)
              Builtins.y2milestone(
                "User selected to skip the setup of a SMT certificate"
              )
              return :conferror
            end
          end
        end while !exitloop
      end

      if certmode == :done
        Builtins.y2milestone(
          "User configured to do nothing to retrieve a SMT certificate file."
        )
        Builtins.y2milestone(
          "I hope you know what you do. Registration will be run but may fail due to missing certificate."
        )
        return :ok
      end

      if certmode == :none
        Builtins.y2warning(
          "The string that was passed to get the SMT certificate file does not match any handler."
        )
        Builtins.y2warning("The string was: %1", @smt_server_cert)
        Builtins.y2warning(
          "No certificate could be retrieved. Registration process will not be run!"
        )
        return :conferror
      end


      # log certificate details
      if certTmpFile == nil || certTmpFile == ""
        Builtins.y2error("Copying the CA certificate file failed")
        return :conferror
      end

      cP = RegisterCert.parseCertificate(certTmpFile)
      Builtins.y2milestone("SMT certificate file information: %1", cP)

      # now ask user if he trusts the certificate
      # in autoYaST mode we automatically trust
      if !ay # (bnc#377929)
        # compare with existing certificate (bnc#376000)
        if certExists
          orig_cP = RegisterCert.parseCertificate(smtpemFile)
          if Ops.get_string(orig_cP, "FINGERPRINT", "foo") ==
              Ops.get_string(cP, "FINGERPRINT", "bar")
            # return `ok if fingerprints match - no need to ask again
            Builtins.y2milestone(
              "Current SMT certificate is up to date and will be kept."
            )
            return :ok
          end
        end

        trustQuestion = _("Do you want to trust this certificate?")
        trustMessage = _(
          "This certificate will be used to connect to the SMT server.\nYou have to trust this certificate to continue with the registration.\n"
        )

        certInfo = ""

        issueList = Ops.get_list(cP, "ISSUER", [])
        #translators: this is certificate context
        certInfo = Ops.add(certInfo, _("<p><b>Issued For:</b></p>"))
        if Ops.greater_than(Builtins.size(issueList), 0)
          certInfo = Ops.add(certInfo, "<pre>")
          Builtins.foreach(
            Convert.convert(
              issueList,
              :from => "list",
              :to   => "list <map <string, string>>"
            )
          ) { |keyval| Builtins.foreach(keyval) do |key, val|
            certInfo = Ops.add(
              certInfo,
              Builtins.sformat("\n%1:  %2", key, val)
            )
          end }
          certInfo = Ops.add(certInfo, "</pre>")
        end

        #translators: this is certificate context
        certInfo = Ops.add(certInfo, _("<p><b>Subject:</b></p>"))
        subjectList = Ops.get_list(cP, "SUBJECT", [])
        if Ops.greater_than(Builtins.size(subjectList), 0)
          certInfo = Ops.add(certInfo, "<pre>")
          Builtins.foreach(
            Convert.convert(
              subjectList,
              :from => "list",
              :to   => "list <map <string, string>>"
            )
          ) { |keyval| Builtins.foreach(keyval) do |key, val|
            certInfo = Ops.add(
              certInfo,
              Builtins.sformat("\n%1:  %2", key, val)
            )
          end }
          certInfo = Ops.add(certInfo, "</pre>")
        end
        #translators: this is certificate context
        certInfo = Ops.add(certInfo, _("<p><b>Validity:</b></p>"))
        certInfo = Ops.add(certInfo, "<pre>")
        #translators: this is certificate context
        certInfo = Ops.add(
          Ops.add(Ops.add(Ops.add(certInfo, "\n"), _("Valid from: ")), " "),
          Ops.get_string(cP, "STARTDATE", "")
        )
        #translators: this is certificate context
        certInfo = Ops.add(
          Ops.add(Ops.add(Ops.add(certInfo, "\n"), _("Valid to: ")), " "),
          Ops.get_string(cP, "ENDDATE", "")
        )
        #translators: this is certificate context
        certInfo = Ops.add(
          Ops.add(Ops.add(Ops.add(certInfo, "\n"), _("Fingerprint: ")), " "),
          Ops.get_string(cP, "FINGERPRINT", "")
        )
        certInfo = Ops.add(certInfo, "</pre>")

        # certInfo = (string) SCR::Read(.target.string, certTmpFile );  // show the certificate file content -- for debugging only

        UI.OpenDialog(
          MinSize(
            70,
            20,
            VBox(
              Left(Label(Opt(:boldFont), trustQuestion)),
              Left(Label(trustMessage)),
              RichText(Builtins.sformat("%1", certInfo)),
              ButtonBox(
                PushButton(Id(:ok), _("Trust")),
                HSpacing(1.5),
                PushButton(Id(:cancel), _("Reject"))
              )
            )
          )
        )
        uret = UI.UserInput
        UI.CloseDialog
        trust = true if Convert.to_symbol(uret) == :ok
      end

      # (bnc#377929)
      if trust
        installCert = Builtins.sformat(
          "cp -a  %1  %2  &&  c_rehash %3",
          certTmpFile,
          smtpemFile,
          smtpemPath
        )
        # removed installing the certificate as well to zmd (bnc#435631)

        if Convert.to_integer(SCR.Execute(path(".target.bash"), installCert)) == 0
          Builtins.y2milestone(
            "Successfully installed SMT certificate. Registration will now proceed."
          )
          return :ok
        else
          Builtins.y2error(
            "Failed to install SMT certificate to common cert storage. Registration would fail and thus will be skipped."
          )

          if !ay
            Popup.Message(
              _(
                "Installation of the SMT certificates failed.\nSee the logs for further information.\n"
              )
            )
          end
          return :silentskip
        end
      else
        Builtins.y2milestone(
          "User decided not to trust the SMT registration server certificate. Registration will be skipped."
        )
        return :notrust
      end


      # a return to be safe :)
      :conferror 

      # return value `ok           we can perform the registration
      #              `conferror    configuration error - we have to skip registration
      #              `notrust      user does not trust certificate - we have to skip registration
      #              `silentskip   autoyast mode skip registration on error
      #              `nil          unkown error - report generic error message
    end



    # configureRegistrationServer()
    #
    # read SMT server settings from install.inf and set them up (FATE #302966)
    #
    def configureRegistrationServer
      # boot parameters have a generic naming (regurl) - internally keeping smt for variable names
      @smt_server = Linuxrc.InstallInf("regurl")
      @smt_server_cert = Linuxrc.InstallInf("regcert")

      Builtins.y2milestone("SMT config - regurl:  %1", @smt_server)
      Builtins.y2milestone("SMT config - regcert: %1", @smt_server_cert)

      # regurl=https:/smt.mybigcompany.com/center/regsvc/
      #     regcert=ask      open FileDialog
      #     regcert=done     Cert already insalled - do nothing
      #     regcert=http:/certpool.mybigcompany.com/smt/smt.crt     download from there
      #     regcert=floppy/path/to/file.crt
      #     regcert=/path/to/local/file.crt   copy from there
      #
      #     the old parameters 'smturl' and 'smtcert' are supported as well
      #       but their values will be written to 'regurl' and 'regcert'

      # setup the smt_server settings
      setupRegistrationServer(nil)
    end



    # read_config()
    #
    # reads the configuration of the registration module from sysconfig and/or user's home
    #
    def read_config
      # first read from control file
      @submit_optional = ProductFeatures.GetBooleanFeature(
        "globals",
        "enable_register_optional"
      )
      @submit_hwdata = ProductFeatures.GetBooleanFeature(
        "globals",
        "enable_register_hwdata"
      )
      # this boolean comes only from the control file - nowhere to be saved
      # do never hide the regcode checkbox, fix on behalf of (bnc#784588) as its fix will not hit already installed systems
      #display_forcereg = ProductFeatures::GetBooleanFeature("globals", "display_register_forcereg");
      @display_forcereg = true
      @disable_w3m = ProductFeatures.GetBooleanFeature(
        "globals",
        "disable_register_w3m"
      )

      @register_regularly = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          "[ -f /var/lib/suseRegister/neverRegisterOnBoot ]"
        )
      ) == 0 ? false : true
      # register_regularly = ProductFeatures::GetBooleanFeature("globals", "register_monthly");  // read default value - deactivated
      @register_regularly = @register_regularly != nil ? @register_regularly : false

      # read proxy settings
      @use_proxy = Convert.to_string(
        SCR.Read(path(".sysconfig.proxy.PROXY_ENABLED"))
      ) == "yes" ? true : false
      @http_proxy = Convert.to_string(
        SCR.Read(path(".sysconfig.proxy.HTTP_PROXY"))
      )
      @https_proxy = Convert.to_string(
        SCR.Read(path(".sysconfig.proxy.HTTPS_PROXY"))
      )

      # proxy error handling now moved to the correct place (#208651)
      @http_proxy = "" if !@use_proxy || @http_proxy == nil
      @https_proxy = "" if !@use_proxy || @https_proxy == nil


      # then read from sysconfig - but not during installation
      if Mode.normal
        sysc_submit_optional = Convert.to_string(
          SCR.Read(path(".sysconfig.suse_register.SUBMIT_OPTIONAL"))
        )
        sysc_submit_hwdata = Convert.to_string(
          SCR.Read(path(".sysconfig.suse_register.SUBMIT_HWDATA"))
        )
        if sysc_submit_optional != ""
          @submit_optional = sysc_submit_optional == "true" ? true : false
        end
        if sysc_submit_hwdata != ""
          @submit_hwdata = sysc_submit_hwdata == "true" ? true : false
        end
      end

      nil
    end



    # write_config()
    #
    # writes the configuration to the system
    # either to sysconfig if runnig as root or to user's home if running as non-root
    #
    def write_config
      SCR.Write(
        path(".sysconfig.suse_register.SUBMIT_OPTIONAL"),
        Builtins.sformat("%1", @submit_optional == true ? true : false)
      )
      SCR.Write(
        path(".sysconfig.suse_register.SUBMIT_HWDATA"),
        Builtins.sformat("%1", @submit_hwdata == true ? true : false)
      )

      @register_regularly = false if @register_regularly == nil
      SCR.Execute(
        path(".target.bash"),
        Builtins.sformat(
          "%1 /var/lib/suseRegister/neverRegisterOnBoot",
          @register_regularly == true ? "rm -f " : "touch "
        )
      )
      # touch a flag file for opensuseupdater
      SCR.Execute(
        path(".target.bash"),
        Builtins.sformat("touch /var/lib/YaST2/registrationDidRun")
      )

      nil
    end

    # ------------------------------------------------------------------
    # END: Locally defined functions
    # ------------------------------------------------------------------


    # initialize
    #
    # Initialize booleans: submit_optional, submit_hwdata and iamroot
    #
    def suseRegisterOnce
      # (#164794)
      # on behalf of hmuelle and shorn
      UI.OpenDialog(
        VBox(
          # translators: busy popup while registering the system
          Left(Heading(_("Contacting server..."))),
          # translators: Text for a busy-process-indicator while registering the system
          BusyIndicator(
            Id(:busyContactingServer),
            _("This may take a while"),
            300000
          )
        )
      )
      # Bug #171061 - Busy cursor during "Contacting server..."
      UI.BusyCursor

      ret = YSR.register

      # Bug #171061 - Changing back to normal cursor
      UI.NormalCursor
      UI.CloseDialog

      errorCode = YSR.get_errorcode
      if errorCode != 0
        # error
        Builtins.y2warning(
          "Register call returned with an error message (error code: %1): %2",
          errorCode,
          YSR.get_errormsg
        )
        Builtins.y2warning(
          "This basically means registration is not finished yet."
        )
      end

      ret
    end



    # getSrcIdFromSrcMap
    #
    # get a SrcID from a sources list
    # takes a name of a source and the sources list<map> from Pkg::SourceEditGet()
    # @return: id of the found source, else nil

    def getSrcIdFromSrcList(name, allSrc)
      allSrc = deep_copy(allSrc)
      if name == nil || name == ""
        Builtins.y2error("Can not find a source with an empty or invalid name.")
        return nil
      elsif allSrc == nil || allSrc == []
        Builtins.y2error("Can not find a source in an empty sources list.")
        return nil
      end

      foundSrc = nil

      Builtins.foreach(allSrc) do |srcMap|
        if Ops.is_string?(Ops.get_string(srcMap, "name", ""))
          if Ops.get_string(srcMap, "name", "") == name
            if Ops.is_integer?(Ops.get(srcMap, "SrcId"))
              foundSrc = Ops.get_integer(srcMap, "SrcId")
            end
          end
        end
      end

      if foundSrc == nil
        Builtins.y2error(
          "Could not find a source ID for the source with the name: %1",
          name
        )
      else
        Builtins.y2milestone(
          "Found a source id for a source: %1 (%2)",
          name,
          foundSrc
        )
      end

      foundSrc
    end

    # ---------------------------------------------------------------------------------------
    # START: Globally defined functions
    # ---------------------------------------------------------------------------------------



    # initialize
    #
    # Initialize booleans: submit_optional, submit_hwdata and iamroot
    #
    def initialize
      read_config
      @iamroot = amIroot

      nil
    end



    # finish
    #
    # Finishing the modules stuff: calling write_config()
    #
    def finish
      @iamroot = amIroot
      write_config
      # reset YSRs context
      YSR.del_ctx
      @isInitializedSR = false

      nil
    end


    # callbackAuthenticationOnRefresh
    # dummy callbackfunction to disable the authentication errors
    def callbackAuthenticationOnRefresh
      Builtins.y2error(
        "Refreshing a service or repository filed because of an authentication error."
      )
      Builtins.y2error(
        "This is a valid scenario though, and only means that registration needs to be run."
      )
      Builtins.y2error(
        "Registration will now continue without a warning to the user."
      )
      { "continue" => false, "username" => "", "password" => "" }
    end


    # checkCatalogs
    #
    # takes a sub-"taskList"-map (catalogs-map) from SuseRegister and updates listed repositories
    # @return a list with a small summary (added/deleted/enabled/disabled repos)
    def checkCatalogs(taskList, service)
      taskList = deep_copy(taskList)
      Builtins.y2debug(
        "Task list of check catalogs for the service (%1): %2",
        service,
        taskList
      )

      cSummary = []
      catalogToEnable = []
      catalogToDisable = []

      Builtins.foreach(taskList) do |catalog, pAny|
        if !Ops.is_map?(pAny)
          Builtins.y2error(
            "A catalog returned by SuseRegister did not contain any details: %1",
            catalog
          )
          @repoUpdateSuccessful = false
        elsif catalog == nil || catalog == ""
          Builtins.y2error(
            "A catalog returned by SuseRegister has no or an invalid name."
          )
          @repoUpdateSuccessful = false
        else
          catDetail = Convert.to_map(pAny)

          if Ops.get_string(catDetail, "ALIAS", "") == nil ||
              Ops.get_string(catDetail, "ALIAS", "") == ""
            Builtins.y2error(
              "A catalog returned by SuseRegister has no or an invalid alias name."
            )
            @repoUpdateSuccessful = false
          else
            if Ops.get_string(catDetail, "TASK", "") == nil ||
                Ops.get_string(catDetail, "TASK", "") == ""
              Builtins.y2error(
                "A catalog returned by SuseRegister has an invalid task: %1",
                catalog
              )
              @repoUpdateSuccessful = false
            elsif Ops.get_string(catDetail, "TASK", "") == "le" ||
                Ops.get_string(catDetail, "TASK", "") == "ld"
              Builtins.y2milestone(
                "According to SuseRegister a catalog does not need to be changed: %1 (%2)",
                catalog,
                service
              )
            elsif Ops.get_string(catDetail, "TASK", "") == "a"
              Builtins.y2milestone(
                "According to SuseRegister a catalog has to be enabled: %1 (%2)",
                catalog,
                service
              )
              catalogToEnable = Builtins.add(catalogToEnable, catalog)
              cSummary = Builtins.add(
                cSummary,
                Builtins.sformat(
                  _("Enabled catalog: %1 (%2)"),
                  catalog,
                  service
                )
              )
            elsif Ops.get_string(catDetail, "TASK", "") == "d"
              Builtins.y2milestone(
                "According to SuseRegister a service has to be disabled: %1 (%2)",
                catalog,
                service
              )
              catalogToDisable = Builtins.add(catalogToDisable, catalog)
              cSummary = Builtins.add(
                cSummary,
                Builtins.sformat(
                  _("Disabled catalog: %1 (%2)"),
                  catalog,
                  service
                )
              )
            else
              Builtins.y2error(
                "A catalog returned by SuseRegister has an unsupported task: %1 (%2)",
                catalog,
                service
              )
              @repoUpdateSuccessful = false
            end
          end
        end
      end

      serviceDetails = {}
      serviceDetails = Pkg.ServiceGet(service)
      Ops.set(
        serviceDetails,
        "repos_to_enable",
        Builtins.union(
          Ops.get_list(serviceDetails, "repos_to_enable", []),
          catalogToEnable
        )
      )
      Ops.set(
        serviceDetails,
        "repos_to_disable",
        Builtins.union(
          Ops.get_list(serviceDetails, "repos_to_disable", []),
          catalogToDisable
        )
      )

      # enabled flag must not be present - otherwise all catalogs will be activated
      serviceDetails = Builtins.remove(serviceDetails, "enabled")

      Builtins.y2debug(
        "Setting service properties for service (%1): %2",
        service,
        serviceDetails
      )

      if Pkg.ServiceSet(service, serviceDetails)
        Builtins.y2milestone(
          "Successfully updated the catalog settings of service: %1",
          service
        )
        Builtins.y2milestone(
          "Set repostoenable: %1 (%2)",
          catalogToEnable,
          service
        )
        Builtins.y2milestone(
          "Set repostodisable: %1 (%2)",
          catalogToDisable,
          service
        ) 
        # saving the service is (resp. has to be) done after calling checkCatalogs()
      else
        Builtins.y2error(
          "Could not update the catalog settings of service: %1",
          service
        )
        @repoUpdateSuccessful = false
      end

      deep_copy(cSummary)
    end





    # updateSoftwareRepositories
    #
    # takes a "taskList"-map from SuseRegister and updates the repositories
    # @return a list with a small summary (added/deleted/enabled/disabled repos)
    def updateSoftwareRepositories(taskList, doRefresh)
      taskList = deep_copy(taskList)
      # see if there are actions to perform
      return [] if taskList == {}

      Builtins.y2debug(
        "Task list to update software repositories: %1",
        taskList
      )

      summary = []

      currentSources = Pkg.SourceEditGet
      # log the sources for debugging purposes
      # y2milestone("The current sources are: %1", currentSources);


      # outer foreach loop - loop over service names/aliases
      Builtins.foreach(taskList) do |pService, pAny|
        if !Ops.is_map?(pAny)
          Builtins.y2error(
            "A service returned by SuseRegister did not contain any details: %1",
            pService
          )
          @repoUpdateSuccessful = false
        elsif pService == nil || pService == ""
          Builtins.y2error(
            "A service returned by SuseRegister has no or an invalid name."
          )
          @repoUpdateSuccessful = false
        else
          if !Ops.is_string?(Ops.get_string(Convert.to_map(pAny), "TYPE", ""))
            Builtins.y2error(
              "A service returned by SuseRegister has an invalid type: %1 (%2)",
              pService,
              Ops.get_string(Convert.to_map(pAny), "TYPE", "")
            )
            @repoUpdateSuccessful = false
          end
          if Ops.get_string(Convert.to_map(pAny), "TYPE", "") == "zypp"
            Builtins.y2milestone("Handling a service of the type zypp")
            if !Ops.is_string?(Ops.get_string(Convert.to_map(pAny), "TASK", ""))
              Builtins.y2error(
                "A service returned by SuseRegister has an invalid task: %1 (%2)",
                pService,
                Ops.get_string(Convert.to_map(pAny), "TASK", "")
              )
              @repoUpdateSuccessful = false
            elsif Ops.get_string(Convert.to_map(pAny), "TASK", "") == "le" ||
                Ops.get_string(Convert.to_map(pAny), "TASK", "") == "ld"
              Builtins.y2milestone(
                "According to SuseRegister a service does not need to be changed: %1",
                pService
              )
            elsif Ops.get_string(Convert.to_map(pAny), "TASK", "") == "a"
              # SourceAdd
              Builtins.y2milestone(
                "According to SuseRegister a service has to be added: %1",
                pService
              )

              # create map for new source
              newSrcMap =
                # remove repo type (bnc#444770)
                {
                  "enabled"     => true,
                  "autorefresh" => true,
                  "name"        => Ops.get_string(
                    Convert.to_map(pAny),
                    "NAME",
                    ""
                  ),
                  "alias"       => Ops.get_string(
                    Convert.to_map(pAny),
                    "ALIAS",
                    ""
                  ),
                  "base_urls"   => [
                    Ops.get_string(Convert.to_map(pAny), "URL", "")
                  ],
                  "priority"    => Ops.get_integer(
                    Convert.to_map(pAny),
                    "PRIORITY",
                    99
                  )
                }

              newSrcID = Pkg.RepositoryAdd(newSrcMap)

              if newSrcID == nil
                Builtins.y2error("Adding a new service failed: %1", pService)
                @repoUpdateSuccessful = false
              else
                Builtins.y2milestone(
                  "Successfully added a new service: %1 (%2)",
                  pService,
                  newSrcID
                )
                summary = Builtins.add(
                  summary,
                  Builtins.sformat(_("Added Source: %1"), pService)
                )
              end
            elsif Ops.get_string(Convert.to_map(pAny), "TASK", "") == "d"
              # SourceDelete
              Builtins.y2milestone(
                "According to SuseRegister a service has to be deleted: %1",
                pService
              )

              srcID = getSrcIdFromSrcList(pService, currentSources)
              if srcID == nil
                Builtins.y2error(
                  "A service that should be deleted can not be found: %1",
                  pService
                )
                @repoUpdateSuccessful = false
              else
                if Pkg.SourceDelete(srcID)
                  Builtins.y2milestone(
                    "Successfully deleted a service: %1 (%2)",
                    pService,
                    srcID
                  )
                  summary = Builtins.add(
                    summary,
                    Builtins.sformat(_("Deleted Source: %1"), pService)
                  )
                else
                  Builtins.y2error(
                    "Could not delete a service: %1 (%2)",
                    pService,
                    srcID
                  )
                  @repoUpdateSuccessful = false
                end
              end
            else
              Builtins.y2error(
                "A service returned by SuseRegister has an unsupported task: %1 (%2)",
                pService,
                Ops.get_string(Convert.to_map(pAny), "TASK", "")
              )
              @repoUpdateSuccessful = false
            end
          elsif Ops.get_string(Convert.to_map(pAny), "TYPE", "") == "nu"
            Builtins.y2milestone("Handling a service of the type nu")

            if !Ops.is_string?(Ops.get_string(Convert.to_map(pAny), "TASK", ""))
              Builtins.y2error(
                "A service returned by SuseRegister has an invalid task: %1 (%2)",
                pService,
                Ops.get_string(Convert.to_map(pAny), "TASK", "")
              )
              @repoUpdateSuccessful = false
            elsif Ops.get_string(Convert.to_map(pAny), "TASK", "") == "ld"
              Builtins.y2milestone(
                "According to SuseRegister a service should be left disabled: %1",
                pService
              )
            elsif Ops.get_string(Convert.to_map(pAny), "TASK", "") == "le"
              Builtins.y2milestone(
                "According to SuseRegister a service should be left enabled: %1",
                pService
              )
              Builtins.y2milestone(
                "Now checking the catalogs of the service: %1",
                pService
              )

              catalogsMap = Ops.get_map(Convert.to_map(pAny), "CATALOGS", {})
              if Ops.is_map?(catalogsMap) && catalogsMap != {}
                Builtins.y2milestone(
                  "A service returned by SuseRegister has catalogs that will be checked now."
                )
                cSummary = checkCatalogs(
                  Convert.convert(
                    catalogsMap,
                    :from => "any",
                    :to   => "map <string, any>"
                  ),
                  pService
                )
                summary = Convert.convert(
                  Builtins.merge(summary, cSummary),
                  :from => "list",
                  :to   => "list <string>"
                )
              else
                Builtins.y2error(
                  "A service returned by SuseRegister did not contain any catalogs."
                )
                @repoUpdateSuccessful = false
              end

              # we may have changed something - so lets save and refresh now
              # because the Pkg bindings do not operate on the system directly we need to save them before we can continue
              if Pkg.ServiceSave(pService)
                Builtins.y2milestone(
                  "Successfully saved service: %1.",
                  pService
                )

                if Pkg.ServiceRefresh(pService)
                  Builtins.y2milestone(
                    "Successfully refreshed service: %1",
                    pService
                  )
                else
                  Builtins.y2error("Could not refresh service: %1", pService)
                end
              else
                Builtins.y2error(
                  "Could not save a service to the system: %1",
                  pService
                )
                @repoUpdateSuccessful = false
              end
            elsif Ops.get_string(Convert.to_map(pAny), "TASK", "") == "a"
              # ServiceAdd
              Builtins.y2milestone(
                "According to SuseRegister a service has to be added: %1",
                pService
              )

              # add credetials information (bnc#435645)
              serviceAddUrl = URL.Parse(
                Ops.get_string(Convert.to_map(pAny), "URL", "")
              )
              queryJoinChar = ""
              if Ops.greater_than(
                  Builtins.size(Ops.get_string(serviceAddUrl, "query", "")),
                  0
                )
                queryJoinChar = "&"
              end
              Ops.set(
                serviceAddUrl,
                "query",
                Ops.add(
                  Ops.add(
                    Ops.get_string(serviceAddUrl, "query", ""),
                    queryJoinChar
                  ),
                  "credentials=NCCcredentials"
                )
              )

              if Pkg.ServiceAdd(pService, URL.Build(serviceAddUrl))
                Builtins.y2milestone(
                  "Successfully added a new service: %1",
                  pService
                )
                Builtins.y2milestone(
                  "Now checking the catalogs of the service: %1",
                  pService
                )
                summary = Builtins.add(
                  summary,
                  Builtins.sformat(_("Added Service: %1"), pService)
                )

                # activate autorefresh - only for services that get added!
                newServiceDetails = Pkg.ServiceGet(pService)
                Ops.set(newServiceDetails, "autorefresh", true)
                if Pkg.ServiceSet(pService, newServiceDetails)
                  Builtins.y2milestone(
                    "Successfully activated autofresh mode for service: %1",
                    pService
                  )
                else
                  Builtins.y2error(
                    "Could not activate autofresh mode for service: %1",
                    pService
                  )
                end

                # then iterate over catalogs
                catalogsMap = Ops.get_map(Convert.to_map(pAny), "CATALOGS", {})
                if Ops.is_map?(catalogsMap) && catalogsMap != {}
                  Builtins.y2milestone(
                    "A new service returned by SuseRegister has catalogs that will be checked now."
                  )
                  cSummary = checkCatalogs(
                    Convert.convert(
                      catalogsMap,
                      :from => "any",
                      :to   => "map <string, any>"
                    ),
                    pService
                  )
                  summary = Convert.convert(
                    Builtins.merge(summary, cSummary),
                    :from => "list",
                    :to   => "list <string>"
                  )
                else
                  Builtins.y2error(
                    "A new service returned by SuseRegister did not contain any catalogs."
                  )
                  @repoUpdateSuccessful = false
                end

                # we may have changed something - so lets save and refresh now
                # because the Pkg bindings do not operate on the system directly we need to save them before we can continue
                if Pkg.ServiceSave(pService)
                  Builtins.y2milestone(
                    "Successfully saved service: %1.",
                    pService
                  )

                  if Pkg.ServiceRefresh(pService)
                    Builtins.y2milestone(
                      "Successfully refreshed service: %1",
                      pService
                    )
                  else
                    Builtins.y2error("Could not refresh service: %1", pService)
                  end
                else
                  Builtins.y2error(
                    "Could not save a service to the system: %1",
                    pService
                  )
                  @repoUpdateSuccessful = false
                end
              else
                Builtins.y2error("Adding a new service failed: %1", pService)
                @repoUpdateSuccessful = false
              end
            elsif Ops.get_string(Convert.to_map(pAny), "TASK", "") == "d"
              # ServiceDelete
              Builtins.y2milestone(
                "According to SuseRegister a service has to be deleted: %1",
                pService
              )

              if Pkg.ServiceDelete(pService)
                Builtins.y2milestone(
                  "Successfully deleted a service: %1",
                  pService
                )
                summary = Builtins.add(
                  summary,
                  Builtins.sformat(_("Deleted Service: %1"), pService)
                )
              else
                Builtins.y2error("Could not delete a service: %1", pService)
                @repoUpdateSuccessful = false
              end
            else
              Builtins.y2error(
                "A service returned by SuseRegister has an unsupported task: %1 (%2)",
                pService,
                Ops.get_string(Convert.to_map(pAny), "TASK", "")
              )
              @repoUpdateSuccessful = false
            end
          else
            Builtins.y2error(
              "A service returned by SuseRegister has an unsupported type: %1 (%2)",
              pService,
              Ops.get_string(Convert.to_map(pAny), "TYPE", "")
            )
            @repoUpdateSuccessful = false
          end
        end
      end


      # on successful registration and only if there were changes, we need to refresh all sources
      if Ops.greater_than(Builtins.size(summary), 0)
        # save all changes to the sources that we have done
        Pkg.SourceSaveAll

        # we can not refresh in autoYaST mode as it may require manual interaction to import keys
        if doRefresh
          Builtins.y2milestone(
            "Changes to the repositories and services were successful. Now refreshing all of them."
          )

          currentNewServices = Pkg.ServiceAliases
          Builtins.foreach(currentNewServices) do |serviceAlias|
            Builtins.y2milestone(
              "Refreshing service with Alias: %1",
              serviceAlias
            )
            Pkg.ServiceRefresh(serviceAlias)
          end

          currentNewSources = Pkg.SourceGetCurrent(true)
          Builtins.foreach(currentNewSources) do |srcID|
            Builtins.y2milestone("Refreshing source with ID: %1", srcID)
            # no "forced" refresh needed - default is sufficient (bnc#476429)
            Pkg.SourceRefreshNow(srcID)
          end
        end
      end

      # finish sources (bnc#447080)
      if Pkg.SourceFinishAll
        Builtins.y2milestone(
          "Successfully finished all sources to enforce a reload."
        )

        # restart the SourceManager to refill the cache with the current data (bnc#468449)
        #   an application that called the registration (or that follows it) should be presented an updated pkg system
        if Pkg.SourceStartManager(true)
          Builtins.y2milestone("Successfully restarted source manager.")
        else
          Builtins.y2error("Failed to restart source manager")
        end
      else
        Builtins.y2error("Failed to finish all sources.")
      end

      if @repoUpdateSuccessful
        Builtins.y2milestone("SuseRegister will now save the lastZmdConfig.")
        YSR.saveLastZmdConfig
      else
        Builtins.y2error(
          "Error occurred while changing the systems repositories according to the instructions of SuseRegister. SuseRegister will not save this status as lastZmdConfig."
        )
      end


      deep_copy(summary)
    end


    # suseRegister()
    # return the error code of SuseRegister (via YSR.pm) as integer
    def suseRegister(parameter)
      allCurrentSources = []
      allCurrentServices = []

      ui = UI.GetDisplayInfo
      debugMode = Ops.get_boolean(ui, "y2debug", false)

      # take care for nil booleans (bnc#463800)
      contextData = {
        "debug"        => debugMode == true ? 2 : 0,
        "nooptional"   => @submit_optional == true ? 0 : 1,
        "nohwdata"     => @submit_hwdata == true ? 0 : 1,
        "forcereg"     => @force_registration == true ? 1 : 0, # (bnc#443704)
        "norefresh"    => 1,
        "yastcall"     => 1,
        "restoreRepos" => 1, # (#309231)
        "logfile"      => "/root/.suse_register.log"
      }
      Builtins.y2milestone(
        "Basic initialization data for SuseRegister (custom registration data is suppressed for security reasons): %1",
        contextData
      )

      # add data to the context from autoyast profile or from manual input
      if @registration_data != {}
        # append sensitive data to the context map
        # collect data inside of the args keyword (bnc#476494)
        Ops.set(contextData, "args", @registration_data)

        # do not log sensitive data to the log (#195624)
        Builtins.y2milestone(
          "Added sensitive registration data to suse_register call - the data will not be logged, only the used keys"
        )

        # list the used keys in the log
        Builtins.foreach(@registration_data) do |key, val|
          Builtins.y2milestone(
            "Added sensitive registration data for the key: %1",
            key
          )
        end
      end


      if !@isInitializedSR || !@isInitializedTarget ||
          contextData != @contextDataSR
        # initialize target
        if !@isInitializedTarget
          targetRootDir = Mode.normal == true ? "/" : Installation.destdir
          if !Pkg.TargetInitialize(targetRootDir)
            Builtins.y2error(
              "Initializing the target failed via Pkg::TargetInitialize. No interaction with the package system is possible."
            )
            return 113
          end
          Builtins.y2milestone("Successfully initialized the target.")
          @isInitializedTarget = true

          if Pkg.SourceStartManager(true)
            Builtins.y2milestone("Successfully started source manager.")
          else
            Builtins.y2error("Failed to start source manager")
            return 199
          end

          #            y2debug("Setting Pkg::CallbackAuthentication to a dummy function");
          #            Pkg::CallbackAuthentication("Register::callbackAuthenticationOnRefresh");

          Builtins.y2milestone("Initially refreshing services.")
          # refresh all services _once_ before interacting with SuseRegister
          allCurrentServices = Pkg.ServiceAliases

          Builtins.foreach(allCurrentServices) do |serviceAlias|
            Builtins.y2milestone(
              "Refreshing service with Alias: %1",
              serviceAlias
            )
            Pkg.ServiceRefresh(serviceAlias)
          end

          Builtins.y2milestone("Initially refreshing sources.")
          # refresh all sources _once_ before interacting with SuseRegister
          allCurrentSources = Pkg.SourceGetCurrent(true)

          Builtins.foreach(allCurrentSources) do |srcID|
            Builtins.y2milestone("Refreshing source with ID: %1", srcID)
            # no "forced" refresh needed - default is sufficient (bnc#476429)
            Pkg.SourceRefreshNow(srcID)
          end
          Builtins.y2milestone("Initial refreshing ended.") 

          #            y2debug("Resetting Pkg::CallbackAuthentication to default.");
          #            Pkg::CallbackAuthentication(nil);
        end

        # setting the proxy must happen before init_ctx is called (bnc#468480)
        # setting up proxy for SuseRegister
        if @use_proxy
          # setup proxy for http and https individually (bnc#468919)
          if @http_proxy == nil
            @http_proxy = ""
            Builtins.y2error(
              "Setting for http proxy is broken. Resetting http proxy. Registration will not use an http proxy."
            )
          end

          if @https_proxy == nil
            @https_proxy = ""
            Builtins.y2error(
              "Setting for https proxy is broken. Resetting https proxy. Registration will not use an https proxy."
            )
          end

          if @http_proxy != "" || @https_proxy != ""
            Builtins.y2milestone(
              "Setting up proxy for SuseRegister. http_proxy: %1  -- https_proxy: %2",
              @http_proxy,
              @https_proxy
            )
            YSR.set_proxy(@http_proxy, @https_proxy)
          else
            Builtins.y2milestone(
              "No proxy settings will be used for registration and SuseRegister."
            )
          end
        end

        # initialize SuseRegister
        @contextDataSR = deep_copy(contextData)
        Builtins.y2milestone(
          "Initializing SuseRegister with this context data: %1",
          @contextDataSR
        )
        YSR.init_ctx(@contextDataSR)

        initErrorCode = YSR.get_errorcode
        if initErrorCode == 0
          Builtins.y2milestone("Successfully initialized SuseRegister.")
          @isInitializedSR = true
        else
          Builtins.y2error(
            "Initializing SuseRegister failed with error code (%1) and error message: %2",
            initErrorCode,
            YSR.get_errormsg
          )
          return initErrorCode
        end
      end

      # ----====  handle modes for suseRegister  ====----

      # special mode for list-params
      # only makes sure registration is initialized
      if parameter == :listparams
        Builtins.y2milestone(
          "Making sure suseregister is initialized for listparams"
        )
        return 0
      end
      begin
        @initialSRstatus = suseRegisterOnce
        Builtins.y2milestone(
          "SuseRegister loop: SuseRegister returned with error code: %1",
          @initialSRstatus
        )
      end while @initialSRstatus == 1


      # everything fine - nothing to be done
      if @initialSRstatus == 0
        Builtins.y2milestone(
          "SuseRegister returned with status: %1",
          @initialSRstatus
        )
        # touch webyast flag file to show in webyast that this machine is already registered (bnc#634026)
        SCR.Execute(
          path(".target.bash"),
          " [ -d  /var/lib/yastws ]       && date +%s > /var/lib/yastws/registration_successful "
        )
        SCR.Execute(
          path(".target.bash"),
          " [ -d  /var/lib/suseRegister ] && date +%s > /var/lib/suseRegister/y2_registration_successful "
        )
      end


      if parameter == :autoyast
        Builtins.y2milestone(
          "SuseRegister was called in autoYaST mode. The overall registration satus is: %1",
          @initialSRstatus
        )
        if @initialSRstatus == 0
          Builtins.y2milestone(
            "Registeration in autoYaST mode succeeded. Now checking the repositories."
          )
          # in autoyast mode this must be called from here
          taskList = YSR.getTaskList
          if taskList == {}
            Builtins.y2milestone(
              "According to SuseRegister no repositories need to be changed."
            )
          else
            updateSoftwareRepositories(taskList, false)
          end
        elsif @initialSRstatus == 4
          Builtins.y2error(
            "Manual interaction is required for proper registration which is not possible during autoYaST. Please register manually."
          )
        end
      end

      Builtins.y2milestone("SuseRegister status: %1", @initialSRstatus)
      @initialSRstatus
    end


    # suseRegisterListParams()
    # returns the text to display as details in the registration module
    def suseRegisterListParams
      Builtins.y2milestone(
        "User requested the args map. Collecting registration data details."
      )

      # make sure the suseRegister is initialized and the args map contains information
      retval = suseRegister(:listparams)
      if retval == 0
        Builtins.y2milestone("Registration data details map: %1", @argsDataSR)
        return YSR.listParams
      end

      Builtins.y2error(
        "Error occurred when collecting registration data details. The exit code was: %1",
        retval
      )
      _("Error: Could not retrieve data.")
    end



    # ------------------------------------------------------------------
    # END: Globally defined functions
    # ------------------------------------------------------------------



    # Read()
    def Read
      initialize

      nil
    end


    # Import()
    def Import(settings)
      settings = deep_copy(settings)
      @iamroot = amIroot

      @submit_optional = false
      @submit_hwdata = false
      @do_registration = false
      @registration_data = {}

      @submit_optional = Ops.get_boolean(
        settings,
        "submit_optional",
        @submit_optional
      )
      @submit_hwdata = Ops.get_boolean(
        settings,
        "submit_hwdata",
        @submit_hwdata
      )
      @do_registration = Ops.get_boolean(
        settings,
        "do_registration",
        @do_registration
      )
      @register_regularly = Ops.get_boolean(
        settings,
        "register_regularly",
        @register_regularly
      )
      @registration_data = Ops.get_map(settings, "registration_data", {})
      @smt_server = Ops.get_string(settings, "reg_server", "")
      @smt_server_cert = Ops.get_string(settings, "reg_server_cert", "")

      true
    end



    # Write()
    def Write
      @iamroot = amIroot
      setupRegistrationServer(:autoyast)
      suseRegister(:autoyast) if @do_registration
      finish
      true
    end



    # AutoYaST interface function: Export()
    # @return [Hash] with the settings
    def Export
      {
        "submit_optional"    => @submit_optional,
        "submit_hwdata"      => @submit_hwdata,
        "do_registration"    => @do_registration,
        "register_regularly" => @register_regularly,
        "reg_server"         => @smt_server,
        "reg_server_cert"    => @smt_server_cert,
        "registration_data"  => @registration_data
      }
    end

    publish :variable => :autoYaSTModified, :type => "boolean"
    publish :variable => :do_registration, :type => "boolean"
    publish :variable => :iamroot, :type => "boolean"
    publish :variable => :submit_optional, :type => "boolean"
    publish :variable => :submit_hwdata, :type => "boolean"
    publish :variable => :force_registration, :type => "boolean"
    publish :variable => :display_forcereg, :type => "boolean"
    publish :variable => :register_regularly, :type => "boolean"
    publish :variable => :disable_w3m, :type => "boolean"
    publish :variable => :use_proxy, :type => "boolean"
    publish :variable => :http_proxy, :type => "string"
    publish :variable => :https_proxy, :type => "string"
    publish :variable => :smt_server, :type => "string"
    publish :variable => :smt_server_cert, :type => "string"
    publish :variable => :force_new_reg_url, :type => "boolean"
    publish :variable => :registration_data, :type => "map <string, string>"
    publish :function => :xenType, :type => "symbol ()"
    publish :function => :setupRegistrationServer, :type => "symbol (symbol)"
    publish :function => :configureRegistrationServer, :type => "symbol ()"
    publish :function => :initialize, :type => "void ()"
    publish :function => :finish, :type => "void ()"
    publish :function => :callbackAuthenticationOnRefresh, :type => "map <string, any> ()"
    publish :function => :checkCatalogs, :type => "list <string> (map <string, any>, string)"
    publish :function => :updateSoftwareRepositories, :type => "list <string> (map <string, any>, boolean)"
    publish :function => :suseRegister, :type => "integer (symbol)"
    publish :function => :suseRegisterListParams, :type => "string ()"
    publish :function => :Read, :type => "void ()"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Write, :type => "boolean ()"
    publish :function => :Export, :type => "map ()"
  end

  Register = RegisterClass.new
  Register.main
end
