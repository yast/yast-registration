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
Version:        3.1.168
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

# Install extra packages for running additional tests at the Jenkins CI builds.
# run manually: osc build --define "run_ci_tests 1"
# from sources: rake osc:build['--define "run_ci_tests 1"']
%if 0%{?run_ci_tests}
BuildRequires:  rubygem(yast-rake-ci)
%endif


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
%if 0%{?run_ci_tests}
  LC_ALL=en_US.UTF-8 \
    COVERALLS_REPO_TOKEN='%{coveralls_repo_token}' \
    CI_PULL_REQUEST='%{ci_pull_request}' \
    JENKINS_URL='%{jenkins_url}' \
    BUILD_URL='%{build_url}' \
    GIT_BRANCH='%{git_branch}' \
    GIT_COMMIT='%{git_commit}' \
    GIT_ID='%{git_commit}' \
    GIT_AUTHOR_NAME='%{git_author_name}' \
    GIT_AUTHOR_EMAIL='%{git_author_email}' \
    GIT_COMMITTER_NAME='%{git_commiter_name}' \
    GIT_COMMITTER_EMAIL='%{git_commiter_email}' \
    GIT_MESSAGE='%{git_message}' \
    COVERAGE=1 CI=1 \
    rake --verbose --trace check:ci
%else
  rake test:unit
%endif

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
