---
last_updated: 2026-10-21
---

# AutoMQ integration guide

This document describes the role of the `AutoMQ/strimzi-kafka-operator` fork, how AutoMQ Kafka images are built and deployed with Strimzi, and what must be checked when Kafka or Strimzi versions change.

## Repository role

Strimzi is a Kubernetes Operator. It uses `Kafka`, `KafkaNodePool`, `KafkaConnect`, and related custom resources to manage Kafka pods, services, configuration, and rolling updates. This repository is not the AutoMQ BYOC Operator and does not provision cloud resources, object storage, or AutoMQ data-plane clusters.

The AutoMQ-specific work in this fork is concentrated in `tools/automq/build-automq-image.sh` and a small set of dependency and image-build changes. The script places an AutoMQ Kafka distribution, such as `automq-1.7.5-rc1_kafka-3.9.1.tgz`, into the Strimzi Kafka image layout, adds the Strimzi agent, Kafka Exporter, JMX Exporter, Cruise Control, and third-party libraries, and pushes the resulting image.

Keep the following two artifacts separate:

| Artifact | Role | Must this repository build it? |
| --- | --- | --- |
| Strimzi Cluster Operator | Watches custom resources and creates or upgrades Kafka pods | No. A compatible official or internal Strimzi Operator can be used. |
| AutoMQ Kafka image | Runs the AutoMQ broker process | Yes, unless a matching published image already exists. |

## Operator version requirements

The Operator version and AutoMQ version are independent. The selected Operator must satisfy all of the following:

1. It supports the required `Kafka` APIs and deployment mode, such as KRaft and `KafkaNodePool`.
2. Its supported Kafka versions include the Kafka version declared by the AutoMQ image.
3. The Operator runtime, the Java runtime in the Kafka image, and the AutoMQ distribution have been tested together.
4. Production deployments pin a traceable Strimzi release or fork commit instead of following a floating `main` branch.

When `spec.kafka.image` is set, Strimzi uses that image directly. `spec.kafka.version` is still used for protocol versions, feature checks, and upgrade validation. `KafkaVersion.Lookup.kafkaImage()` consults `STRIMZI_KAFKA_IMAGES` only when the custom resource does not specify an image. Therefore, an official Strimzi Operator can run an AutoMQ image when it supports the declared Kafka version. The fork is used to share the AutoMQ image build, test, and release process; it does not make the Operator recognize a new runtime through a code change.

The current `main` branch has `release.version` set to `0.48.0-SNAPSHOT` and lists Kafka 3.9.0, 3.9.1, and 4.0.0. Treat this snapshot as a build baseline, not as a compatibility commitment for a particular AutoMQ release. Record the actual Operator image or chart version and commit used for each release.

## Using an AutoMQ image

The build script accepts these arguments:

```text
tools/automq/build-automq-image.sh <AUTOMQ_VERSION> <AUTOMQ_URL> <KAFKA_VERSION> <DOCKER_ORG> <PROJECT_NAME>
```

The script sets `DOCKER_TAG=${AUTOMQ_VERSION}-strimzi`. The final registry, organization, and repository are determined by `DOCKER_REGISTRY`, `DOCKER_ORG`, and `PROJECT_NAME`. For example, `DOCKER_ORG=automq` and `PROJECT_NAME=kafka` produce an image similar to `automq/kafka:1.7.5-rc1-strimzi`.

Set the image and its Kafka version explicitly in the Kafka custom resource:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: automq
spec:
  kafka:
    version: 3.9.1
    image: registry.example.com/automq/kafka:1.7.5-rc1-strimzi
    # Set storage, listeners, resources, and AutoMQ-specific configuration here.
  entityOperator:
    topicOperator: {}
    userOperator: {}
