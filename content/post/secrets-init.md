+++
date = "2019-12-23T10:00:00+02:00"
draft = true
title = "Kubernetes and Secrets Management in Cloud"
tags = ["Kubernetes", "EKS","GKE", "AWS", "GCP", "Secrets Manager"]
categories = ["Development", "Security", "Kubernetes"]
+++

## Introduction

Secrets are essential for operation of many production systems. Unintended secrets exposure is one of the top risks that should properly addressed. Most companies must do their best to protect their secrets.

The problem becomes even harder, once company moves to a microservice architecture and multiple services need different secrets in order to work. How to distribute, manage, monitor and rotate these secrets, avoiding unintended leaks?

## Kubernetes Secrets

Kubernetes provides a resource called Secret, which you can use to store sensitive data, like passwords, SSH keys, API keys, tokens and other. Kubernetes Secret can be injected into Pod container either as environment variable or file. Using Kubernetes Secrets, allows you to abstract sensitive data data from deployments that describe containerized workflows.

You can create secret with command line `kubectl create secret`:

```sh
kubectl create secret generic db-credentials -n default --from-literal=user=dbuser --from-literal=password=quick.fox.5312
```

or using Kubernetes `db-credentials.yaml` file, that describes the same secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  password: cXVpY2suZm94LjUzMTI=
  user: ZGJ1c2Vy
```

```sh
kubectl create -f db-credentials.yaml
```

But storing sensitive data in Kubernetes Secret does not make it secure. By default, all data in Kubernetes Secrets is stored as `base64` encoded pain text.

Starting with version 1.13, Kubernetes supports [encrypting Secrets data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/), using `EncryptionConfiguration` object with encryption provider.

Supported encryption providers:

- [built-in providers](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#providers): `aescbc`, `aesgsm`, `secretbox`
- [KMS providers](https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/):
  - [Google KMS provider](https://cloud.google.com/kubernetes-engine/docs/how-to/encrypting-secrets)
  - [AWS KMS provider](https://github.com/kubernetes-sigs/aws-encryption-provider)
  - [Azure KMS provider](https://github.com/Azure/kubernetes-kms)

However encryption at rest is not enforced by default, and even if enabled, it not sufficient and cannot be considered a sufficient secret management solution.

A complete Secret Management solution must also support: secrets distribution, rotation, fine-grained access control, audit log, usage monitoring, versioning, strongly encrypted storage, convenient API and client SDK/s and probably some other useful features.

## Cloud Secrets Management

## Binding them together

The [doitintl/secrets-init](https://github.com/doitintl/secrets-init) is an open source tool (Apache License 2.0) that simplifies integration of cloud-native Secrets Management services with containerized workload running on cloud-managed or self-managed Kubernetes clusters.

In its essence, the `secrets-init` is a minimalistic init system, designed to run as `PID 1` inside a container environment, similarly to [dumb-init](https://github.com/Yelp/dumb-init), and provides a fluent integration with multiple cloud-native Secrets Management services, like:

- [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)
- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [Google Secret Manager (Beta)](https://cloud.google.com/secret-manager/docs/)

### Why you need an init system in Docker container?

Please [read Yelp *dumb-init* repo explanation](https://github.com/Yelp/dumb-init/blob/v1.2.0/README.md#why-you-need-an-init-system)

Summary:

- Proper signal forwarding
- Orphaned zombies reaping

### What `secrets-init` does

The `secrets-init` runs as `PID 1`, acting like a simple init system serving as `ENTRYPOINT` or first container command, which is responsible to launch a child process, proxying all systems signals to a session rooted at that child process. This is the essence of init process. On the other hand, the `secrets-init` also passes _almost_ all environment variables without modification, replacing special _secret variables_ with values from Secret Management services.

### Integration with AWS Secrets Manager

To start using `secrets-init` with AWS Secrets Manager, user should put an AWS secret ARN as environment variable value. The `secrets-init` will resolve any environment value, using specified ARN, to a referenced secret value.

AWS Secret Manager example:

```sh
# environment variable referencing AWS Secrets Manager secret
MY_DB_PASSWORD=arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:mydbpassword-cdma3

# environment variable passed to a child process, as resolved by `secrets-init`
MY_DB_PASSWORD=very-secret-password
```

### Integration with AWS Systems Manager Parameter Store

It is possible to use AWS Systems Manager Parameter Store to store application parameters as plain text or encrypted (kind of secrets).

As with the previous example, user can put AWS Parameter Store ARN as environment variable value. The `secrets-init` will resolve any environment value, using specified ARN, to a referenced parameter value.

AWS Systems Manager Parameter Store example

```sh
# environment variable referencing AWS Systems Manager Parameter Store secret
MY_API_KEY=arn:aws:ssm:$AWS_REGION:$AWS_ACCOUNT_ID:parameter/api/key

# environment variable passed to a child process, as resolved by `secrets-init`
MY_API_KEY=key-123456789
```

In order to resolve AWS secrets from AWS Secrets Manager and Parameter Store, `secrets-init` should run under IAM role that has permission to access desired secrets.

This can be achieved by assigning IAM Role to Kubernetes Pod or ECS Task. It's possible to assign IAM Role to EC2 instance, where container is running, but this option is less secure.

### Integration with Google Secret Manager

Google Cloud released recently a new service for managing secrets in the cloud: [Google Secret Manager](https://cloud.google.com/secret-manager)

User can put Google secret name, using `secrets-init` recognizable prefix (`gcp:secretmanager:`), following secret name (`projects/{PROJECT_ID}/secrets/{SECRET_NAME}` or `projects/{PROJECT_ID}/secrets/{SECRET_NAME}/versions/{VERSION}`) as environment variable value. The `secrets-init` will resolve any environment value, using the specified name, to a referenced secret value.

```sh
# environment variable referencing Google Secret Manager secret (without version)
MY_DB_PASSWORD=gcp:secretmanager:projects/$PROJECT_ID/secrets/mydbpassword
# OR versioned secret (with numeric version or 'latest')
MY_DB_PASSWORD=gcp:secretmanager:projects/$PROJECT_ID/secrets/mydbpassword/versions/2

# environment variable passed to a child process, as resolved by `secrets-init`
MY_DB_PASSWORD=very-secret-password
```

In order to resolve Google secrets from Google Secret Manager, `secrets-init` should run under IAM role that has permission to access desired secrets.

This can be achieved by assigning IAM Role to Kubernetes Pod with [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity). It's possible to assign IAM Role to GCE instance, where container is running, but this option is less secure.

## Summary

...
