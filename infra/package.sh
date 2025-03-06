#!/bin/bash
set -e

# Define directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${SCRIPT_DIR}/build"
LAMBDA_DIR="${SCRIPT_DIR}/lambda"
PACKAGE_DIR="${BUILD_DIR}/package"
ZIP_FILE="${BUILD_DIR}/lambda_function.zip"

echo "Cleaning up previous builds..."
rm -rf "${BUILD_DIR}"
mkdir -p "${PACKAGE_DIR}"

echo "Installing dependencies and project..."
cd "${ROOT_DIR}"
pip3 install -t "${PACKAGE_DIR}" .

echo "Copying lambda function..."
cp "${LAMBDA_DIR}/lambda_function.py" "${PACKAGE_DIR}/"

echo "Creating zip package..."
cd "${PACKAGE_DIR}"
zip -r "${ZIP_FILE}" .

echo "Package created at ${ZIP_FILE}"