```

Install the Operator using the normal Strimzi installation flow, including the CRDs, RBAC resources, Deployment, or Helm chart. Provide registry credentials through `imagePullSecrets` or the Operator configuration supported by the deployment. If Kafka Connect, MirrorMaker 2, Kafka Exporter, or Cruise Control is also used, verify each component image against the AutoMQ and Kafka versions separately; `spec.kafka.image` replaces only the Kafka broker image.

## Current automated release flow

The automated build entry point is `.github/workflows/docker-strimzi-release.yaml` in `AutoMQ/automq`, rather than a GitHub Actions workflow in this repository. It can run automatically after a successful `GitHub Release` workflow or manually through `workflow_dispatch` with a release tag. The workflow clones the `main` branch of this repository, runs `tools/automq/build-automq-image.sh`, and builds and pushes only the Kafka image. It does not publish a new Strimzi Operator image.

The workflow currently hardcodes `KAFKA_VERSION` to `3.9.1`. If a new AutoMQ release uses another Kafka baseline, the workflow and the corresponding version/build adaptations must be updated first; the GitHub Release event does not infer a new Kafka version automatically.

## Required adaptation work

### Kafka version metadata

`kafka-versions.yaml` is the Strimzi build-time version source. It affects Kafka archive downloads, third-party libraries, generated installation files, and the Kafka version model used by the Operator build. For every new Kafka minor or patch baseline, check:

- `version`, `url`, SHA-512 `checksum`, `metadata`, `third-party-libs`, and `supported/default`;
- whether `docker-images/artifacts/kafka-thirdparty-libs/<minor>.x/` needs a new directory or dependency versions;
- generated Helm, installation YAML, documentation, and image-map files after `make all`; and
- Kafka protocol, metadata version, `KafkaVersion` tests, and upgrade/downgrade tests.

An AutoMQ archive can use a different filename from an Apache Kafka archive. The script substitutes the target archive URL and checksum, then renames `automq-<version>_kafka-<kafka-version>.tgz` to the `kafka_2.13-<kafka-version>.tgz` name expected by Strimzi.

### Classpath collision ignore list

Strimzi combines the Kafka distribution's `libs/` directory with Strimzi third-party libraries and runs `find-classpath-collision.sh` from `docker-images/kafka-based/kafka/Makefile`. If AutoMQ and Strimzi contain different versions of a library, add the specific conflicting jar filename to `${KAFKA_VERSION}.ignorelist` only after confirming which copy should remain in the image.

The `IGNORE_LIST` in `build-automq-image.sh` is appended to the version-specific list. It is not a Maven exclude and does not change classpath ordering. When AutoMQ, Kafka, Java, or Strimzi dependencies change:

1. Collect all collision jars from the failed build.
2. Compare them with AutoMQ's `gradle/dependencies.gradle` and the archive's `libs/` directory.
3. Add only confirmed, expected collisions.
4. Re-run the same `grep -vFf` filtering used by `find-classpath-collision.sh` and verify that no unexpected collision remains.
5. Run `bash -n`, `git diff --check`, and a complete image build in CI.

### Version filtering

The current `build-automq-image.sh` uses several `sed` ranges that explicitly mention 3.9.0, 3.9.1, and 4.0.0. When another Kafka version is introduced, verify that the target version is enabled and all other versions are disabled as intended. Prefer changing this to generic filtering based on `KAFKA_VERSION` or `yq` rather than adding another hard-coded range.

## Multi-version builds

One Strimzi source branch can build multiple AutoMQ images. Each script invocation modifies `kafka-versions.yaml`, generated files, and the archive directory, so use a clean checkout, tag, or separate worktree for each AutoMQ/Kafka combination:

1. Select a traceable Strimzi commit or branch.
2. Build one AutoMQ/Kafka combination and assign it a unique image tag.
3. Complete the collision checks and image verification.
4. Clean the checkout before building the next combination.
5. Record `AutoMQ version → Kafka version → Strimzi commit → image digest`.

Multiple AutoMQ versions can use the same Strimzi source branch when that branch supports all required Kafka versions and Java runtimes. The Operator can be shared, while each broker image must have its own immutable tag and be selected explicitly in the Kafka custom resource.
