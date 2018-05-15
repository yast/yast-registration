#! /bin/sh

# This script rolls back the registration status on the server
# You can optionally pass the target chroot directory as a parameter,
# the default is "/".

ROOT=${1:-/}

# print the progress in green so it is better visible
echo -e "\e[0;32mRestoring the registration status at ${ROOT}, \
this might take several minutes...\e[0m"

# run the rollback
chroot "$ROOT" SUSEConnect --rollback
