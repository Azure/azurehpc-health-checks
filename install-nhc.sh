#!/bin/bash

NHC_VERSION=1.4.3
echo "Installed NHC verison $NHC_VERSION"

wget -O nhc-$NHC_VERSION.tar.xz https://github.com/mej/nhc/releases/download/1.4.3/lbnl-nhc-1.4.3.tar.xz
tar -xf nhc-$NHC_VERSION.tar.xz

cd lbnl-nhc-$NHC_VERSION
./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec

sudo make test
echo -e "\n"
sudo make install

echo -e "\nRunning set up script for custom tests"
pushd customTests/
./custom-test-setup.sh
popd