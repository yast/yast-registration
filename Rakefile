require "yast/rake"

yast_submit = ENV["YAST_SUBMIT"] || :sle12sp1
Yast::Tasks.submit_to(yast_submit.to_sym)

Yast::Tasks.configuration do |conf|
  # lets ignore license check for now
  conf.skip_license_check << /.*/
end
