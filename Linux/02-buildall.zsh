#!/bin/zsh -f

setopt extendedglob
setopt err_exit
umask 022

DOC="\
${0:t} build all codes for the diffpy Linux bundle.
usage: ${0:t} [options] [N1] [N2] [FIRST-LAST]

With no arguments all packages are built in sequence.  Otherwise build
only packages given as arguments, where each argument is either a
single package number or an inclusive range of indices FIRST-LAST.
Use option --list for displaying package numbers.

Options:

  --list        show a numbered list of packages and exit
  -h, --help    display this message and exit

Environment variables can be used to override script defaults:

  PREFIX        base directory for installing the binaries [.]
  PYTHON        python executable used for the build [python]
  EASY_INSTALL  easy_install program used for the build [easy_install]
  SCONS         SCons program used for the build [scons]
  NCPU          number of CPUs used in parallel builds [all-cores].
"
DOC=${${DOC##[[:space:]]##}%%[[:space:]]##}
MYDIR="$(cd ${0:h} && pwd)"

# Parse Options --------------------------------------------------------------

zmodload zsh/zutil
zparseopts -K -E -D \
    h=opt_help -help=opt_help l=opt_list -list=opt_list

if [[ -n ${opt_help} ]]; then
    print -r -- $DOC
    exit
fi

typeset -U selection
for n; do
    if [[ $n == [[:digit:]]##-[[:digit:]]## ]]; then
        selection=( $selection {${n%%-*}..${n##*-}} )
    else
        selection=( $selection $n )
    fi
done

# Resolve parameters that can be overloaded from the environment -------------

: ${PREFIX:=${MYDIR}}
: ${PYTHON:==python}
: ${EASY_INSTALL:==easy_install}
: ${SCONS:==scons}
: ${NCPU:=$(${PYTHON} -c \
    'from multiprocessing import cpu_count; print cpu_count()')}

# Determine other parameters -------------------------------------------------

SRCDIR=${MYDIR}/src
BINDIR=${PREFIX}/bin
INCLUDEDIR=${PREFIX}/include
LIBDIR=${PREFIX}/lib
PYTHON_VERSION=$($PYTHON -c 'import sys; print "%s.%s" % sys.version_info[:2]')
PYTHONDIR=$LIBDIR/python${PYTHON_VERSION}/site-packages

# Adjust environment variables used in the build -----------------------------

export PATH=$BINDIR:$PATH
export LIBRARY_PATH=$LIBDIR:$LIBRARY_PATH
export LD_LIBRARY_PATH=$LIBDIR:$LD_LIBRARY_PATH
export CPATH=$INCLUDEDIR:$CPATH
export PYTHONPATH=$PYTHONDIR:$PYTHONPATH

# Define function for building or skipping the packages ----------------------

integer BIDX=0

ListSkipOrBuild() {
    local name=${1?}
    (( ++BIDX ))
    if [[ -n ${selection} && -z ${(M)selection:#${BIDX}} ]]; then
        return 0
    fi
    if [[ -n ${opt_list} ]]; then
        print $BIDX $name
        return 0
    fi
    local dashline="# $BIDX $name ${(l:80::-:):-}"
    print ${dashline[1,78]}
    # return false status to trigger the build section
    return 1
}

# Build commands here --------------------------------------------------------

if [[ -z ${opt_list} ]]; then
    mkdir -p $BINDIR $INCLUDEDIR $LIBDIR $PYTHONDIR
fi

cd $SRCDIR

ListSkipOrBuild pycifrw || {
    $EASY_INSTALL -N --zip-ok --prefix=$PREFIX \
        ${SRCDIR}/pycifrw/PyCifRW-*.tar.gz(om[1])
}

ListSkipOrBuild diffpy.Structure || {
    $EASY_INSTALL -ZN --prefix=$PREFIX ${SRCDIR}/diffpy.Structure
}

ListSkipOrBuild diffpy.utils || {
    $EASY_INSTALL -ZN --prefix=$PREFIX ${SRCDIR}/diffpy.utils
}

ListSkipOrBuild periodictable || {
    $EASY_INSTALL -ZN --prefix=$PREFIX ${SRCDIR}/periodictable
}

ListSkipOrBuild libObjCryst || {
    cd $SRCDIR/libobjcryst
    $SCONS -j $NCPU build=fast prefix=$PREFIX install
}

ListSkipOrBuild pyobjcryst || {
    cd $SRCDIR/pyobjcryst
    $SCONS -j $NCPU build=fast prefix=$PREFIX install
}

ListSkipOrBuild libdiffpy || {
    cd $SRCDIR/libdiffpy
    $SCONS -j $NCPU build=fast enable_objcryst=yes test
    $SCONS -j $NCPU build=fast enable_objcryst=yes prefix=$PREFIX install
}

ListSkipOrBuild diffpy.srreal || {
    cd $SRCDIR/diffpy.srreal
    $SCONS -j $NCPU build=fast prefix=$PREFIX install
}

ListSkipOrBuild sans/data_util || {
    cd ${SRCDIR}/sans/data_util
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild sans/sansdataloader || {
    cd ${SRCDIR}/sans/sansdataloader
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild sans/sansmodels || {
    cd ${SRCDIR}/sans/sansmodels
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild sans/pr_inversion || {
    cd ${SRCDIR}/sans/pr_inversion
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild diffpy.srfit || {
    $EASY_INSTALL -ZN --prefix=$PREFIX ${SRCDIR}/diffpy.srfit
}

# Skip when building on Mac OS X
[[ $OSTYPE == darwin* ]] ||
ListSkipOrBuild "copy boost libraries" || {
    typeset -aU boostdeplibs
    for f in $LIBDIR/**/*.so(*N); do
        boostdeplibs+=( 
            $(ldd $f | awk '$1 ~ /^libboost_/ && $2 == "=>" {print $3}')
        )
    done
    if [[ -n ${boostdeplibs} ]]; then
        rsync -a ${boostdeplibs} $LIBDIR/
    fi
    cd $LIBDIR
    for bp in ${boostdeplibs:t}; do
        tgt=${bp%.so*}.so
        [[ $bp -ef $tgt ]] || ln -sv ${bp} $tgt
    done
}
