#!/bin/bash

set -exuo pipefail

# This code includes code from https://github.com/conda-forge/openvscode-server-feedstock 
# which is licensed under the BSD-3-Clause License.

pushd sagemaker-code-editor
pushd src

# Fix error 'Check failed: current == end_slot_index.' while running 'yarn list --prod --json'
# in nodejs 20.x
# See https://github.com/nodejs/node/issues/51555

export DISABLE_V8_COMPILE_CACHE=1

npm i -g npm

npm --version

# Install node-gyp globally as a fix for NodeJS 18.18.2 https://github.com/microsoft/vscode/issues/194665
npm i -g node-gyp

# Install all dependencies except @vscode/ripgrep
VSCODE_RIPGREP_VERSION=$(jq -r '.dependencies."@vscode/ripgrep"' package.json)
mv package.json package.json.orig
jq 'del(.dependencies."@vscode/ripgrep")' package.json.orig > package.json

npm install

# Install @vscode/ripgrep without downloading the pre-built ripgrep.
# This often runs into Github API ratelimits and we won't use the binary in this package anyways.
npm add --ignore-scripts "@vscode/ripgrep@${VSCODE_RIPGREP_VERSION}"

# ==============================================================================
# ▼▼▼ CORE MODIFICATION: Inject concurrency control instead of increasing memory ▼▼▼
#
echo "Patching build scripts to limit esbuild concurrency..."

OPTIMIZE_JS_PATH="build/lib/optimize.js"

if [ -f "$OPTIMIZE_JS_PATH" ]; then
    # 1. Install p-limit, a lightweight concurrency control library.
    npm install p-limit

    # 2. Inside the minifyTask function, inject the p-limit initialization code
    #    to hard-limit the concurrency to 2.
    sed -i "/function minifyTask(src, sourceMapBaseUrl) {/a \ \ \ \ const pLimit = require('p-limit');\n    const limit = pLimit(2);" "$OPTIMIZE_JS_PATH"

    # 3. Find the esbuild.build({...}) call and wrap it with limit(...).
    #    This ensures a maximum of 2 esbuild minification tasks run at the same time,
    #    preventing memory spikes from an excessive number of parallel processes.
    sed -i "s/esbuild_1.default.build({/limit(() => esbuild_1.default.build({/" "$OPTIMIZE_JS_PATH"
    sed -i "s/}, cb);/}));/" "$OPTIMIZE_JS_PATH"

    echo "optimize.js patched successfully. Concurrency is now limited to 2."
else
    echo "Warning: $OPTIMIZE_JS_PATH not found, skipping concurrency limit patch."
fi
#
# ▲▲▲ END OF CORE MODIFICATION ▲▲▲
# ==============================================================================

# Set memory limit explicitly as a defensive measure to ensure build consistency across environments.
export NODE_OPTIONS="--max-old-space-size=8192"
export UV_THREADPOOL_SIZE=4

ARCH_ALIAS=linux-x64
npm run gulp vscode-reh-web-${ARCH_ALIAS}-min --inspect --debug-brk

mkdir -p $PREFIX/share
cp -r vscode-reh-web-${ARCH_ALIAS} ${PREFIX}/share/sagemaker-code-editor
rm -rf $PREFIX/share/sagemaker-code-editor/bin

popd
popd

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
