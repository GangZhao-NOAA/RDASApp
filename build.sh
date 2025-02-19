#!/bin/bash

# build.sh
# 1 - determine host, load modules on supported hosts; proceed w/o otherwise
# 2 - configure; build; install
# 4 - optional, run unit tests

set -eu
START=$(date +%s)
dir_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $dir_root/ush/detect_machine.sh

# ==============================================================================
usage() {
  set +x
  echo
  echo "Usage: $0 -p <prefix> | -t <target> -h"
  echo
  echo "  -p  installation prefix <prefix>    DEFAULT: <none>"
  echo "  -t  target to build for <target>    DEFAULT: $MACHINE_ID"
  echo "  -c  additional CMake options        DEFAULT: <none>"
  echo "  -v  build with verbose output       DEFAULT: NO"
  echo "  -f  force a clean build             DEFAULT: NO"
  echo "  -d  include JCSDA ctest data        DEFAULT: NO"
  echo "  -r  include rrfs-ctest data         DEFAULT: NO"
  echo "  -a  build everything in bundle      DEFAULT: NO"
  echo "  -m  select dycore                   DEFAULT: FV3andMPAS"
  echo "  -h  display this message and quit"
  echo
  exit 1
}

# ==============================================================================

# Defaults:
INSTALL_PREFIX=""
CMAKE_OPTS=""
BUILD_TARGET="${MACHINE_ID:-'localhost'}"
BUILD_VERBOSE="NO"
CLONE_JCSDADATA="NO"
CLONE_RRFSDATA="NO"
CLEAN_BUILD="NO"
BUILD_JCSDA="NO"
DYCORE="FV3andMPAS"
COMPILER="${COMPILER:-intel}"

while getopts "p:t:c:m:hvdfar" opt; do
  case $opt in
    p)
      INSTALL_PREFIX=$OPTARG
      ;;
    t)
      BUILD_TARGET=$OPTARG
      ;;
    c)
      CMAKE_OPTS=$OPTARG
      ;;
    m)
      DYCORE=$OPTARG
      ;;
    v)
      BUILD_VERBOSE=YES
      ;;
    d)
      CLONE_JCSDADATA=YES
      ;;
    r)
      CLONE_RRFSDATA=YES
      ;;
    f)
      CLEAN_BUILD=YES
      ;;
    a)
      BUILD_JCSDA=YES
      ;;
    h|\?|:)
      usage
      ;;
  esac
done

case ${BUILD_TARGET} in
  hera | orion | hercules)
    echo "Building RDASApp on $BUILD_TARGET"
    echo "  Build initiated `date`"
    source $dir_root/ush/module-setup.sh
    module use $dir_root/modulefiles
    module load RDAS/$BUILD_TARGET.$COMPILER
    CMAKE_OPTS+=" -DMPIEXEC_EXECUTABLE=$MPIEXEC_EXEC -DMPIEXEC_NUMPROC_FLAG=$MPIEXEC_NPROC -DBUILD_GSIBEC=ON -DMACHINE_ID=$MACHINE_ID"
    module list
    ;;
  $(hostname))
    echo "Building RDASApp on $BUILD_TARGET"
    ;;
  *)
    echo "Building RDASApp on unknown target: $BUILD_TARGET"
    ;;
esac

CMAKE_OPTS+=" -DCLONE_JCSDADATA=$CLONE_JCSDADATA -DCLONE_RRFSDATA=$CLONE_RRFSDATA"

BUILD_DIR=${BUILD_DIR:-$dir_root/build}
if [[ $CLEAN_BUILD == 'YES' ]]; then
  [[ -d ${BUILD_DIR} ]] && rm -rf ${BUILD_DIR}
fi
mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR}

# If INSTALL_PREFIX is not empty; install at INSTALL_PREFIX
[[ -n "${INSTALL_PREFIX:-}" ]] && CMAKE_OPTS+=" -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}"

# activate tests based on if this is cloned within the global-workflow
WORKFLOW_BUILD=${WORKFLOW_BUILD:-"OFF"}
CMAKE_OPTS+=" -DWORKFLOW_TESTS=${WORKFLOW_BUILD}"

# determine which dycore to use
if [[ $DYCORE == 'FV3' ]]; then
  CMAKE_OPTS+=" -DFV3_DYCORE=ON"
  builddirs="fv3-jedi iodaconv"
elif [[ $DYCORE == 'MPAS' ]]; then
  CMAKE_OPTS+=" -DFV3_DYCORE=OFF -DMPAS_DYCORE=ON"
  builddirs="mpas-jedi iodaconv"
elif [[ $DYCORE == 'FV3andMPAS' ]]; then
  CMAKE_OPTS+=" -DFV3_DYCORE=ON -DMPAS_DYCORE=ON"
  builddirs="fv3-jedi mpas-jedi iodaconv"
else
  echo "$DYCORE is not a valid dycore option. Valid options are FV3 or MPAS"
  exit 1
fi

# JCSDA changed test data things, need to make a dummy CRTM directory
if [[ $BUILD_TARGET == 'hera' ]]; then
  if [ -d "$dir_root/bundle/fix/test-data-release/" ]; then rm -rf $dir_root/bundle/fix/test-data-release/; fi
  if [ -d "$dir_root/bundle/test-data-release/" ]; then rm -rf $dir_root/bundle/test-data-release/; fi
  mkdir -p $dir_root/bundle/fix/test-data-release/
  mkdir -p $dir_root/bundle/test-data-release/
  ln -sf $RDASAPP_TESTDATA/crtm $dir_root/bundle/fix/test-data-release/crtm
  ln -sf $RDASAPP_TESTDATA/crtm $dir_root/bundle/test-data-release/crtm
fi

  CMAKE_OPTS+=" -DMPIEXEC_MAX_NUMPROCS:STRING=120"
# Configure
echo "Configuring ..."
set -x
cmake \
  ${CMAKE_OPTS:-} \
  $dir_root/bundle
set +x

# Build
echo "Building ..."
set -x
if [[ $BUILD_JCSDA == 'YES' ]]; then
  make -j ${BUILD_JOBS:-6} VERBOSE=$BUILD_VERBOSE
else
  for b in $builddirs; do
    cd $b
    make -j ${BUILD_JOBS:-6} VERBOSE=$BUILD_VERBOSE
    cd ../
  done
fi
set +x

# Install
if [[ -n ${INSTALL_PREFIX:-} ]]; then
  echo "Installing ..."
  set -x
  make install
  set +x
fi

echo build finished: `date`
END=$(date +%s)
DIFF=$((END - START))
echo "Time taken to run the code: $DIFF seconds"
exit 0
