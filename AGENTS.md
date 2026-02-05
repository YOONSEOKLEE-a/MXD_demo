# AGENTS.md - Development Guide for MXD Project

This file contains build, test, and development guidelines for agentic coding agents working in the Minimum Tractus-X Dataspace (MXD) repository.

## Project Overview

MXD is a Terraform-based Kubernetes infrastructure project that deploys the Minimum Tractus-X Dataspace with Eclipse Dataspace Connectors (EDC), IdentityHub instances, PostgreSQL databases, and HashiCorp Vault instances.

## Build/Deploy Commands

### Prerequisites Setup
```bash
# Create KinD cluster
kind create cluster -n mxd --config kind.config.yaml

# Install ingress controller (KinD specific)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Build runtime images (from mxd-runtimes directory)
cd ../mxd-runtimes && ./gradlew dockerize

# Load images into KinD
kind load docker-image --name mxd data-service-api tx-identityhub tx-catalog-server tx-issuerservice
```

### Terraform Operations
```bash
terraform init                          # Initialize Terraform
terraform plan                          # Preview changes
terraform apply                         # Deploy infrastructure (interactive)
terraform apply -auto-approve           # Deploy without confirmation
terraform destroy -auto-approve         # Destroy infrastructure
terraform apply -var="useSVE=true"      # For ARM platforms (Apple Silicon)
```

### Lint and Format Commands
```bash
terraform fmt                           # Format all .tf files in current directory
terraform fmt -check                    # Check if files are formatted (CI-friendly)
terraform fmt -recursive                # Format all .tf files recursively
terraform validate                      # Validate Terraform syntax and configuration
```

### Test Commands

#### Quick Health Checks
```bash
# Test connector health endpoints
curl -X GET http://localhost/bob/health/api/check/liveness
curl -X GET http://localhost/alice/health/api/check/liveness

# Query Alice assets
curl -X POST http://localhost/alice/management/v3/assets/request \
  -H "x-api-key: password" -H "content-type: application/json" | jq
```

#### API Test Collections
```bash
# Run full API test suite (newman required)
newman run postman/management_api_tests.json

# Run specific Postman collection
newman run postman/mxd-management-apis.json

# Run with environment file
newman run postman/management_api_tests.json -e postman/environment.json

# Run a single test by filtering (use Postman folder/request name)
newman run postman/management_api_tests.json --folder "Alice Health Check"
```

#### Performance Tests
```bash
cd performance-tests
./experiment_controller.sh              # Run default performance test
./experiment_controller.sh -f test-configurations/small_experiment.properties  # Run specific test
# Results: ./Output/measurement_interval/index.html

# Run with custom cluster configuration
./experiment_controller.sh -x kind-mxd -y shoot--edc-lpt--mxd
```

#### Setup Utilities
```bash
./setup_db.sh                           # Initialize databases
./setup_vaults.sh                       # Setup Vault instances
./fix_all_vaults.sh                     # Repair Vault configurations
./port-forward.sh                       # Start all port forwards for local access
```

## Code Style Guidelines

### Terraform Files (.tf)

#### Header Format
All Terraform files must include the Apache 2.0 license header:
```hcl
#
#  Copyright (c) [YEAR] Contributors to the Eclipse Foundation
#
#  See the NOTICE file(s) distributed with this work for additional
#  information regarding copyright ownership.
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#  License for the specific language governing permissions and limitations
#  under the License.
#
#  SPDX-License-Identifier: Apache-2.0
#
```

#### Naming Conventions
- **Resources**: kebab-case with descriptive names (e.g., `kubernetes_namespace.mxd-ns`)
- **Variables**: kebab-case (e.g., `alice-humanReadableName`, `database-host`)
- **Locals**: kebab-case for composite values (e.g., `alice-postgres`, `databases.alice`)
- **Modules**: kebab-case (e.g., `alice-connector`, `bob-vault`)

#### Variable Definitions
Always include `type`, `description`, and `default` where applicable:
```hcl
variable "namespace" {
  type        = string
  description = "Kubernetes namespace to use"
  default     = "mxd"
}

variable "humanReadableName" {
  type        = string
  description = "Human readable name of the connector, NOT the BPN!!. Required."
}
```

#### Module Usage
- Always explicitly declare `source` path
- Use `depends_on` for explicit dependencies
- Align variable assignments for readability:
```hcl
module "alice-connector" {
  depends_on        = [module.azurite]
  source            = "./modules/connector"
  humanReadableName = var.alice-humanReadableName
  namespace         = kubernetes_namespace.mxd-ns.metadata.0.name
  participantId     = var.alice-bpn
  database-host     = local.alice-postgres.database-host
}
```

