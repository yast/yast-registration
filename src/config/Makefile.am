# Makefile.am for registration/config

desktop_DATA = suse_register.desktop customer_center.desktop

rncdir = $(schemadir)/autoyast/rnc
rnc_DATA = registration.rnc

fillup_DATA = sysconfig.suse_register-yast2-registration 

EXTRA_DIST = $(desktop_DATA) $(rnc_DATA) $(fillup_DATA)

include $(top_srcdir)/Makefile.am.common
