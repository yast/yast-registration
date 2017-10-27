require_relative "spec_helper"

require "registration/erb_renderer.rb"

describe Registration::ErbRenderer do
  subject { Registration::ErbRenderer.new(::Registration::Storage::Config.instance) }

  it "renders an ERB file" do
    expect(subject.render_erb_template("autoyast_summary.erb")).to be_a(String)
  end
end
