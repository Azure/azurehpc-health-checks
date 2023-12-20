#!/bin/bash

INSTALL_DIR=$1
CUDA_DIR=$2

if [[ -z "$INSTALL_DIR" ]];then
  INSTALL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

if [[ -z "$CUDA_DIR" ]];then
	CUDA_DIR=/usr/local/cuda
fi

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# not using src directory as insatll location
if [ $SRC_DIR != $INSTALL_DIR ]; then
  INSTALL_DIR=$INSTALL_DIR/azurehpc-health-checks
fi

export AZ_NHC_VERSION_LOG=$INSTALL_DIR/docs/version.log

function install_lbnl_nhc(){
  pushd $SRC_DIR/build
  NHC_VERSION=1.4.3
  wget -O nhc-$NHC_VERSION.tar.xz https://github.com/mej/nhc/releases/download/${NHC_VERSION}/lbnl-nhc-${NHC_VERSION}.tar.xz
  tar -xf nhc-$NHC_VERSION.tar.xz
  rm -f nhc-$NHC_VERSION.tar.xz
  pushd lbnl-nhc-$NHC_VERSION

  . /etc/os-release
  case $ID in
    ubuntu)  
      LIBEXEDIR=/usr/lib;;
    *) 
      LIBEXEDIR=/usr/libexec;;
  esac
  ./configure --prefix=/usr --sysconfdir=/etc --libexecdir=$LIBEXEDIR
  
  sudo make test
  echo -e "\n"
  sudo make install
  echo "NHC version: $NHC_VERSION" >> $AZ_NHC_VERSION_LOG
  popd
  popd

}


mkdir -p $INSTALL_DIR
mkdir -p $INSTALL_DIR/bin
mkdir -p $SRC_DIR/build
mkdir -p $INSTALL_DIR/docs


# create version log
AZVER=$(git describe --tags --abbrev=0)
cat > "$AZ_NHC_VERSION_LOG" <<EOL
This file contains the version of AzureHPC Health Checks and submodules.
Azure-NHC: $AZVER
submodules:
EOL


# install lbnl nhc
install_lbnl_nhc 

# Install NHC dependencies
distro=`awk -F= '/^NAME/{print $2}' /etc/os-release`
if [[ $distro =~ "Ubuntu" ]]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libpci-dev hwloc build-essential libboost-program-options-dev libssl-dev cmake
elif [[ $distro =~ "AlmaLinux" ]]; then
  sudo dnf install -y pciutils-devel hwloc openssl-devel boost-devel cmake
elif [[ $distro =~ "CentOS" ]]; then
  sudo yum install -y  pciutils-devel hwloc openssl-devel boost-devel cmake > /dev/null
  echo "CentOS version is not officially supported, proceed w/ caution."
else
  echo "OS version is not supported, Perf-test build skipped. Proceed w/ caution."
  return 1
fi

# Install build tools
# Check cmake version + install if necessary
output=$(cmake --version | sed -n 1p | sed 's/[^0-9]*//g')
export NHC_CMAKE=cmake
if [ $output -lt 3200 ]; then
    echo "Upgrade cmake version to 3.20 or above to build nvbandwidth"
    pushd $SRC_DIR/build
      wget -q -O cmake.sh https://github.com/Kitware/CMake/releases/download/v3.28.0/cmake-3.28.0-linux-x86_64.sh
      chmod +x cmake.sh
      mkdir -p cmake
      ./cmake.sh --skip-license --prefix=./cmake
      export NHC_CMAKE=$(pwd)/cmake/bin/cmake
      rm cmake.sh
    popd
fi

# Copy over necessary files
sudo cp $SRC_DIR/customTests/*.nhc /etc/nhc/scripts

if [ $SRC_DIR != $INSTALL_DIR ]; then
  cp -r $SRC_DIR/conf/ $INSTALL_DIR
  cp -r $SRC_DIR/distributed_nhc/ $INSTALL_DIR
  cp $SRC_DIR/*.md $INSTALL_DIR/docs/
  cp $SRC_DIR/LICENSE $INSTALL_DIR/docs/
  cp $SRC_DIR/run-health-checks.sh $INSTALL_DIR
fi
cp -r $SRC_DIR/customTests/topofiles/ $INSTALL_DIR

# Install NHC custom tests
pushd customTests/
./custom-test-setup.sh $INSTALL_DIR $CUDA_DIR
popd

# create env file
env_file="$INSTALL_DIR/aznhc_env_init.sh"

cat > "$env_file" <<EOL
#!/bin/bash
# This file is used to source the NHC environment variables
# It is recommended to source this file in your .bashrc or .bash_profile
# to make the NHC commands available in your shell.
export AZ_NHC_ROOT=$INSTALL_DIR
alias aznhc="sudo $INSTALL_DIR/run-health-checks.sh"
EOL

chmod +x "$env_file"

exit 0
