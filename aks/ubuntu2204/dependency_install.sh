# Dependencies 

git clone https://github.com/Azure/azurehpc-health-checks.git

sudo apt install -y pciutils ibutils

wget https://github.com/mej/nhc/releases/download/1.4.3/lbnl-nhc-1.4.3.tar.gz

tar -xvf lbnl-nhc-1.4.3.tar.gz

cd lbnl-nhc-1.4.3/
  
./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec
make test
make install

cp nhc ../azurehpc-health-checks/
cd ../azurehpc-health-checks/

# Install kvp_client.c

DEST_DIR=/opt/azurehpc/tools
mkdir -p $DEST_DIR

wget https://raw.githubusercontent.com/microsoft/lis-test/master/WS2012R2/lisa/tools/KVP/kvp_client.c

mv ./kvp_client.c $DEST_DIR

gcc $DEST_DIR/kvp_client.c -o $DEST_DIR/kvp_client

# Copy custom Azure NHC files to path that NHC searches

# cp customTests/* /etc/nhc/scripts/

cp aks/ubuntu2204/aksConf/* /etc/nhc/scripts/