---
last_updated: 2026-10-21
---

# AutoMQ fork guidance

This repository is an AutoMQ-maintained fork of Strimzi. Read [docs/automq-adaptation.md](docs/automq-adaptation.md) before changing the AutoMQ build path, Kafka version metadata, dependency collision ignore list, or container image release process.

The document is the repository-specific source of truth for:

- the boundary between the Strimzi Cluster Operator and the AutoMQ Kafka image;
- the Kafka/AutoMQ version matrix and multi-version build procedure;
- the changes required when AutoMQ follows a new Apache Kafka base version; and
- deploying an AutoMQ image with Strimzi.

Keep the document current when the build script, supported versions, image naming, or release workflow changes.
