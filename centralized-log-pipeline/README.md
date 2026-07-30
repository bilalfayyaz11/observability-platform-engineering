# Centralized Log Pipeline

## Overview

This implementation provides an end-to-end centralized logging pipeline using Filebeat, Logstash, and Elasticsearch.

Application and Linux logs are collected by Filebeat, forwarded through the Beats protocol, parsed and enriched by Logstash, and indexed in Elasticsearch for centralized search and operational analysis.

## Architecture

    Application and Linux Logs
                |
                v
          Filebeat Agent
          filestream input
                |
                | Beats protocol
                | TCP 5044
                v
          Logstash Pipeline
       Grok parsing and enrichment
                |
                | Elasticsearch API
                | HTTP 9200
                v
           Elasticsearch
       Centralized searchable index

## Core Capabilities

- File-based application and system log collection
- Modern Filebeat `filestream` input
- Beats-based forwarding to Logstash
- Grok parsing of timestamps, severity levels, and messages
- Timestamp normalization using the Logstash date filter
- Log enrichment with pipeline and environment metadata
- Daily Elasticsearch index creation
- Centralized search through the Elasticsearch API
- Linux service management through systemd
- End-to-end pipeline and connectivity validation

## Repository Structure

    centralized-log-pipeline/
    ├── application/
    │   └── log_generator.py
    ├── elasticsearch/
    │   └── elasticsearch.yml
    ├── filebeat/
    │   └── filebeat.yml
    ├── logstash/
    │   └── pipeline.conf
    ├── testing/
    │   └── .gitkeep
    ├── component-versions.txt
    └── README.md

## Pipeline Flow

1. The Python application writes structured events to an application log file.
2. Filebeat monitors application and operating-system log sources.
3. Filebeat forwards events to Logstash on TCP port 5044.
4. Logstash parses and enriches each event.
5. Logstash sends processed events to Elasticsearch.
6. Elasticsearch stores the events in date-based indices.
7. Operators can search and analyze logs through Elasticsearch queries.

## Technology Stack

- Elasticsearch
- Logstash
- Filebeat
- Python
- Grok
- Elastic Common Schema fields
- Linux
- systemd
- REST APIs

## Validation Performed

- Elasticsearch cluster health verification
- Logstash configuration validation under the dedicated service account
- Filebeat configuration validation
- Filebeat-to-Logstash connectivity testing
- Service-state verification
- Port-listener verification
- Application log generation
- Elasticsearch index verification
- Document-count verification
- Error-event search
- Unique end-to-end pipeline test

## Skills Demonstrated

- Centralized logging architecture
- Elastic Stack administration
- Log ingestion engineering
- Log parsing and transformation
- Structured event generation
- Linux service operations
- Configuration validation
- API-based log retrieval
- Pipeline troubleshooting
- Observability platform engineering

## Operational Use Cases

- Centralized troubleshooting across distributed systems
- Application failure investigation
- Security-event collection
- Authentication-log analysis
- Infrastructure health monitoring
- Incident-response support
- Operational trend analysis

## Key Takeaways

A reliable logging platform requires more than collecting files. It requires consistent event structure, secure service execution, reliable transport, accurate timestamp handling, searchable storage, and end-to-end validation.

This implementation demonstrates the foundational architecture used by production observability and security-monitoring platforms.
