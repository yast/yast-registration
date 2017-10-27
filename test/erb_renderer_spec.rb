require_relative "spec_helper"

require "registration/erb_renderer.rb"

describe Registration::ErbRenderer do
  subject { Registration::ErbRenderer.new(Registration::Storage::Config.instance) }

  it "renders the ERB file as String" do
    expect(subject.render_erb_template("autoyast_summary.erb")).to be_a(String)
  end

  it "renders the AY configuration" do
    result = subject.render_erb_template("autoyast_summary.erb")
    # test the header, it is always present regardless the actual AY configuration
    expect(result).to include("Product Registration")
  end
end
