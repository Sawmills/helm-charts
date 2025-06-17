# Sawmills Helm Charts

This repository contains official Helm charts for Sawmills platform services. These charts are designed to simplify the deployment and management of Sawmills components in Kubernetes environments.

## 📋 Available Charts

### `sawmills-collector`
**Sawmills OpenTelemetry Collector** - A comprehensive Helm chart for deploying the Sawmills OpenTelemetry Collector with advanced observability features.

**Key Features:**
- Multiple deployment modes (Deployment, DaemonSet)
- Built-in autoscaling with HPA and KEDA support
- HAProxy load balancing
- Comprehensive monitoring and telemetry
- Service mesh integration
- Flexible configuration options

**Chart Location:** [`helm-charts/sawmills-collector/`](./helm-charts/sawmills-collector/)

## 🚀 Quick Start

### Prerequisites
- Kubernetes cluster (v1.19+)
- Helm 3.x
- Access to Sawmills container registry

### Installation

```bash
# Add the Sawmills Helm repository
helm repo add sawmills https://public.ecr.aws/s7a5m1b4

# Update repository cache
helm repo update

# Install the Sawmills Collector
helm install my-collector sawmills/sawmills-collector-chart \
  --namespace sawmills-system \
  --create-namespace \
  --set prometheusremotewrite.endpoint="https://your-endpoint.com" \
  --set-string appVersion="latest"
```

### Configuration

Each chart includes comprehensive configuration options. Refer to the individual chart documentation:

- [Sawmills Collector Configuration](./helm-charts/sawmills-collector/README.md)
- [Sawmills Collector Examples](./helm-charts/sawmills-collector/examples/)

## 🤝 Contributing

We welcome contributions from our partners and customers to improve these Helm charts. Please follow the contribution guidelines below.

### Contribution Process

1. **Fork and Clone**: Fork this repository and clone it to your local machine
2. **Create a Branch**: Create a feature branch for your changes
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make Changes**: Implement your improvements or fixes
4. **Test Your Changes**: Thoroughly test your changes (see [Testing Guidelines](#testing-guidelines))
5. **Open a Pull Request**: Submit a PR with a clear description

### Pull Request Requirements

When opening a pull request, please include:

#### Required Information
- **Tag**: Always tag `@sawmills/engineers` in your PR description
- **Change Description**: Clear, concise description of what was changed and why
- **Testing Details**: How the changes were tested (see examples below)
- **Breaking Changes**: Explicitly state if this is a breaking change

#### PR Template
```markdown
## Summary
Brief description of the changes made.

## Changes Made
- [ ] Feature addition
- [ ] Bug fix
- [ ] Documentation update
- [ ] Breaking change

## Testing Performed
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed
- [ ] Tested in staging environment

### Test Details
Describe how you tested these changes:
- Commands used
- Test environments
- Expected vs actual results

## Breaking Changes
- [ ] No breaking changes
- [ ] Contains breaking changes (describe below)

**Breaking Change Details:**
If this is a breaking change, describe:
- What breaks
- Migration path
- Version compatibility

## Additional Notes
Any additional context or information.

---
@sawmills/engineers Please review this contribution.
```

### Testing Guidelines

#### Required Testing
1. **Helm Template Validation**
   ```bash
   helm template test-release ./helm-charts/[chart-name] --debug
   ```

2. **Helm Lint Check**
   ```bash
   helm lint ./helm-charts/[chart-name]
   ```

3. **Dry Run Installation**
   ```bash
   helm install test-release ./helm-charts/[chart-name] --dry-run --debug
   ```

#### Recommended Testing
1. **Deploy to Test Environment**
   ```bash
   helm install test-release ./helm-charts/[chart-name] \
     --namespace test-sawmills \
     --create-namespace
   ```

2. **Verify Deployment**
   ```bash
   kubectl get pods -n test-sawmills
   kubectl logs -f deployment/test-release-sawmills-collector
   ```

3. **Test Upgrades**
   ```bash
   helm upgrade test-release ./helm-charts/[chart-name] \
     --namespace test-sawmills
   ```

### Code Standards

- Follow Helm best practices
- Use meaningful variable names
- Include helpful comments
- Maintain backwards compatibility when possible
- Follow semantic versioning for chart versions

### Documentation Requirements

- Update chart README.md if adding new features
- Add examples for new configuration options
- Update CHANGELOG.md with your changes
- Include inline comments for complex template logic

## 📚 Documentation

### Chart Documentation
- [Sawmills Collector](./helm-charts/sawmills-collector/README.md)
- [Configuration Examples](./helm-charts/sawmills-collector/examples/)

### Useful Resources
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Sawmills Platform Documentation](https://docs.sawmills.ai)

## 🔧 Development

### Local Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/Sawmills/helm-charts.git
   cd helm-charts
   ```

2. **Install development dependencies**
   ```bash
   # Install Helm
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   
   # Install kubectl
   # Follow instructions at https://kubernetes.io/docs/tasks/tools/install-kubectl/
   ```

3. **Validate changes**
   ```bash
   # Run linting
   helm lint helm-charts/*/
   
   # Run tests
   helm test --help
   ```

## 🐛 Troubleshooting

### Common Issues

1. **Chart fails to install**
   - Check Kubernetes cluster connectivity
   - Verify Helm version compatibility
   - Review error messages in `helm install --debug`

2. **Template rendering errors**
   - Use `helm template --debug` to identify issues
   - Check for missing required values
   - Validate YAML syntax

3. **Resource conflicts**
   - Check for existing resources with same names
   - Verify namespace configuration
   - Review RBAC permissions

### Getting Help

- **Issues**: Create an issue in this repository
- **Questions**: Tag `@sawmills/engineers` in discussions
- **Urgent Issues**: Contact Sawmills support

## 📄 License

This project is licensed under the terms specified in the [LICENSE](./LICENSE) file.

## 🔐 Security

This repository contains configurations for production systems. Please:
- Do not commit sensitive information (secrets, keys, passwords)
- Use Kubernetes secrets for sensitive data
- Follow security best practices for Helm charts
- Report security issues privately to security@sawmills.ai

---

**Questions or Issues?** Please tag `@sawmills/engineers` in your issues or pull requests.