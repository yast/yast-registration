require "yast/rake"

Yast::Tasks.configuration do |conf|
  # lets ignore license check for now
  conf.skip_license_check << /.*/

  # use IBS (the internal BS instance)
  conf.obs_api = "https://api.suse.de/"

  # where to submit the package
  conf.obs_project = "Devel:YaST:Head"

  # target project for submit requests
  conf.obs_sr_project = "SUSE:SLE-12:GA"

  # BS build target (repository)
  conf.obs_target = "SLE-12"
end

