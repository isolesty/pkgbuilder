#! /bin/bash
# TODO:
#   1. rewrite
#   2. cowbuilder support
#   3. git-buildpackage
# Features:
#   1. gerrit/git-review support
#   2. pbuilder support

set -e

declare -r WORKBASE=/mnt/packages
declare -r BASEURI=http://cr.deepin.io
declare -r REPOBASE=${WORKBASE}/git-repos
declare -r SVERSION="v0.0.1"
declare -r DPKGBOPTIONS="-us -uc -sa -j8"
declare -i CHANGELIST=

declare BOPTS=
declare PKGVER=
declare -i usepbuilder=1
declare targetbranch=master

declare -r dde_components=(
    dde-account-faces
    dde-api
    dde-calendar
    dde-control-center
    dde-daemon
    dde-desktop
    dde-dock
    dde-file-manager
    dde-help
    dde-launcher
    dde-session-ui
    libdui
    startdde
)

declare -r raccoon_components=(
    dbus-factory
    dde-api
    dde-control-center
    dde-daemon
    dde-desktop
    dde-dock
    dde-launcher
    dde-session-ui
    deepin-desktop-base
    deepin-desktop-schemas
    startdde
)

printVersion() {
    echo "$0 version $SVERSION"
    exit 0
}

printHelp() {
    cat <<EOF >&2
Usage:
  $0 [-c CHANGELOG] [-l NUMBER] -n PKGNAME [-t BRANCH] [-w WORKDIR] [-b|-p] [-h] [-v]

Build script for deepin mipsel package team

Help Options:
  -h, --help            Show help options
Application Options:
  -c, --changelog=CHANGELOG    Use CHANGELOG as debian package changelog
  -l, --cl=NUMBER              Build package based on a CL: NUMBER
  -n, --pkgname=PKGNAME        Build PKGNAME
  -t, --target-branch=BRANCH   Check out to specific BRANCH
  -w, --workdir=DIR            Override the default WORKDIR
  -b, --build                  Perform a package build using debuild
  -p, --pbuilder               Perform a package build using pbuilder (recommended for a clean buid)
  -v, --version                Show version

Note:
Unless -p or -b option is specified, otherwise the script will help you to prepare for a package building
EOF
    exit 0
}

die() {
    echo "$BASH_LINENO: $@" >&2
    exit 1
}

has_bin() {
    local executable=$1
    if [[ -n $(type $1) ]] ; then
        return 0
    else
        return 1
    fi
}

configGitReview() {
    echo "create per project gitreview configuration"
    if [[ ! -f .gitreview ]] ; then
        cat <<EOF > .gitreview
[gerrit]
defaultremote = origin
EOF
    fi
}

downloadGerritChange() {
    if has_bin git-review ; then
        git review -d $1
    else
        die "No git-review package in the system!!!"
    fi
}

assert() {
    local ret
    eval ret=\$${1}
    [[ -n $ret ]] || die "I'm confused, var: ${1} is empty"
}

pushd() {
    builtin pushd $@ >& /dev/null
}

popd() {
    builtin popd $@ >& /dev/null
}

contains() {
    local element=
    local result=1
    for element in ${@:2}; do
    if [[ $element == $1 ]] ; then
        result=0
        break
    fi
    done
    echo $result
}

createdir() {
    local dir=$1
    local desc=$2
    if [[ ! -d ${dir} ]];then
        echo "create $2 directory: $dir"
        mkdir -p $dir
    fi
}

has_patch() {
    if [[ -d $patchdir ]] ; then
        return 0
    else
        return 1
    fi
}

pkgIsDebianized() {
    if [[ -d debian ]] ; then
        return 0
    else
        return 1
    fi
}

dquilt() {
    local quiltrc=${HOME}/.quiltrc-dpkg

    if [[ ! -f $quiltrc ]] ; then
        echo "Write quilt configuration: $quiltrc"

        cat <<'EOF' >>$quiltrc
d=. ; while [ ! -d $d/debian -a `readlink -e $d` != / ]; do d=$d/..; done
if [ -d $d/debian ] && [ -z $QUILT_PATCHES ]; then
    # if in Debian packaging tree with unset $QUILT_PATCHES
    QUILT_PATCHES="debian/patches"
    QUILT_PATCH_OPTS="--reject-format=unified"
    QUILT_DIFF_ARGS="-p ab --no-timestamps --no-index --color=auto"
    QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
    QUILT_COLORS="diff_hdr=1;32:diff_add=1;34:diff_rem=1;31:diff_hunk=1;33:diff_ctx=35:diff_cctx=33"
    if ! [ -d $d/debian/patches ]; then mkdir $d/debian/patches; fi
fi
EOF
    fi

    quilt --quiltrc=${quiltrc} -f $@
}

