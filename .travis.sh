#! /bin/bash

# exit on error immediately and print the executed commands
set -e -x

rake check:pot
rubocop
/usr/bin/yardoc.ruby2.2
# enable coveralls reports
COVERAGE=1 CI=1 TRAVIS=1 rake test:unit

# build the binary package locally, use plain "rpmbuild" to make it simple
rake tarball
cp package/* /usr/src/packages/SOURCES/
rpmbuild -bb package/*.spec

# test the %pre/%post script by installing/updating/removing the package
rpm -iv /usr/src/packages/RPMS/noarch/*.rpm
rpm -Uv --force /usr/src/packages/RPMS/noarch/*.rpm
rpm -ev yast2-registration
