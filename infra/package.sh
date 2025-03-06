#!/bin/bash
set -e

echo "Building Lambda function package..."

# Check if zip is installed, install if not
if ! command -v zip &>/dev/null; then
    echo "zip command not found, attempting to install..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y zip
    elif command -v yum &>/dev/null; then
        sudo yum install -y zip
    elif command -v brew &>/dev/null; then
        brew install zip
    else
        echo "ERROR: Could not install zip. Please install it manually."
        exit 1
    fi
fi

# Create build directory
mkdir -p build/package

# Copy only Lambda function code (no dependencies)
cp lambda/lambda_function.py build/package/

# Create zip file
cd build/package
zip -r ../../lambda_function.zip .
cd ../..

echo "Lambda package created successfully"
