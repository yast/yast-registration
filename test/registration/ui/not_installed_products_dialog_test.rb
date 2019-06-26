#!/usr/bin/env rspec
# typed: false
# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require_relative "../../spec_helper"
require "registration/ui/not_installed_products_dialog"

describe Registration::UI::NotInstalledProductsDialog do
  describe "#run" do
    before do
      allow(Yast::UI).to receive(:OpenDialog)
      allow(Yast::UI).to receive(:CloseDialog)
      allow(Yast::UI).to receive(:SetFocus)

      allow(Yast::Popup).to receive(:Feedback).and_yield
      allow(subject).to receive(:handle_dialog)

      # the translated strings are frozen
      allow(subject).to receive(:_), &:freeze
    end

    context "when there is a registered but not installed product" do
      before do
        allow(Registration::Addon).to receive(:registered_not_installed).and_return(
          [
            double(name: "not_installed_product")
          ]
        )
      end

      it "displays a product summary popup" do
        expect(Yast::UI).to receive(:OpenDialog) do |_opts, content|
          # find the RichText widget in the content
          term = content.nested_find do |t|
            t.respond_to?(:value) && t.value == :RichText
          end

          expect(term.params[1]).to match(/registered but not installed: .*not_installed_product/)
        end

        subject.run
      end
    end
  end
end
