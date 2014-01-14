require "yast/rake"

Yast::Tasks.configuration do |conf|
  # lets ignore license check for now
  conf.skip_license_check << /.*/

  # use IBS (the internal BS instance)
  conf.obs_api = "https://api.suse.de/"

  # where to submit the package
  conf.obs_project = "Devel:YaST:Head"

  # target project for submit requests
  # (SUSE:Factory:Head:Internal is for packages *not* in openSUSE)
  conf.obs_sr_project = "SUSE:Factory:Head:Internal"

  # BS build target (repository)
  conf.obs_target = "factory"
end

