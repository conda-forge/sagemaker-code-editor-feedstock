#!/bin/bash

set -exuo pipefail

# This code includes code from https://github.com/conda-forge/openvscode-server-feedstock 
# which is licensed under the BSD-3-Clause License.


# Extract the prebuilt tarball. This assumes the tarball is already present in the working directory.
tar -xvf code-editor${PKG_VERSION}.tar.gz

# Copy the extracted folder to the target location under $PREFIX/share/sagemaker-code-editor.
mkdir -p "${PREFIX}/share"
cp -R vscode-reh-web-linux-x64 "${PREFIX}/share/sagemaker-code-editor"

# Remove all .map files to reduce package size.
find "${PREFIX}/share/sagemaker-code-editor" -name '*.map' -delete

# Create the binary entry point script for sagemaker-code-editor.
mkdir -p "${PREFIX}/bin"
cat <<'EOF' >"${PREFIX}/bin/sagemaker-code-editor"
#!/bin/bash

# Get the directory of the current script.
PREFIX_DIR=$(dirname "${BASH_SOURCE[0]}")

# Make PREFIX_DIR absolute.
if [[ $(uname) == 'Linux' ]]; then
  PREFIX_DIR=$(readlink -f "${PREFIX_DIR}")
else
  pushd "${PREFIX_DIR}"
  PREFIX_DIR=$(pwd -P)
  popd
fi

# Move one level up to reach the conda environment prefix.
PREFIX_DIR=$(dirname "${PREFIX_DIR}")

# Start the server using Node.js, passing all user arguments.
node "${PREFIX_DIR}/share/sagemaker-code-editor/out/server-main.js" "$@"
EOF

chmod +x "${PREFIX}/bin/sagemaker-code-editor"

