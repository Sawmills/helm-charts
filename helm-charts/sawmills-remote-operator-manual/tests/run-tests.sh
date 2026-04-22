#!/bin/bash

# Script to run Helm chart unit tests for the sawmills-remote-operator-manual chart

set -e

echo "🔧 Checking if helm-unittest plugin is installed..."

# Check if helm-unittest is already installed
plugins="$(helm plugin list)"
if ! grep -q unittest <<<"${plugins}"; then
	echo "📦 Installing helm-unittest plugin..."
	helm plugin install https://github.com/helm-unittest/helm-unittest
else
	echo "✅ helm-unittest plugin is already installed"
fi

echo ""
echo "🧪 Running Helm chart unit tests..."
echo "=================================="

# Change to the chart directory
cd "$(dirname "$0")/.."

# Run all tests with colors
echo "📋 Running proxy helper tests..."

echo ""
helm unittest . -f 'tests/proxy_test.yaml' --color

echo ""
echo "📋 Running RBAC tests..."
helm unittest . -f 'tests/rbac_test.yaml' --color

echo ""
echo "📋 Running all tests..."
helm unittest . --color

echo ""
echo "✅ All tests completed successfully!"
echo ""
echo "📊 Test Summary:"
echo "  - Proxy helper tests: ✅"
echo "  - RBAC scope tests: ✅"
echo ""
