# Grafana Least-Privilege Access Control

## What This Does

This implementation builds and validates a least-privilege access-control model for Grafana.

Grafana users are assigned a minimal organization-level Viewer role and receive elevated permissions only through team-scoped folder access.

Three functional teams are used:

- Development Team
- Management Team
- Operations Team

Each team receives Edit, View, or no access depending on the dashboard folder.

The implementation also replaces deprecated API-key automation with Grafana service accounts and short-lived service-account tokens.

Authorization is validated through actual Grafana API requests rather than inferred only from configuration.

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                           Grafana                            │
    │                                                              │
    │                  Organization Baseline                       │
    │                       Viewer                                 │
    │                          │                                   │
    │              ┌───────────┼───────────┐                       │
    │              │           │           │                       │
    │              ▼           ▼           ▼                       │
    │        Development   Management   Operations                 │
    │           Team          Team         Team                     │
    │              │           │           │                       │
    │              │           │           │                       │
    │     ┌────────▼───────────▼───────────▼──────────────────┐    │
    │     │              Folder Permissions                   │    │
    │     │                                                   │    │
    │     │ Development Metrics                               │    │
    │     │   Development → Edit                              │    │
    │     │   Management  → View                              │    │
    │     │   Operations  → No Access                         │    │
    │     │                                                   │    │
    │     │ Business Metrics                                  │    │
    │     │   Management  → Edit                              │    │
    │     │   Development → View                              │    │
    │     │   Operations  → View                              │    │
    │     │                                                   │    │
    │     │ System Monitoring                                 │    │
    │     │   Operations  → Edit                              │    │
    │     │   Development → View                              │    │
    │     │   Management  → View                              │    │
    │     └───────────────────────────────────────────────────┘    │
    │                                                              │
    │               Automation Access                              │
    │                                                              │
    │        Viewer Service Account                                │
    │              ↓                                               │
    │           Read Only                                          │
    │                                                              │
    │        Editor Service Account                                │
    │              ↓                                               │
    │          Dashboard Write                                     │
    │                                                              │
    └──────────────────────────────────────────────────────────────┘

## Security Baseline

Grafana is configured with the following initial controls:

    public signup        disabled
    anonymous access     disabled
    default org role     Viewer
    generated admin      password
    localhost binding    enabled

This prevents unnecessary exposure before users and permissions are configured.

## Users

Three users are created to represent different operational responsibilities.

### Developer

    login: jdeveloper
    organization role: Viewer
    team: Development Team

### Manager

    login: smanager
    organization role: Viewer
    team: Management Team

### Operations

    login: bviewer
    organization role: Viewer
    team: Operations Team

All users intentionally retain the Viewer organization role.

Elevated access is granted only through folder permissions.

## Why Viewer Is the Baseline

Using the global Editor organization role would grant broader dashboard privileges than necessary.

The access model therefore follows:

    baseline Viewer
          +
    team membership
          +
    folder-specific permission

This provides stronger least-privilege separation.

## Teams

The implementation creates:

    Development Team
    Management Team
    Operations Team

Teams represent functional responsibilities rather than assigning elevated privileges directly to individuals.

## Folder Access Matrix

                          Development   Business   System
    Development Team     EDIT          VIEW       VIEW
    Management Team      VIEW          EDIT       VIEW
    Operations Team      NO ACCESS     VIEW       EDIT

Folder permissions propagate to dashboards contained within those folders.

## Dashboards

### Application Performance

Folder:

    Development Metrics

Purpose:

    Development authorization validation

## Revenue Tracking

Folder:

    Business Metrics

Purpose:

    Management authorization validation

## Server Health

Folder:

    System Monitoring

Purpose:

    Operations authorization validation

## Authorization Testing

Permissions are validated through actual authenticated HTTP requests.

Tests include:

- dashboard read access
- dashboard write access
- restricted-folder access
- instance-admin API access
- data-source creation
- service-account access

Expected write behavior:

    authorized editor → HTTP 200
    view-only user    → HTTP 403

A completely inaccessible dashboard may return:

    HTTP 404

rather than 403 to avoid exposing the existence of restricted resources.

## Developer Access

Expected:

    Development Metrics → Edit
    Business Metrics    → View
    System Monitoring   → View

Blocked:

    instance admin APIs
    data-source creation

## Manager Access

Expected:

    Development Metrics → View
    Business Metrics    → Edit
    System Monitoring   → View

Blocked:

    instance admin APIs
    data-source creation

## Operations Access

Expected:

    Development Metrics → No Access
    Business Metrics    → View
    System Monitoring   → Edit

Blocked:

    instance admin APIs
    data-source creation

## Service Accounts

Deprecated API-key automation is replaced by Grafana service accounts.

Two service accounts are used.

### Read-Only Automation

    name: rbac-readonly
    role: Viewer

Validated behavior:

    dashboard read   → allowed
    dashboard write  → denied
    admin API        → denied

## Dashboard Automation

    name: rbac-dashboard
    role: Editor

Validated behavior:

    dashboard read   → allowed
    dashboard write  → allowed
    admin API        → denied

## Short-Lived Tokens

Validation tokens are created with limited lifetimes.

This reduces exposure compared with permanent automation credentials.

Tokens are stored only in restricted local files and are excluded from version control.

## Token Revocation

Token revocation is explicitly tested.

Process:

    valid token
        ↓
    authenticated request succeeds
        ↓
    token deleted
        ↓
    same token reused
        ↓
    authentication fails

This proves that service-account credentials can be invalidated immediately.

