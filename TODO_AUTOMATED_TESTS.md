# TODO: Automated Testing for Installation Scripts

## Overview
Create comprehensive integration tests for the Symfony Docker installation procedure that:
- Tests all different scenarios
- Cleans up local files, Docker containers, and images afterwards
- Can be run in CI/CD pipelines

**Recommended Implementation:** Use Sonnet 4 (faster, cost-effective for structured tasks)

---

## Test Structure

### Directory Layout
```
tests/
├── unit/
│   ├── test_port_detection.sh          # Test check_port function
│   ├── test_mailpit_detection.sh       # Test existing Mailpit detection
│   ├── test_input_sanitization.sh      # Test name validation/sanitization
│   └── test_helper_functions.sh        # Test utility functions
├── integration/
│   ├── test_fresh_install.sh           # New project, no existing containers
│   ├── test_with_existing_mailpit.sh   # Install with Mailpit already running
│   ├── test_port_conflicts.sh          # Ports 3306, 1025, 8025 in use
│   ├── test_wsl_detection.sh           # WSL environment detection
│   ├── test_shared_mailpit.sh          # Shared Mailpit creation
│   ├── test_project_mailpit.sh         # Project-specific Mailpit
│   ├── test_input_variations.sh        # Various input formats (caps, special chars)
│   └── test_verbose_mode.sh            # Test --verbose flag
├── ci/
│   └── github-actions.yml              # CI/CD workflow
├── lib/
│   ├── test_helpers.sh                 # Common test utilities
│   ├── mock_inputs.sh                  # Input simulation
│   └── assertions.sh                   # Test assertions
└── cleanup.sh                          # Master cleanup script

run_tests.sh                            # Main test runner
```

---

## Implementation Tasks

### Phase 1: Test Infrastructure
- [ ] Create test directory structure
- [ ] Write test harness with setup/teardown
- [ ] Implement mock input system (using `expect` or heredoc)
- [ ] Create assertion library
  - [ ] `assert_file_exists`
  - [ ] `assert_container_running`
  - [ ] `assert_port_in_use`
  - [ ] `assert_env_variable_set`
- [ ] Write cleanup utilities
  - [ ] Remove test projects
  - [ ] Stop/remove test containers
  - [ ] Clean test volumes
  - [ ] Reset test environment

### Phase 2: Unit Tests
- [ ] **test_port_detection.sh**
  - [ ] Test `check_port()` with free port
  - [ ] Test `check_port()` with occupied port
  - [ ] Test WSL detection
  - [ ] Test Windows host port detection
  - [ ] Test Docker container port detection
  - [ ] Test verbose mode output

- [ ] **test_mailpit_detection.sh**
  - [ ] Test detection with no Mailpit
  - [ ] Test detection with running Mailpit
  - [ ] Test port extraction from Docker ps

- [ ] **test_input_sanitization.sh**
  - [ ] Test project name sanitization
    - [ ] Uppercase → lowercase
    - [ ] Special characters removed
    - [ ] Must start with letter/underscore
  - [ ] Test database name sanitization
  - [ ] Test username sanitization

### Phase 3: Integration Tests
- [ ] **test_fresh_install.sh**
  - [ ] Mock inputs: project name, DB creds, default ports
  - [ ] Verify project directory created
  - [ ] Verify .env files configured correctly
  - [ ] Verify containers started
  - [ ] Verify MySQL accessible
  - [ ] Cleanup after test

- [ ] **test_with_existing_mailpit.sh**
  - [ ] Start Mailpit before test
  - [ ] Run installer
  - [ ] Verify detection message shown
  - [ ] Verify choice to use existing
  - [ ] Verify .env.dev.local configured with host.docker.internal

- [ ] **test_port_conflicts.sh**
  - [ ] Occupy port 3306 (mock MySQL)
  - [ ] Run installer
  - [ ] Verify port conflict detected
  - [ ] Verify alternative port suggested
  - [ ] Verify acceptance of suggested port
  - [ ] Verify project uses alternative port

- [ ] **test_shared_mailpit.sh**
  - [ ] Choose to create shared Mailpit
  - [ ] Verify shared-mailpit container created
  - [ ] Verify restart policy set
  - [ ] Verify project configured to use it

- [ ] **test_input_variations.sh**
  - [ ] Test "Y", "y", "Yes", "yes" acceptance
  - [ ] Test "N", "n", "No", "no" acceptance
  - [ ] Test project name: "My Project" → "my_project"
  - [ ] Test database name: "My-DB!" → "mydb"

### Phase 4: Isolation & Cleanup
- [ ] **cleanup.sh**
  ```bash
  - Remove all test_project_* directories
  - Stop/remove containers matching test-*
  - Remove volumes matching test_*
  - Prune unused Docker resources
  - Reset /tmp test files
  ```

