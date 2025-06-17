# Contributing to Sawmills Helm Charts

Thank you for your interest in contributing to Sawmills Helm Charts! This document provides detailed guidelines for contributing to this repository.

## 🎯 Contribution Philosophy

We believe in **collaborative improvement** of our Helm charts through community contributions. Whether you're a Sawmills customer, partner, or community member, your contributions help make our charts better for everyone.

## 📋 Before You Start

### Prerequisites
- Kubernetes knowledge (intermediate level)
- Helm 3.x experience
- Git and GitHub workflow familiarity
- Access to a Kubernetes test environment

### Repository Access
This repository is private and shared with select partners and customers. If you need access, please contact your Sawmills representative.

## 🚀 Getting Started

### 1. Fork and Clone
```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/helm-charts.git
cd helm-charts

# Add upstream remote
git remote add upstream https://github.com/Sawmills/helm-charts.git
```

### 2. Set Up Development Environment
```bash
# Ensure you have the required tools
helm version  # Should be v3.x+
kubectl version  # Should match your cluster
```

### 3. Create a Feature Branch
```bash
# Keep your main branch up to date
git checkout main
git pull upstream main

# Create a feature branch
git checkout -b feature/your-feature-name
```

## 🔍 Types of Contributions

### Welcomed Contributions
- **Bug fixes** - Fixing issues in existing charts
- **Feature enhancements** - Adding new functionality
- **Documentation improvements** - Better docs, examples, comments
- **Configuration additions** - New values.yaml options
- **Performance optimizations** - Resource efficiency improvements
- **Security enhancements** - Security best practices

### Review Required
- **Breaking changes** - Changes that break existing deployments
- **New charts** - Adding entirely new charts
- **Major architectural changes** - Significant structural modifications

## 🧪 Testing Requirements

### Mandatory Tests (Must Pass)

#### 1. Helm Validation
```bash
# Template validation
helm template test-release ./helm-charts/[chart-name] --debug

# Lint check
helm lint ./helm-charts/[chart-name]

# Dry run
helm install test-release ./helm-charts/[chart-name] --dry-run --debug
```

#### 2. Chart Tests
```bash
# Run chart tests if they exist
helm test test-release --namespace test-namespace
```

### Recommended Tests

#### 1. Integration Testing
```bash
# Install in test environment
helm install test-release ./helm-charts/[chart-name] \
  --namespace test-sawmills \
  --create-namespace \
  --values ./test-values.yaml

# Verify deployment
kubectl get pods -n test-sawmills
kubectl get services -n test-sawmills
kubectl logs -f deployment/test-release-sawmills-collector
```

#### 2. Upgrade Testing
```bash
# Test upgrade path
helm upgrade test-release ./helm-charts/[chart-name] \
  --namespace test-sawmills

# Test rollback
helm rollback test-release 1 --namespace test-sawmills
```

#### 3. Uninstall Testing
```bash
# Clean uninstall
helm uninstall test-release --namespace test-sawmills
kubectl delete namespace test-sawmills
```

## 📝 Code Standards

### Helm Chart Best Practices

#### 1. File Organization
```
chart-name/
├── Chart.yaml          # Chart metadata
├── values.yaml         # Default configuration
├── README.md           # Chart documentation
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl    # Template helpers
│   └── tests/          # Chart tests
└── examples/           # Usage examples
```

#### 2. Template Guidelines
- Use meaningful variable names
- Include helpful comments for complex logic
- Validate required values with `required` function
- Use `quote` for string values that might contain special characters
- Follow Kubernetes resource naming conventions

#### 3. Values.yaml Structure
```yaml
# Group related settings
image:
  repository: "public.ecr.aws/s7a5m1b4/sawmills-collector"
  tag: "latest"
  pullPolicy: IfNotPresent

# Use descriptive comments
replicaCount: 3  # Number of replicas for the deployment

# Provide sensible defaults
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "2.5Gi"
    cpu: "3000m"
```

#### 4. Template Helpers
```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
```

