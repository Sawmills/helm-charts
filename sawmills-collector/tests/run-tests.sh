#!/bin/bash

# Script to run Helm chart unit tests for the sawmills-collector chart

set -e

echo "🔧 Checking if helm-unittest plugin is installed..."

# Check if helm-unittest is already installed
if ! helm plugin list | grep -q unittest; then
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
echo "📋 Running affinity configuration tests..."
helm unittest . -f 'tests/deployment_affinity_test.yaml' --color

echo ""
echo "📋 Running integration tests..."
helm unittest . -f 'tests/deployment_integration_test.yaml' --color

echo ""
echo "📋 Running all tests..."
helm unittest . --color

echo ""
echo "✅ All tests completed successfully!"
echo ""
echo "📊 Test Summary:"
echo "  - Affinity configuration tests: ✅"
echo "  - Integration tests: ✅"
echo ""
echo "🚀 You can now deploy the chart with confidence that the affinity configuration works correctly!" 