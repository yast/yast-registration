# Sources for installation

client_DATA = \
  clients/discover_registration_services.rb \
  clients/inst_scc.rb \
  clients/scc.rb \
  clients/scc_finish.rb

desktop_DATA = \
  desktop/customer_center.desktop

ylibdir = @ylibdir@/registration
ylib_DATA = \
  lib/registration/addon.rb \
  lib/registration/exceptions.rb \
  lib/registration/sw_mgmt.rb \
  lib/registration/storage.rb \
  lib/registration/repo_state.rb \
  lib/registration/helpers.rb

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/registration.rnc

EXTRA_DIST = $(client_DATA) $(desktop_DATA) $(ylib_DATA) $(schemafiles_DATA)

include $(top_srcdir)/Makefile.am.common