### YAML Standards
- Use 2 spaces for indentation
- Keep lines under 120 characters when possible
- Use meaningful resource names
- Include proper labels and annotations

## 📖 Documentation Requirements

### Chart README.md
Each chart must include:
- **Description**: What the chart does
- **Prerequisites**: Requirements to use the chart
- **Installation**: Basic installation instructions
- **Configuration**: Table of all values.yaml options
- **Examples**: Common use cases
- **Troubleshooting**: Common issues and solutions

### Configuration Documentation
```yaml
# values.yaml
prometheus:
  # Enable Prometheus metrics collection
  # @default -- false
  enabled: false
  
  # Prometheus scrape port
  # @default -- 8080
  port: 8080
```

### Inline Comments
- Explain complex template logic
- Document unusual configurations
- Provide context for default values

## 🔄 Pull Request Process

### 1. Pre-PR Checklist
- [ ] All tests pass locally
- [ ] Documentation is updated
- [ ] Commit messages are clear
- [ ] Branch is up to date with main

### 2. PR Creation
1. Push your feature branch to your fork
2. Create a PR against the main branch
3. Use the provided PR template
4. Tag `@sawmills/engineers` in the description

### 3. PR Content Requirements

#### Title Format
```
[CHART] Type: Brief description

Examples:
[sawmills-collector] fix: Correct resource limits calculation
[sawmills-collector] feat: Add KEDA autoscaling support
[docs] improve: Update installation instructions
```

#### Description Requirements
- **Summary**: Clear description of changes
- **Motivation**: Why these changes are needed
- **Testing**: How you tested the changes
- **Breaking Changes**: Any compatibility impacts
- **Screenshots**: For UI/visual changes

### 4. Review Process

#### Automated Checks
- Helm lint validation
- Template rendering tests
- Documentation checks

#### Manual Review
- Code quality assessment
- Security considerations
- Compatibility review
- Documentation completeness

#### Review Timeline
- **Initial Review**: Within 2 business days
- **Follow-up Reviews**: Within 1 business day
- **Final Approval**: Senior engineer approval required

## 🐛 Issue Reporting

### Before Creating an Issue
1. Check existing issues for duplicates
2. Test with the latest chart version
3. Gather relevant information

### Issue Template
```markdown
**Chart Name**: sawmills-collector
**Chart Version**: 1.2.3
**Kubernetes Version**: 1.25.0
**Helm Version**: 3.10.0

**Description**
Clear description of the issue.

**Steps to Reproduce**
1. Step one
2. Step two
3. Step three

**Expected Behavior**
What should happen.

**Actual Behavior**
What actually happens.

**Additional Context**
- Error messages
- Logs
- Screenshots
- Configuration files
```

## 🛡️ Security Guidelines

### Sensitive Information
- **Never commit secrets** (passwords, keys, tokens)
- Use Kubernetes secrets for sensitive data
- Sanitize logs and error messages
- Review template outputs for data leaks

### Security Review
- All PRs undergo security review
- Report security issues privately to security@sawmills.ai
- Follow responsible disclosure practices

## 🎉 Recognition

### Contributors
We maintain a contributors list and recognize valuable contributions:
- Documentation improvements
- Bug fixes and enhancements
- Community support
- Testing and validation

### Hall of Fame
Outstanding contributors may be featured in:
- Repository README
- Release notes
- Sawmills community updates

## 📞 Getting Help

### Support Channels
- **GitHub Issues**: Technical issues and bugs
- **GitHub Discussions**: Questions and general help
- **Direct Contact**: Tag `@sawmills/engineers` in PRs/issues

### Response Times
- **Critical Issues**: Same day response
- **General Issues**: 2 business day response
- **Feature Requests**: 1 week response

## 📋 Release Process

### Versioning
We follow [Semantic Versioning](https://semver.org/):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes (backwards compatible)

### Release Schedule
- **Patch releases**: As needed for critical fixes
- **Minor releases**: Monthly or as features are ready
- **Major releases**: Quarterly or for significant changes

---

Thank you for contributing to Sawmills Helm Charts! Your contributions help make our platform better for everyone. 🚀 