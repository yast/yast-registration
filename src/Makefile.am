# Sources for registration

module_DATA = \
  modules/Register.rb \
  modules/RegisterCert.pm \
  modules/YSR.pm

client_DATA = \
  clients/inst_suse_register.rb \
  clients/suse_register_auto.rb

yncludedir = @yncludedir@/registration
ynclude_DATA = \
  include/registration/texts.rb

scrconf_DATA = \
  scrconf/cfg_suse_register.scr

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/registration.rnc

desktop_DATA = \
  desktop/customer_center.desktop \
  desktop/suse_register.desktop

fillup_DATA = \
  fillup/sysconfig.suse_register-yast2-registration

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(scrconf_DATA) $(schemafiles_DATA) $(desktop_DATA) $(fillup_DATA)

include $(top_srcdir)/Makefile.am.common