- [ ] **Trap handlers**
  - [ ] Cleanup on test failure
  - [ ] Cleanup on SIGINT/SIGTERM
  - [ ] Preserve logs on failure

### Phase 5: CI/CD Integration
- [ ] **GitHub Actions workflow**
  - [ ] Setup: Install Docker, Docker Compose
  - [ ] Run unit tests
  - [ ] Run integration tests
  - [ ] Upload test artifacts (logs)
  - [ ] Cleanup on completion
  - [ ] Report coverage

- [ ] **Matrix testing**
  - [ ] Ubuntu 20.04
  - [ ] Ubuntu 22.04
  - [ ] WSL2 (if possible in CI)

---

## Test Scenarios Checklist

### Scenario 1: Fresh Install - Default Ports
- [ ] No existing containers
- [ ] Default ports available (80, 443, 3306, 1025, 8025)
- [ ] User selects: Yes to Mailpit, create shared
- [ ] Expected: All services start successfully

### Scenario 2: Fresh Install - Port Conflicts
- [ ] MySQL on 3306 (mock)
- [ ] User accepts suggested 3307
- [ ] Expected: Project uses port 3307

### Scenario 3: Existing Mailpit
- [ ] Mailpit running on 63309→1025, 63310→8025
- [ ] User selects: Use existing shared
- [ ] Expected: .env.dev.local points to host.docker.internal:63309

### Scenario 4: Project-Specific Mailpit
- [ ] User selects: Create project-specific Mailpit
- [ ] Different ports (2025, 9025)
- [ ] Expected: compose.mailer.yaml used, separate container

### Scenario 5: No Mailpit
- [ ] User selects: Do not use Mailpit
- [ ] Expected: No Mailpit container, no MAILER_DSN

### Scenario 6: WSL Environment
- [ ] Detect /proc/version contains "microsoft"
- [ ] Test Windows port detection via PowerShell
- [ ] Test Docker container detection

### Scenario 7: Input Sanitization
- [ ] "My Project!" → "my_project"
- [ ] "Admin@User123" → "adminuser123"
- [ ] "Test-Database!" → "testdatabase"

### Scenario 8: Verbose Mode
- [ ] Run with --verbose
- [ ] Verify detailed diagnostic output
- [ ] Verify WSL detection messages
- [ ] Verify port checking details

---

## Implementation Example

### Test Template
```bash
#!/bin/bash
# tests/integration/test_fresh_install.sh

set -e

# Load test helpers
source "$(dirname "$0")/../lib/test_helpers.sh"

setup() {
    echo "Setting up test environment..."
    export TEST_PROJECT="test_project_$$"
    export TEST_DB_PORT=13306
}

test_fresh_install_defaults() {
    echo "Running: Fresh install with defaults"
    
    # Mock inputs
    {
        echo "$TEST_PROJECT"           # Project name
        echo "y"                       # Want Mailpit
        echo "y"                       # Create shared
        echo "n"                       # Mercure
        echo "${TEST_PROJECT}_db"      # Database name
        echo "${TEST_PROJECT}_user"    # DB user
        echo "testpass123"             # DB password
        echo "rootpass123"             # Root password
        echo "$TEST_DB_PORT"           # MySQL port
        echo "y"                       # Accept port
    } | ../setup/setup.sh
    
    # Assertions
    assert_directory_exists "$TEST_PROJECT"
    assert_file_exists "$TEST_PROJECT/.env"
    assert_container_running "shared-mailpit"
    assert_container_running "${TEST_PROJECT}-database-1"
    assert_port_listening "$TEST_DB_PORT"
    
    echo "✓ Test passed"
}

cleanup() {
    echo "Cleaning up test..."
    docker rm -f shared-mailpit test_* 2>/dev/null || true
    rm -rf "$TEST_PROJECT"
}

trap cleanup EXIT

setup
test_fresh_install_defaults
cleanup
```

---

## Success Criteria

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Tests run in < 10 minutes
- [ ] No leftover containers after tests
- [ ] No leftover volumes after tests
- [ ] No leftover files after tests
- [ ] Tests pass in CI/CD pipeline
- [ ] Coverage > 80% of scenarios

---

## Notes

- Use **Sonnet 4** for implementation (faster, cost-effective)
- Consider **Opus 3.5** only for complex test architecture decisions
- Mock external dependencies (MySQL, Mailpit) where possible
- Use Docker-in-Docker for full isolation in CI
- Keep tests idempotent (can run multiple times)
- Add parallel test execution for speed

---

## Future Enhancements

- [ ] Performance benchmarks
- [ ] Load testing (multiple simultaneous installs)
- [ ] Network failure simulation
- [ ] Disk space limitation tests
- [ ] Permission error scenarios
- [ ] Upgrade path testing (old → new version)