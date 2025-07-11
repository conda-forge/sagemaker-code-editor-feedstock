#!/bin/bash

set -exuo pipefail

# This code includes code from https://github.com/conda-forge/openvscode-server-feedstock 
# which is licensed under the BSD-3-Clause License.

cd code-editorv1.6.1
#pushd src

# Fix error 'Check failed: current == end_slot_index.' while running 'yarn list --prod --json'
# in nodejs 20.x
# See https://github.com/nodejs/node/issues/51555

export DISABLE_V8_COMPILE_CACHE=1

# Install node-gyp globally as a fix for NodeJS 18.18.2 https://github.com/microsoft/vscode/issues/194665
npm i -g node-gyp

# Install all dependencies except @vscode/ripgrep
VSCODE_RIPGREP_VERSION=$(jq -r '.dependencies."@vscode/ripgrep"' package.json)
mv package.json package.json.orig
jq 'del(.dependencies."@vscode/ripgrep")' package.json.orig > package.json

yarn install

# Install @vscode/ripgrep without downloading the pre-built ripgrep.
# This often runs into Github API ratelimits and we won't use the binary in this package anyways.
yarn add --ignore-scripts "@vscode/ripgrep@${VSCODE_RIPGREP_VERSION}"

ARCH_ALIAS=linux-x64
yarn gulp vscode-reh-web-${ARCH_ALIAS}-min
popd

mkdir -p $PREFIX/share
cp -r vscode-reh-web-${ARCH_ALIAS} ${PREFIX}/share/sagemaker-code-editor
rm -rf $PREFIX/share/sagemaker-code-editor/bin

mkdir -p ${PREFIX}/bin
cat <<'EOF' >${PREFIX}/bin/sagemaker-code-editor
#!/bin/bash
PREFIX_DIR=$(dirname ${BASH_SOURCE})
# Make PREDIX_DIR absolute
if [[ $(uname) == 'Linux' ]]; then
  PREFIX_DIR=$(readlink -f ${PREFIX_DIR})
else
  pushd ${PREFIX_DIR}
  PREFIX_DIR=$(pwd -P)
  popd
fi
# Go one level up
PREFIX_DIR=$(dirname ${PREFIX_DIR})
node "${PREFIX_DIR}/share/sagemaker-code-editor/out/server-main.js" "$@"
EOF
chmod +x ${PREFIX}/bin/sagemaker-code-editor

# Replace node ripgrep with conda package
mkdir -p ${PREFIX}/share/sagemaker-code-editor/node_modules/@vscode/ripgrep/bin
cat <<EOF >${PREFIX}/share/sagemaker-code-editor/node_modules/@vscode/ripgrep/bin/rg
#!/bin/bash
exec "${PREFIX}/bin/rg" "\$@"
EOF
chmod +x ${PREFIX}/share/sagemaker-code-editor/node_modules/@vscode/ripgrep/bin/rg
