#
# spec file for package yast2-registration
#
# Copyright (c) 2014 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-registration
Version:        3.1.166
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Group:          System/YaST
License:        GPL-2.0

# Popup.Feedback
Requires:       yast2 >= 3.1.26
# "dupAllowVendorChange" option in Pkg.SetSolverFlags()
Requires:       yast2-pkg-bindings >= 3.1.27
# N_() method
Requires:       yast2-ruby-bindings >= 3.1.12
Requires:       rubygem(suse-connect) >= 0.2.22

# NOTE: Workaround for bsc#947482, SUSEConnect is actually not needed by the
# YaST registration module, it is used just to install the Connect dependencies.
#
# TODO: Remove it once the SUSEConnect dependencies are properly moved to the
# suse-connect gem.
Requires:       SUSEConnect

Requires:       yast2-slp >= 3.1.2
Requires:       yast2-add-on >= 3.1.8
Requires:       yast2-packager >= 3.1.26
Requires:       yast2-update >= 3.1.19

BuildRequires:  yast2 >= 3.1.26
BuildRequires:  update-desktop-files
BuildRequires:  yast2-devtools >= 3.1.6
BuildRequires:  rubygem(yast-rake) >= 0.2.5
BuildRequires:  rubygem(rspec)
BuildRequires:  rubygem(suse-connect) >= 0.2.22
BuildRequires:  yast2-slp >= 3.1.2
BuildRequires:  yast2-packager >= 3.1.26
BuildRequires:  yast2-update >= 3.1.19

BuildArch:      noarch

Summary:        YaST2 - Registration Module
Url:            https://github.com/yast/yast-registration

%description
The registration module to register products and/or to fetch an update
source (mirror) automatically.


Authors:
--------
    Ladislav Slezak <lslezak@suse.cz>

%prep
%setup -n %{name}-%{version}

%build

%check
rake test:unit

%install
rake install DESTDIR="%{buildroot}"
%suse_update_desktop_file customer_center


%files
%defattr(-,root,root)
%{yast_desktopdir}/customer_center.desktop
%{yast_clientdir}/*.rb
%{yast_ydatadir}/registration
%{yast_schemadir}/autoyast/rnc/*.rnc
%{yast_libdir}/registration
%{yast_libdir}/yast
%{yast_libdir}/yast/suse_connect.rb
%doc %{yast_docdir}

%changelog