debsrcFormatter() {
    local sformat=
    local sformatfile=debian/source/format
    local quilt="3.0 (quilt)"

    if [[ -f $sformatfile ]] ; then
        sformat=$(cat $sformatfile)
    fi

    if [[ $sformat =~ 3.0[[:space:]]\((native|quilt)\) ]] ; then
    echo "${pkgname} has debsrc 3.0 format: $sformat"
    fi

    if has_patch; then
        echo "Found patches, set package source format to debsrc 3.0 quilt"
        sformat=$quilt
        createdir ${sformatfile//format}; echo $sformat > ${sformatfile}
    fi

    if [[ $sformat == $quilt ]] ; then
        PKGVER="${PKGVER}-1"
        echo -e "\n\n\n\n\t\t\tI'm here PKGVER=${PKGVER}\n\n\n"
    fi
}

fixBuildDeps() {
    echo "Replace golang-go in build deps with gccgo-5"
    if pkgIsDebianized ; then
        sed -e 's@golang-go\s*,@gccgo-5 | &@g' -i debian/control
    fi
}

fixDebuildOptions() {
    if pkgIsDebianized ; then
        if grep -wqs golang-go debian/control ; then
            echo "Golang package detected, trying to fix debuild option"
            BOPTS+="-e USE_GGCGO=1 -e CGO_ENABLED=1 "
        fi
    fi

    [[ $pkgname == deepin-file-manager-backend ]] && \
        BOPTS+="-e CGO_LDTHREAD=-lpthread"

    # pkgname test maybe fail, force return true
    return 0
}

apply_patches() {
    pkgIsDebianized || \
        die "You should debianize your package, workdir: $PWD!!!"

    if has_patch $patchdir ; then
    debsrcFormatter

        for patch in $patchdir/*.patch; do
            echo "Import mipsel specific patch: $(basename $patch)"
            dquilt import $patch
        done
    fi
}

hasPbuilderChroot() {
    if [[ -f ${WORKBASE}/deepin-base.tgz ]] ; then
        return 0
    else
        return 1
    fi
}

initializePbuilder() {
    has_bin pbuilder || die "Install pbuilder!!!"

    # Should I use options instead of configuration?
    echo "Initialize pbuilder configuration"

    if [[ ! -f ${HOME}/.pbuilderrc ]] ; then
    cat <<EOF > ${HOME}/.pbuilderrc
AUTO_DEBSIGN=no
BINDMOUNT="$WORKBASE"
MIRRORSITE="http://192.168.1.135/debian-mipsel"
OTHERMIRROR="deb http://pools.corp.deepin.com/mipsel-experimental unstable main | deb http://192.168.1.135/mipsel-staging raccoon main"
ALLOWUNTRUSTED=yes
DEBOOTSTRAPOPTS=( '--variant=buildd' '--no-check-gpg' )
EOF
    fi

    createdir ${WORKBASE}/deepin-chroot
    sudo pbuilder create ${PBUILDEROPTS[@]}
}

print_build_info() {
cat <<EOF
We're working on
    pkgname:        $pkgname
    workdir:        $workdir
    changelog:      $changelog
    CL:             $CHANGELIST
    repository:     $repository
EOF
}

[[ $EUID -eq 0 ]] && die "Don't build package with priviledged users"

OPTS=$(getopt -n build-package -o 'c:l:n:B:w:bhpv' \
          --long changelog:,cl:,pkgname:,workdir:,build,help,pbuilder,version -- "$@")

[[ $? -eq 0 ]] || die "Sorry! I don't understand!!!"

eval set -- "${OPTS}"

while : ; do
    case $1 in
        -c|--changelog)
            changelog=$2
            shift 2
            ;;
        -l|--cl)
            CHANGELIST=$2
            [[ $CHANGELIST -eq 0 ]] && die "CL $CHANGELIST is illegal"
            shift 2
            ;;
        -n|--pkgname)
            pkgname=$2
            shift 2
            ;;
        -p|--pbuilder)
            usepbuilder=0
            shift
            ;;
        -w|--workdir)
            workdir=${WORKBASE}/${2}
            shift 2
            ;;
        -t|--target-branch)
            targetbranch=$2
            shift 2
            ;;
        -b|--build)
            do_build=0
            shift
            ;;
        -v|--version)
            printVersion
            shift
            ;;
        -h|--help)
            printHelp
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            printHelp
            shift
            ;;
    esac
done

assert pkgname

declare -ar PBUILDEROPTS=(
    "--buildresult ${WORKBASE}/${pkgname}"
    "--basetgz ${WORKBASE}/deepin-base.tgz"
    "--buildplace ${WORKBASE}/deepin-chroot"
    "--hookdir   ${WORKBASE}/buildpkg/pbuilder-hook.d"
)

# sane default values
[[ -z $workdir ]]      && workdir=${WORKBASE}/${pkgname}
[[ -z $changelog ]]    && changelog="Rebuild on mipsel"

createdir $workdir
createdir $REPOBASE

# set git repository
if [[ $(contains $pkgname ${dde_components[@]}) -eq 0 ]]; then
    repository=${BASEURI}/dde/${pkgname}
else
    if [[ ${pkgname} = lastore-daemon* ]]; then
        repository=${BASEURI}/lastore/${pkgname}
    else
        repository=${BASEURI}/${pkgname}
    fi
fi

[[ ${pkgname} == deepin-default-settings ]] && \
    repository=${BASEURI}/${pkgname##deepin-}

patchdir=${WORKBASE}/patches/${pkgname}

make_orig_tarball() {
    local work_branch=${targetbranch}
    local repodir=${REPOBASE}/${pkgname}
    local has_raccoon=$(contains ${pkgname} ${raccoon_components[@]})

    if [[ $has_raccoon -eq 0 ]] ; then
        work_branch=raccoon
        if [[ $work_branch != $targetbranch ]] ; then
            echo -e "\n\n\n\t\tworking branch is not the target branch\n\n\n"
        fi
    fi

    echo "Current branch is $work_branch"

    has_bin git || die "No git package in the system"

    # fetch git repository
    [[ -d ${repodir}/.git ]] || git clone -b ${work_branch} ${repository} ${repodir}

    pushd ${repodir}

    # in case we need to switch branches
    git checkout -B ${work_branch} --track origin/${work_branch}
    git pull origin ${work_branch}

    local commit_id=$(git rev-parse HEAD | cut -b 1-6)
    assert commit_id
    local tag=$(git describe --tags --abbrev=0)
    local revision=$(git log ${tag}..origin/${work_branch} --oneline | wc -l)
    assert revision

    if [[ -z ${tag} ]] ;then
        echo "tag fallback to 0.1"
        tag=0.1
    fi
    assert tag

    # gerrit CL workflow
    if [[ ${CHANGELIST} -gt 1 ]] ; then
        configGitReview
        downloadGerritChange $CHANGELIST
        PKGVER=$tag+cl~$CHANGELIST
    else
        PKGVER=$tag+r${revision}~${commit_id}
    fi

    echo "Create ${pkgname} upstream source tarball..."
    git archive --format=tar --prefix=${pkgname}-${PKGVER}/ HEAD | \
        xz -z > ${workdir}/${pkgname}_${PKGVER}.orig.tar.xz

    popd
}

prepare_build() {
    rm -rf ${workdir}/${pkgname}-${PKGVER}
    pushd ${workdir}
    tar xf ${pkgname}_${PKGVER}.orig.tar.xz
    popd

    pushd ${workdir}/${pkgname}-${PKGVER}
    if ! pkgIsDebianized ; then
        cp -a ${WORKBASE}/pkg_debian/${pkgname}/debian .
    fi
    popd
}

build_package() {
    pushd ${workdir}/${pkgname}-${PKGVER}

    # Apply patches unless build official package (Not from any CL)
    [[ $CHANGELIST -eq 0 ]] && apply_patches

    fixBuildDeps
    fixDebuildOptions

    if [[ $do_build -eq 0 ]] ; then
        dch -v ${PKGVER} -D unstable $changelog
        if [[ $usepbuilder -eq 0 ]] ; then
            export ${BOPTS}
            hasPbuilderChroot || initializePbuilder
            eval pdebuild --use-pdebuild-internal --debbuildopts '"${DPKGBOPTIONS}"' \
		-- ${PBUILDEROPTS[@]}
        else
            echo "Debuild options: ${BOPTS} ${DPKGBOPTIONS}"
            eval debuild ${BOPTS} ${DPKGBOPTIONS}
        fi
    fi
    popd
}

make_orig_tarball
prepare_build
build_package

# vim: number tabstop=4 softtabstop=4 expandtab
