# Copyright (c) [2019] SUSE LLC
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

require "suse/connect"
require "registration/ui/addon_selection_registration_dialog"

class RegistrationMock
  def activated_products
    YAML.load_file("test/fixtures/activated_products.yml")
  end

  def get_addon_list
    YAML.load_file("test/fixtures/pure_addons.yml")
  end

  def addon_generator(params = {})
    SUSE::Connect::Remote::Product.new(suse_connect_product_generator(params))
  end
end

module Yast
  class Registration::Addon
    def self.find_all(registration)
      YAML.load_file("test/fixtures/sle15_addons.yaml")
    end
  end

  class TestAddonSelectionClient < Client
    def main
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "Wizard"


      Stage.Set("continue")
      Mode.SetMode("installation")

      Wizard.CreateDialog

      registration = RegistrationMock.new
      Registration::UI::AddonSelectionRegistrationDialog.run(registration)

      Wizard.CloseDialog

      true
    end
  end
end
