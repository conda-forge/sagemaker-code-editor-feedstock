#!/bin/bash

set -exuo pipefail

# This code includes code from https://github.com/conda-forge/openvscode-server-feedstock 
# which is licensed under the BSD-3-Clause License.

pushd sagemaker-code-editor

# Next, we need use a wildcard (*) to enter the versioned directory.
# This matches any directory starting with 'code-editor', such as 'code-editorvx.y.z'.
# https://github.com/conda-forge/sagemaker-code-editor-feedstock/pull/70/checks In this pr, and the error said GXX=$BUILD_PREFIX/bin/x86_64-conda-linux-gnu-g++ ~/feedstock_root/build_artifacts/sagemaker-code-editor_1750277789375/work/sagemaker-code-editor ~/feedstock_root/build_artifacts/sagemaker-code-editor_1750277789375/work/home/conda/feedstock_root/build_artifacts/sagemaker-code-editor_1750277789375/work/conda_build.sh: line 12: pushd: src: No such file or directory
# Add the commands to fix the error and help to find the right directory

pushd src

# Fix error 'Check failed: current == end_slot_index.' while running 'yarn list --prod --json'
# in nodejs 20.x
# See https://github.com/nodejs/node/issues/51555

export DISABLE_V8_COMPILE_CACHE=1

# Limit Node.js memory usage to prevent OOM kills
# Add this because a previous PR solve the OOM Failures by adding this and we use the same commands
# See pr: https://github.com/conda-forge/sagemaker-code-editor-feedstock/pull/82/files
export NODE_OPTIONS="--max-old-space-size=4096"
export UV_THREADPOOL_SIZE=4

# Install node-gyp globally as a fix for NodeJS 18.18.2 https://github.com/microsoft/vscode/issues/194665
npm i -g node-gyp

# Limit concurrency to prevent OOM kills
# Add this because a previous PR solve the OOM Failures by adding this and we use the same commands
yarn install --network-concurrency 1

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
