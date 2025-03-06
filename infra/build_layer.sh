#!/bin/bash
set -e

echo "Building Lambda layer..."

# Create layer directory structure
mkdir -p build/layer/python

# Install dependencies into the layer
pip install -r lambda/requirements.txt -t build/layer/python/

# Create layer zip
cd build/layer
zip -r ../../lambda_layer.zip .
cd ../..

echo "Lambda layer created successfully"
