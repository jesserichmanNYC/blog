+++
date = "2019-12-23T10:00:00+02:00"
draft = true
title = "Kubernetes and Secrets Management in Cloud"
tags = ["Kubernetes", "EKS","GKE", "AWS", "GCP", "Secrets Manager"]
categories = ["Development", "Security", "Kubernetes"]
+++

## Introduction

Secrets are essential for operation of many production systems. Unintended secrets exposure is one of the top risks that should be properly addressed. Developers should do their best to protect application secrets.

The problem becomes even harder, once company moves to a microservice architecture and multiple services require an access to different secrets in order to properly work. And this leads to a new challenges: how to distribute, manage, monitor and rotate application secrets, avoiding unintended exposure?

## Kubernetes Secrets

Kubernetes provides an object called Secret, which you can use to store application sensitive data, like passwords, SSH keys, API keys, tokens and others. Kubernetes Secret can be injected into a Pod container either as an environment variable or mounted as a file. Using Kubernetes Secrets, allows to abstract sensitive data and configuration from application deployment.

For example, a Kubernetes secret can be created with command `kubectl create secret`:

```sh
kubectl create secret generic db-credentials -n default --from-literal=user=dbuser --from-literal=password=quick.fox.5312
```

or Kubernetes `db-credentials.yaml` file, that describes the same secret:

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

Please note, that storing a sensitive data in a Kubernetes Secret does not make it secure. By default, all data in Kubernetes Secrets is stored as a plantext encoded with `base64`.

Starting with version 1.13, Kubernetes supports [encrypting Secrets data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/), using `EncryptionConfiguration` object with built-in or external encryption provider.

List of currently supported encryption providers:

- [built-in providers](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#providers): `aescbc`, `aesgsm`, `secretbox`
- [KMS providers](https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/):
  - [Google KMS provider](https://cloud.google.com/kubernetes-engine/docs/how-to/encrypting-secrets)
  - [AWS KMS provider](https://github.com/kubernetes-sigs/aws-encryption-provider)
  - [Azure KMS provider](https://github.com/Azure/kubernetes-kms)

However Secrets encryption at rest is not enforced by default. And even when enabled, it is not sufficient and cannot be considered a complete secrets management solution.

A complete secrets management solution must also support: secrets distribution, rotation, fine-grained access control, audit log, usage monitoring, versioning, strongly encrypted storage, convenient API and client SDK/s and probably some other useful features.

## Cloud Secrets Management

Multiple cloud vendors provide secret management services, as part of their cloud platform offering, helping you to protect secrets needed to access applications, services, and APIs. Using these services eliminates the need to hardcode sensitive information in plain text and develop home-grown secrets management lifecycle. Secrets management services enable you to control access to application secrets using fine-grained permissions and auditing.

## Integrating Kubernetes with Secrets Management services

In general, any application can use vendor-specific SDK/API to access secrets stored in a secrets management service. Usually this requires modifying application code or using some kind of bootstrap scripts or [Init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/), using client CLI tools or web APIs.

### Make it easy with `secrets-init` tool

We release a [doitintl/secrets-init](https://github.com/doitintl/secrets-init) open source tool (Apache License 2.0) that simplifies integration of cloud-native Secrets Management services with containerized workload running on cloud-managed or self-managed Kubernetes clusters.

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

### Integration with Docker

The `secrets-init` is a statically compiled binary file (without external dependencies) and can be easily embedded included into any Docker image. Download `secrets-init` binary and use it as the Docker container `ENTRYPOINT`.

For example:

```dockerfile
FROM node:alpine

# download secrets-init binary
ENV SECRETS_INIT_VERSION=v0.2.1
ENV SECRETS_INIT_URL=https://github.com/doitintl/secrets-init/releases/download/v0.2.1/secrets-init_Linux_amd64.tar.gz
ENV SECRETS_INIT_SHA256=a2849460c650e9e7a29d9d0764e2b5fc679961e6667ad1c4416210fa791be29f
RUN mkdir -p /opt/secrets-init && cd /opt/secrets-init \
    && wget -qO secrets-init.tar.gz "$SECRETS_INIT_URL" \
    && echo "$SECRETS_INIT_SHA256  secrets-init.tar.gz" | sha256sum -c - \
    && tar -xzvf secrets-init.tar.gz \
    && mv secrets-init /usr/local/bin \
    && rm secrets-init.tar.gz

# set container entrypoint to secrets-init
ENTRYPOINT ["/usr/local/bin/secrets-init"]

# ... copy app dependencies and code
# ... define app CMD
```

### Integration with Kubernetes

In order to use `secrets-init` with Kubernetes object (Pod/Deployment/Job/etc) without modifying Docker image, consider injecting `secrets-init` into a target Pod through [Init Container](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/).
You can use the [doitint/secrets-init](https://hub.docker.com/r/doitintl/secrets-init) Docker image or create your own. Copy `secrets-init` binary from init container to a common shared volume and change Pod `command` to run `secrets-init` as a first command.

### Integration with AWS Secrets Manager

To start using `secrets-init` with AWS Secrets Manager, user should put an AWS secret ARN as environment variable value. The `secrets-init` will resolve any environment value, using specified ARN, to a referenced secret value.

Example, using `secrets-init` with Kubernetes Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: printenv-job
spec:
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: iam-secrets-manager-ro
      initContainers:
        - name: secrets-init
          image: doitintl/secrets-init:v0.2.1
          command:
            - sh
          args:
            - -c
            - "cp /usr/local/bin/secrets-init /secrets-init/bin/"
          volumeMounts:
          - mountPath: /secrets-init/bin
            name: secrets-init-volume
      containers:
      - image: alpine:3
        name: print-env
        env:
          - name: AWS_REGION
            value: us-west-2
          - name: TOP_SECRET
            value: arn:aws:secretsmanager:us-west-2:906364353610:secret:topsecret-Acdaq8
        command:
          - /secrets-init/bin/secrets-init
        args:
          - sh
          - -c
          - 'echo $TOP_SECRET'
        volumeMounts:
        - mountPath: /secrets-init/bin
          name: secrets-init-volume
      volumes:
      - name: secrets-init-volume
        emptyDir: {}
```

### Integration with AWS Systems Manager Parameter Store

It is possible to use AWS Systems Manager Parameter Store to store application parameters as plain text or encrypted (kind of secrets).

As with the previous example, user can put AWS Parameter Store ARN as environment variable value. The `secrets-init` will resolve any environment value, using specified ARN, to a referenced parameter value.

AWS Systems Manager Parameter Store format example:

```sh
# environment variable referencing AWS Systems Manager Parameter Store secret
MY_API_KEY=arn:aws:ssm:$AWS_REGION:$AWS_ACCOUNT_ID:parameter/api/key

# environment variable passed to a child process, as resolved by `secrets-init`
MY_API_KEY=key-123456789
```

In order to resolve AWS secrets from AWS Secrets Manager and Parameter Store, `secrets-init` should run under IAM role that has permission to access desired secrets.

This can be achieved by assigning IAM Role to Kubernetes Pod or ECS Task. See [Introducing fine-grained IAM roles for service accounts](https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/) EKS blog post.

It's possible to assign IAM Role to EC2 instance, where container is running, but this option is considerably less secure and not recommended.

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

Hope, you find this post useful. I look forward to your comments and any questions you have.

---

*This is a **working draft** version. The final post version is published at [DoiT Blog](https://blog.doit-intl.com/) .*
