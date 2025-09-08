#!/bin/bash

set -exuo pipefail

# Create target directory
mkdir -p "${PREFIX}/share/sagemaker-code-editor"
cd "${SRC_DIR}/sagemaker-code-editor"

echo "Current directory:"
ls -l
# Copy all contents into the target directory, avoiding wrapping an extra directory layer
cp -a ./* "${PREFIX}/share/sagemaker-code-editor"

# Clean up unnecessary files to reduce package size
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

if [[ "${build_platform}" == "${target_platform}" ]]; then
  # Directly check whether the sagemaker-code-editor call also works inside of conda-build
  sagemaker-code-editor --help
fi
