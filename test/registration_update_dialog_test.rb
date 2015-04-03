#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::RegistrationUpdateDialog do
  subject { Registration::UI::RegistrationUpdateDialog }

  describe ".run" do
    before do
      expect(Yast::Wizard).to receive(:SetContents)
      expect(Registration::UrlHelpers).to receive(:registration_url).and_return(nil)
    end

    it "updates system registration, base and add-on products" do
      expect_any_instance_of(Registration::RegistrationUI).to receive(
        :update_system).and_return(true)
      allow_any_instance_of(Registration::RegistrationUI).to receive(
        :update_base_product).and_return([true,
                                          YAML.load_file(fixtures_file("remote_product.yml"))])
      allow_any_instance_of(Registration::RegistrationUI).to receive(
        :install_updates?).and_return(false)
      allow_any_instance_of(Registration::RegistrationUI).to receive(
        :disable_update_repos).and_return(true)
      allow_any_instance_of(Registration::RegistrationUI).to receive(
        :get_available_addons).and_return([])
      allow_any_instance_of(Registration::RegistrationUI).to receive(
        :update_addons).and_return([])

      expect(subject.run).to eq(:next)
    end
  end
end
