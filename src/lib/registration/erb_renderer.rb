# ***************************************************************************
# Copyright (c) 2017 SUSE LLC
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
# ***************************************************************************

require "erb"
require "yast"
require "yast/i18n"

module Registration
  # A helper used to get ERB out of Yast context
  # to workaround the YaST::String and ::String conflict inside Ruby Erb
  class ErbRenderer
    include Yast::I18n
    include ERB::Util

    def initialize(config)
      @config = config
    end

    def render_erb_template(file)
      ::Registration::Helpers.render_erb_template(file, binding)
    end
  end
end
