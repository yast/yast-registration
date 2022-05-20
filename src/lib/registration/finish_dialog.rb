require "fileutils"

require "yast"
require "suse/connect"

require "registration/helpers"
require "registration/registration"
require "registration/repo_state"

module Registration
  class FinishDialog
    include Yast::Logger
    include Yast::I18n

    USABLE_WORKFLOWS = [
      :installation,
      :live_installation,
      :autoinst,
      :update
    ].freeze

    def initialize
      textdomain "registration"

      Yast.import "Installation"
    end

    def run(*args)
      func = args.first
      param = args[1] || {}

      log.debug "registration finish client called with #{func} and #{param}"

      case func
      when "Info"
        {
          "steps" => 1,
          # progress step title
          "title" => _(
            "Storing Registration Configuration..."
          ),
          "when"  => USABLE_WORKFLOWS
        }

      when "Write"
        # do not write anything if registration was skipped
        return nil unless Registration.is_registered?

        # enable back the update repositories in the installed system
        RepoStateStorage.instance.restore_all

        # save the registration config
        save_config

        # copy the imported SSL certificate
        Helpers.copy_certificate_to_target

        # remove the obsoleted NCC credentials when upgrading from SLE11
        remove_ncc_credentials
        nil
      else
        raise "Unknown action #{func} passed as first parameter"
      end
    end

    def save_config
      # write the current config
      Helpers.write_config

      # copy it to the target system
      source_path = SUSE::Connect::YaST::DEFAULT_CONFIG_FILE
      target_path = File.join(Yast::Installation.destdir, source_path)

      ::FileUtils.mv(source_path, target_path)
    end

    # remove the old NCCcredentials file from the system, it's not need
    # after the migration from SLE11 (moreover the content should be the same
    # as in the new SCCCredentials file)
    def remove_ncc_credentials
      ncc_file = File.join(Yast::Installation.destdir,
        SUSE::Connect::YaST::DEFAULT_CREDENTIALS_DIR, "NCCcredentials")
      return unless File.exist?(ncc_file)

      log.info("Removing the old NCC credentials file: #{ncc_file}")
      File.delete(ncc_file)
    end
  end
end
