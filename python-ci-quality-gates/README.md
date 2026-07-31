# Python CI Quality Gates

## What This Does

This implementation provides automated continuous integration for a tested Python application using GitHub Actions.

Every code change is validated through syntax checks, linting, unit testing, branch coverage, and multi-version Python compatibility testing. Successful validation produces downloadable coverage and release artifacts with a SHA-256 checksum.

The workflow demonstrates how engineering teams can enforce consistent quality standards before accepting, merging, or distributing Python code.

## Architecture

    ┌──────────────────────────────────────────────┐
    │          Git Push or Pull Request            │
    └──────────────────────┬───────────────────────┘
                           │
                           ▼
    ┌──────────────────────────────────────────────┐
    │               GitHub Actions                 │
    └──────────────────────┬───────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
    ┌───────────────────────┐   ┌──────────────────────────┐
    │ Python Calculator CI  │   │ Python Quality Gates     │
    ├───────────────────────┤   ├──────────────────────────┤
    │ Repository checkout   │   │ Python syntax validation │
    │ Dependency caching    │   │ Flake8 code-quality gate │
    │ Flake8 validation     │   │ Python 3.10 test matrix  │
    │ Unit testing          │   │ Python 3.11 test matrix  │
    │ Branch coverage       │   │ Python 3.12 test matrix  │
    │ Coverage artifact     │   │ Python 3.13 test matrix  │
    └───────────────────────┘   └────────────┬─────────────┘
                                             │
                                             ▼
                                ┌──────────────────────────┐
                                │ Release Packaging        │
                                ├──────────────────────────┤
                                │ Source archive           │
                                │ SHA-256 checksum         │
                                │ Downloadable artifact    │
                                └──────────────────────────┘

## Prerequisites

- Git
- Python 3.10 or later
- Python virtual environment support
- GitHub account
- GitHub repository with Actions enabled
- GitHub CLI
- Internet access

## Setup and Installation

Clone the repository:

    git clone https://github.com/bilalfayyaz11/observability-platform-engineering.git
    cd observability-platform-engineering/python-ci-quality-gates

Create and activate a virtual environment:

    python3 -m venv .venv
    source .venv/bin/activate

Install the required dependencies:

    python -m pip install --upgrade pip
    python -m pip install -r requirements.txt

## How to Reproduce

Run code-quality checks:

    flake8 calculator.py test_calculator.py

Validate Python syntax:

    python -m py_compile calculator.py test_calculator.py

Run unit tests:

    pytest test_calculator.py -v

Run tests with branch coverage:

    pytest test_calculator.py \
      -v \
      --cov=calculator \
      --cov-branch \
      --cov-report=term-missing \
      --cov-report=xml

Review recent workflow executions:

    gh run list --limit 10

Inspect a workflow execution:

    gh run view RUN_ID

View failed workflow logs:

    gh run view RUN_ID --log-failed

## Automated Workflows

### Python Calculator CI

The primary workflow:

- Triggers when relevant files change
- Configures Python 3.12
- Caches Python dependencies
- Runs Flake8 checks
- Executes unit tests
- Measures statement and branch coverage
- Uploads the XML coverage report

### Python Calculator Quality Gates

The multi-stage workflow:

- Validates Python syntax
- Enforces Flake8 standards
- Tests Python 3.10, 3.11, 3.12, and 3.13
- Prevents packaging when validation fails
- Creates a compressed source archive
- Generates a SHA-256 checksum
- Uploads the archive and checksum

## Application Capabilities

- Addition
- Subtraction
- Multiplication
- Division
- Exponentiation
- Modulo calculation
- Division-by-zero protection
- Modulo-by-zero protection
- Operand type validation

## Test Coverage

The automated tests validate:

- Positive and negative values
- Integer and floating-point operations
- Division behavior
- Division-by-zero errors
- Exponentiation behavior
- Modulo behavior
- Modulo-by-zero errors
- Invalid operand types

The completed implementation produced nine passing tests and full coverage of the calculator module.

## Tools Used

- Python
- Pytest
- pytest-cov
- Flake8
- Git
- GitHub Actions
- GitHub CLI
- YAML
- Python virtual environments
- GNU tar
- SHA-256 utilities

## Key Skills Demonstrated

- Multi-stage continuous integration
- Automated software quality gates
- Multi-version Python testing
- Statement and branch coverage
- Dependent workflow jobs
- Path-based workflow triggers
- Dependency caching
- Artifact packaging
- Checksum generation
- GitHub Actions troubleshooting
- Headless GitHub authentication

## Real-World Use Case

This pattern can be used by application, platform, AIOps, DevSecOps, data, and machine-learning teams to validate Python services, automation utilities, operational tooling, and data-processing components before merging or release.

It can be extended with security scanning, dependency vulnerability checks, container builds, infrastructure validation, model evaluation, deployment approvals, and automated rollback controls.

## Verified Results

Both GitHub Actions workflows completed successfully.

### Python Calculator CI

- Tests and Coverage job passed
- XML coverage report uploaded
- Coverage artifact generated successfully

### Python Calculator Quality Gates

- Code Quality job passed
- Python 3.10 testing passed
- Python 3.11 testing passed
- Python 3.12 testing passed
- Python 3.13 testing passed
- Build Release Artifact job passed
- Release archive and SHA-256 checksum uploaded

## Lessons Learned

- GitHub Actions workflows must be stored under `.github/workflows`.
- Path filters prevent unrelated changes from triggering workflows.
- Matrix testing identifies runtime compatibility issues.
- Dependent jobs prevent invalid releases.
- Coverage thresholds enforce measurable testing standards.
- Checksums provide basic artifact integrity validation.
- Local success does not replace GitHub-hosted runner validation.
- Headless environments require device-code authentication.

## Troubleshooting Log

### Missing pip

The fresh Ubuntu environment included Python but not pip.

It was installed with:

    sudo apt update
    sudo apt install -y python3-pip python3-venv

### Missing GitHub CLI

GitHub CLI was installed with:

    sudo apt install -y gh

### GitHub CLI Browser Failure

The remote machine did not have a graphical display and returned:

    Error: no DISPLAY environment variable specified

Device authentication was enabled with:

    unset DISPLAY
    export BROWSER=echo
    export GH_BROWSER=echo

    gh auth login \
      --hostname github.com \
      --git-protocol https \
      --web

### Outdated GitHub Actions

The original instructions referenced older releases:

- actions/checkout@v3
- actions/setup-python@v4
- actions/upload-artifact@v3

They were replaced with:

- actions/checkout@v6
- actions/setup-python@v6
- actions/upload-artifact@v7

### Incorrect Test Placement

Appending test methods after the unittest execution block would place them outside the test class and prevent discovery.

The power and modulo tests were placed directly inside the TestCalculator class.

### Workflow Discovery

Workflow definitions were stored at:

    .github/workflows/

The application files remain under:

    python-ci-quality-gates/

## Future Improvements

- Add dependency vulnerability scanning
- Add static security analysis
- Add automated formatting validation
- Add mutation testing
- Add signed artifacts
- Add semantic versioning
- Add automated releases
- Add container image packaging
- Add software bill of materials generation
- Add deployment approval gates
- Add branch-protection requirements
- Pin actions to immutable commit hashes