#### Provider Configuration
- Use explicit provider versions in `required_providers` blocks
- Set `config_path` for both kubernetes and helm providers
- Minimum Terraform version: 1.0
- Maintain `.terraform.lock.hcl` for provider version consistency

### Shell Scripts (.sh)

#### Header Format
Include Apache 2.0 license header and shebang:
```bash
#!/bin/bash
#
#  Copyright (c) 2024 Contributors to the Eclipse Foundation
#
#  [Apache 2.0 header...]
#
#  SPDX-License-Identifier: Apache-2.0
#
```

#### Script Structure
1. Constants section at top
2. Default values assignment
3. Argument parsing with getopts
4. Main logic sections with clear comments
5. Use `set -e` for error handling where appropriate

#### Port Forwarding
- Kill existing processes before starting new ones
- Use background processes (`&`) and `wait` at the end
- Provide clear status messages:
```bash
pkill -f "kubectl port-forward" 2>/dev/null
sleep 1

echo "=== Starting port forwards ==="
kubectl port-forward svc/alice-tractusx-connector-controlplane -n $NS 8282:8081 &
echo "✓ Alice Connector: localhost:8282"
```

### Configuration Files

#### YAML Files
- Use `apiVersion: v1` for ConfigMaps
- Follow Kubernetes naming conventions
- Group related configurations logically:
```yaml
apiVersion: v1
data:
  EDC_DATASOURCE_DEFAULT_PASSWORD: issuer
  EDC_DATASOURCE_DEFAULT_URL: jdbc:postgresql://10.96.52.183:5432/issuer
  EDC_PARTICIPANT_ID: did:web:dataspace-issuer
immutable: false
kind: ConfigMap
metadata:
  name: dataspace-issuer-service-config
  namespace: mxd
```

#### JSON Files (Postman Collections)
- Follow Postman collection schema v2.0.0
- Include proper test assertions:
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});
```

## Testing Guidelines

### Unit Tests
- Use Terraform validate: `terraform validate`
- Check syntax: `terraform fmt -check`
- Verify variable types and constraints

### Integration Tests
- Health checks for all deployed services
- API endpoint validation using Postman collections
- Database connectivity tests
- Vault accessibility tests

### Performance Tests
- Use JMeter scripts in `performance-tests/` directory
- Configure experiments via `.properties` files
- Default test: `test-configurations/small_experiment.properties`
- Results analyzed via JMeter dashboard at `Output/measurement_interval/index.html`
- Performance metrics include:
  - Executions per second
  - Response time (min, avg, max, 90th percentile)
  - Throughput
  - Network KB/sec

## Security Considerations

- Never commit actual secrets to repository
- Use Kubernetes secrets for sensitive data
- Vault integration for credential management
- API key authentication for management APIs
- Network policies restricted to mxd namespace

## Development Workflow

1. **Local Development**: Use KinD cluster with port-forwarding
2. **Testing**: Run health checks and Postman collections
3. **Performance**: Execute JMeter tests for load testing
4. **Deployment**: Use Terraform for all infrastructure changes
5. **Validation**: Verify all services are healthy post-deployment

### Adding New Participants

When adding a new participant to the dataspace:
1. Create participant variables file (e.g., `trudy_variables.tf`) with BPN and other settings
2. Create main configuration (e.g., `trudy.tf`) following the pattern in `alice.tf`/`bob.tf`
3. Update `azurite` module with the new participant's storage account
4. Add appropriate seed data in `seed_data.tf`
5. Update port-forward.sh to include new services

## Common Troubleshooting

### ARM Platform Issues
Use `useSVE=true` variable to enable Scalable Vector Extensions on Apple Silicon.

### Port Conflicts
Ensure local ports are available before running `port-forward.sh`.

### Image Loading
Always build and load Docker images into KinD before applying Terraform.

### Database Access
Use port-forwarding to access PostgreSQL instances for debugging.

### DID Verification Issues
If connector health endpoints report issues with DID verification:
1. Check the Identity Hub logs for errors
2. Verify DID document is accessible at `.well-known/did.json`
3. Confirm CredentialService endpoints point to the correct port (7082)

### Token Service Errors
If STS returns errors, check Vault for correct client secrets and validate IdentityHub configuration.