# To change this license header, choose License Headers in Project Properties.
# To change this template file, choose Tools | Templates
# and open the template in the editor.

require 'set'

module Registration
  class Addon
    # product data needed for registration
    attr_reader :name, :version, :arch
    # additional data: UI labels, dependencies on other add-ons and
    # a flag indicating required registration key
    attr_reader :label, :description, :depends_on, :regkey_needed

    def initialize(name, version, arch, label: "", description: "",
        depends_on: [], regkey_needed: true)
      @name = name
      @version = version
      @arch = arch
      @label = label
      @description = description
      @depends_on = depends_on
      @regkey_needed = regkey_needed
    end

    def required_addons
      # TODO evaluate all @depends_on addons to get a flat list
    end
  end

end
