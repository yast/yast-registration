FROM opensuse:tumbleweed
RUN zypper ar -f http://download.opensuse.org/repositories/YaST:/Head/openSUSE_Tumbleweed/ yast
RUN zypper --gpg-auto-import-keys --non-interactive in \
      fdupes \
      grep \
      yast2 \
      yast2-devtools \
      'rubygem(yast-rake)' \
      'rubygem(rspec)' \
      'rubygem(suse-connect)' \
      'rubygem(gettext)' \
      'rubygem(rubocop)' \
      'rubygem(simplecov)' \
      yast2-slp \
      yast2-packager \
      yast2-update \
      update-desktop-files \
      yast2-add-on \
      git \
      rpm-build \
      which
# FIXME: fix the dependency issues in YaST:Head and install them via zypper
RUN gem install --no-document coveralls yard
COPY . /tmp/sources
WORKDIR /tmp/sources

