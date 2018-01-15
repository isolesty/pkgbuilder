#! /bin/bash

set -e

declare -r scriptdir=$(dirname $(readlink -ef $0))
declare -r username=$(logname)

if [[ $EUID -ne 0 ]] ; then
    die "Root privilege is required to run setup script"
fi

[[ -n $username ]] || die "Can't get usename from setup script"

source conf/env
source lib/common

packages=(
    build-essential
    cowbuilder
    devscripts
    eatmydata
    git
#    git-review
    git-buildpackage
    tmux
    quilt
    dput
)

sudoers=examples/sudoers

info "Install required packages"
apt-get install -y ${packages[@]}

if [[ -f ${sudoers} ]] ; then
    info "Install sudoers configuration"
    install -m 600 -v $sudoers /etc/sudoers.d/deepin_pbuilder
    sed -e "s/deepin/$username/" -i /etc/sudoers.d/deepin_pbuilder
fi

info "create executable link"
ln -sfv ${scriptdir}/cowimage /usr/local/bin
ln -sfv ${scriptdir}/pkgbuilder /usr/local/bin

info "copy apt key"
cp -av /etc/apt/trusted.gpg.d/ ${scriptdir}/apt

info "Remove old executable"
if [[ -f /usr/local/bin/deepin-buildpackage ]] ; then
    rm -rf /usr/local/bin/deepin-buildpackage
fi

mkdir -pv ${WORKBASE}/artifacts
