#!/bin/bash

set -e

DEST_TEST_DIR=/opt/azurehpc/test
AZHC_DIR=/opt/azurehpc/test/azurehpc-health-checks

ssh -o StrictHostKeyChecking=no -t ${HOST_NAME} << EOF

sudo chown -R hpcuser /opt/azurehpc/test

pushd /opt/azurehpc/test/azurehpc-health-checks/lbnl-nhc-1.4.3
make uninstall
popd
rm -rf $AZHC_DIR

mkdir -p $DEST_TEST_DIR

pushd $DEST_TEST_DIR

# Clone PR branch using GITHUB_PR_NUMBER
if [ ! -z "${GITHUB_PR_NUMBER}" ]; then
    echo "##[debug] Cloning PR using GitHub PR number: ${GITHUB_PR_NUMBER}"
    git clone https://github.com/Azure/azurehpc-health-checks.git
    pushd azurehpc-health-checks
    git fetch origin pull/${GITHUB_PR_NUMBER}/head:test-branch
    git checkout test-branch
    popd
else
    # Get latest release of GH repo if GITHUB_PR_NUMBER does not exist
    AZHC_VERSION=$(curl -s https://api.github.com/repos/Azure/azurehpc-health-checks/releases/latest | grep tag_name | cut -d '"' -f 4)
    echo "##[debug] cloning azurehpc-health-checks latest release: ${AZHC_VERSION}"
    git clone https://github.com/Azure/azurehpc-health-checks.git --branch ${AZHC_VERSION}
fi

pushd azurehpc-health-checks

sudo ./install-nhc.sh

popd
popd


if command -v nhc &>/dev/null 2>&1; then
    echo "NHC installed successfully"
else
    echo "NHC installation failed"
    exit 1
fi

pushd $DEST_TEST_DIR/azurehpc-health-checks/test/unit-tests
if ./run_tests.sh happy_path; then
    echo "##[section]Happy path test passed"
else
    echo "##[error]Happy path test failed"
    exit 1
fi

if ./run_tests.sh sad_path; then
    echo "##[section]Sad path test passed"
else
    echo "##[error]Sad path test failed"
    exit 1
fi

popd

EOF