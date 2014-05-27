require "yast"
require "suse/connect"

require "registration/helpers"
require "registration/registration"

module Registration
  class FinishDialog
    include Yast::Logger
    include Yast::I18n

    USABLE_WORKFLOWS = [
      :installation,
      :live_installation,
      :autoinst,
      :update,
    ]

    def initialize
      textdomain "registration"
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

        Yast.import "Installation"

        target_path = Yast::Installation.destdir + SUSE::Connect::Config::DEFAULT_CONFIG_FILE
        config = SUSE::Connect::Config.new target_path

        config.url = Helpers.registration_url
        config.insecure = Helpers.insecure_registration

        log.info "writing registration config: #{config.to_hash}"

        config.write

        nil
      else
        raise "Uknown action #{func} passed as first parameter"
      end
    end
  end
end