## Secret Handling

Sensitive files include:

    test-users.env
    service-account-tokens.env
    resource-ids.env

These files are:

    chmod 600
    excluded through .gitignore

Credentials are never intentionally committed.

## Audit Evidence

The implementation creates an `audit-evidence` directory containing exported security state.

Evidence includes:

    Grafana version
    security configuration
    organization users
    organization roles
    teams
    team memberships
    folder permissions
    service accounts
    token permissions
    authorization results
    Grafana security-relevant logs

## Reusable Permission Audit

The script:

    audit_permissions.sh

queries the running Grafana instance and reports:

- users
- organization roles
- teams
- folder inventory
- service accounts

This is more useful than a manual checklist because it provides repeatable evidence from the live system.

Run:

    ./audit_permissions.sh

## Configuration Backup

Grafana configuration and database are backed up to:

    backup/

Files include:

    grafana.ini
    grafana.db

A production implementation should move these backups to protected external storage rather than keeping them on the same machine.

## Database Integrity

Grafana uses SQLite in this implementation.

Database integrity can be checked with:

    sqlite3 backup/grafana.db \
      'PRAGMA integrity_check;'

Expected:

    ok

## Grafana Logs

Recent security-related events can be inspected with:

    sudo journalctl \
      -u grafana-server \
      --since "2 hours ago"

Useful filters include:

    login
    auth
    unauthorized
    forbidden
    user
    team
    permission
    token
    dashboard

## OSS and Enterprise Boundary

Grafana OSS provides the controls used here:

- organization roles
- users
- teams
- folder permissions
- dashboard permissions
- service accounts

Fine-grained custom RBAC roles and native audit functionality belong to higher Grafana editions.

This implementation therefore does not claim unsupported custom-role or native audit capabilities.

## Source Requirement Conflict

The supplied permission matrix grants Development Team View access to System Monitoring.

A later access test says the same developer should have no access to System Monitoring.

Those requirements cannot both be true.

This implementation follows the explicit permission matrix and documents the discrepancy.

## Tools Used

- Grafana
- Grafana HTTP API
- Grafana Service Accounts
- Grafana Teams
- Grafana Folder Permissions
- SQLite
- systemd
- Linux
- curl
- jq
- OpenSSL
- Bash
- JSON

## Key Skills Demonstrated

- Grafana access-control design
- least-privilege architecture
- organization role management
- team-based authorization
- folder permissions
- dashboard authorization
- API authorization testing
- service-account management
- token lifecycle management
- token revocation
- secret handling
- audit evidence collection
- access-review automation
- SQLite integrity validation
- configuration backup
- security troubleshooting

## Real-World Use Case

Enterprise observability systems frequently contain sensitive operational and business information.

Development teams may need write access to application dashboards without being able to modify infrastructure dashboards.

Management may need access to business KPIs while infrastructure configuration remains restricted.

Operations teams may require write access to system monitoring without needing development-dashboard privileges.

A least-privilege folder and team model allows one Grafana deployment to support these different responsibilities safely.

The same design applies to:

- SRE teams
- platform engineering
- DevSecOps environments
- cloud operations
- AI infrastructure
- MLOps platforms
- multi-department observability
- regulated environments

## Security Principles Demonstrated

### Least Privilege

Users receive only the minimum access required.

### Role Separation

Business, development, and operations responsibilities are separated.

### Team-Based Authorization

Permissions are managed through teams rather than individual exceptions.

### Credential Expiration

Automation credentials are temporary.

### Credential Revocation

Compromised or unnecessary tokens can be invalidated.

### Evidence-Based Validation

Authorization is verified using real requests rather than assuming configuration is correct.

### Secret Isolation

Credentials are excluded from source control.

### Regular Access Review

A repeatable audit process provides visibility into current authorization state.

## Lessons Learned

A global Grafana organization role can easily grant more access than intended.

Using Viewer as the common baseline and applying folder-specific team permissions provides a stronger least-privilege model.

Configuration alone is not enough to prove authorization.

Read and write requests should be executed under each identity to verify the actual security boundary.

Service accounts are better suited to automation than shared user credentials.

Short-lived tokens reduce the risk associated with long-lived secrets.

Revocation should be tested rather than assumed.

Security evidence is most useful when it can be regenerated automatically from the running system.

Grafana edition boundaries should be understood before designing access-control requirements because advanced custom RBAC and audit capabilities are not identical across OSS, Enterprise, and Cloud deployments.

## Troubleshooting Log

### Deprecated Grafana Repository Setup

Legacy apt-key installation was replaced with a dedicated signed APT keyring.

### Default Administrator Credentials

The default admin/admin workflow was replaced with a generated administrator password.

### Public Registration

Public user registration was disabled.

### Broad Editor Permissions

Test users retain Viewer organization roles instead of receiving global Editor access.

### Hard-Coded Passwords

Static sample passwords were replaced with generated credentials.

### Deprecated API Keys

API-key automation was replaced with Grafana service accounts and service-account tokens.

### Long-Lived Tokens

Automation tokens were created with explicit expiration periods.

### Unsupported Custom RBAC

Fine-grained custom-role behavior was not falsely represented as an OSS capability.

### Enterprise Audit Configuration

Native enterprise auditing was replaced with OSS-compatible logs and API-derived security evidence.

### Permission Matrix Conflict

Conflicting requirements in the supplied material were documented and the explicit folder permission matrix was used as the authoritative model.

### Manual Permission Review

A manual audit checklist was replaced with a reusable API-driven access-audit script.
