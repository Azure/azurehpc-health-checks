#!/bin/bash

NHC_VERSION=1.4.3

wget -O nhc-$NHC_VERSION.tar.xz https://github.com/mej/nhc/releases/download/1.4.3/lbnl-nhc-1.4.3.tar.xz
tar -xf nhc-$NHC_VERSION.tar.xz

cd lbnl-nhc-$NHC_VERSION
./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec
sudo make test
sudo make install
