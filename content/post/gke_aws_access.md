+++
date = "2020-02-12T10:00:00+02:00"
draft = true
title = "Securely access AWS from GKE"
tags = ["Kubernetes","GKE", "AWS", "GCP", "IAM", "security"]
categories = ["DevOps", "Security", "Kubernetes", "AWS", "Google Cloud"]
+++

# Securely Access AWS from GKE

It is not a rare case when an application running on Google Kubernetes Engine (GKE) needs to access Amazon Web Services (AWS) APIs. Any application has needs. Maybe it needs to run an analytics query on Amazon Redshift, access data stored in Amazon S3 bucket, convert text to speech with Amazon Polly or use any other AWS service. This multi-cloud scenario is common nowadays, as companies are working with multiple cloud providers.

Cross-cloud access introduce a new challenge; how to manage cloud credentials, required to access from one cloud provider, to services running in the other. The naive approach, distributing and saving cloud provider secrets is not the most secure approach; distributing long-term credentials to each service, that needs to access AWS services, is challenging to manage and a potential security risk.

## Current Solutions

Each cloud provides it's own unique solution to overcome this challenge, and if you are working with a single cloud provider, it's more than enough.

Google Cloud announced a [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity), the recommended way for GKE applications to authenticate to and consume other Google Cloud services. Workload Identity works by binding Kubernetes service accounts and Cloud IAM service accounts, so you can use Kubernetes-native concepts to define which workloads run as which identities, and permit your workloads to automatically access other Google Cloud services, all without having to manage Kubernetes secrets or IAM service account keys! Read DoiT [Kubernetes GKE Workload Identity](https://blog.doit-intl.com/kubernetes-gke-workload-identity-75fa197ff6bf) blog post.

Amazon Web Services supports a similar functionality with [IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) feature. With IAM roles for service accounts on Amazon EKS clusters, you can associate an IAM role with a Kubernetes service account. This service account can then provide AWS permissions to the containers in any pod that uses that service account. With this feature, you no longer need to provide extended permissions to the worker node IAM role so that pods on that node can call AWS APIs.

But what if you are running your application workload on GKE cluster and would like to access AWS services without compromising on security?

## Use Case Definition

Let's assume that you already have an AWS account, and a GKE cluster, and your company has decided to run a microservice-based application on GKE cluster, but still wants to use resources in the AWS account (Amazon S3 and SNS services) to integrate with other systems deployed on AWS.

For example, the *orchestration job* (deployed as a Kubernetes Job) is running inside a GKE cluster and needs to upload a data file into a S3 bucket and send a message to an Amazon SNS topic. The equivalent command-line might be:

```sh
aws s3 cp data.csv s3://my-data-bucket/datagram_12345.csv
aws sns publish --topic-arn arn:aws:sns:us-west-2:123456789012:my-data-topic --message "datagram_12345.csv apply geo-filter"
```

Pretty simple example. In order for these commands to succeed, the *orchestration job* must have AWS credentials available to it, and those credentials must be able to make the relevant API calls.

## The Naive (and non-secure) Approach: IAM long-term credentials

Export AWS Access Key and Secret Key for some AWS IAM User, and inject AWS credentials into the *orchestration job*, either as a credentials file or environment variables. Probably not doing this directly, but using [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) resource protected with [RBAC authorization policy](https://kubernetes.io/docs/concepts/configuration/secret/#clients-that-use-the-secret-api).

The risk here is that these credentials never expire. They have to be transferred somehow from the AWS environment to the GCP environment, and in most cases, people want them to be stored somewhere so that they can be used to re-create the *orchestration job* later if required.

When using long-term AWS credentials, there are multiple ways that your AWS account can be compromised; unintentionally committing AWS credentials into a GitHub repository, keeping them in a Wiki system, reusing credentials for different services and applications, allowing non-restricted access and, [so on](https://rhinosecuritylabs.com/aws/aws-iam-credentials-get-compromised/).

While it's possible to design a proper credentials management solution for issued IAM User credentials, it won't be required if you will never create these long-term credentials in the first place.

## The Proposed Approach

The basic idea is to assign [AWS IAM Role](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html) to GKE Pod, similarly to **Workload Identity** and **EKS IAM Roles fo Service Accounts** cloud-specific features.

Luckily for us, AWS allows to create an IAM role for OpenID Connect Federation [OIDC](https://openid.net/connect/) identity providers instead of IAM users. On the other hand, Google implements OIDC provider and integrates it tightly with GKE through **Workload Identity** feature. Providing a valid OIDC token to GKE pod, running under Kubernetes Service Account linked to a Google Cloud Service Account. All these may come in handy to implement GKE-to-AWS secure access.

### Exchanging OIDC access token to ID token

There is one thing missing, required to complete the puzzle.
With properly setup **Workflow Identity** GKE Pod gets an OIDC **access token** that allows access to Google Cloud services. In order to get temporary AWS credentials from AWS STS service, you need to provide a valid OIDC **ID token**. 

AWS SDK (and `aws-cli` tool) will automatically request temporary AWS credentials form STS service, when the following environment variables are properly setup:

- `AWS_WEB_IDENTITY_TOKEN_FILE` - the path to the web identity token file (OIDC ID token)
- `AWS_ROLE_ARN` - the ARN of the role to assume by Pod containers
- `AWS_ROLE_SESSION_NAME` - the name applied to this assume-role session

This may sound a bit complex, but I will provide a step-by-step guide and supporting open source project [dointl/gtoken](https://github.com/doitintl/gtoken) to simplify the setup.

### `gtoken-webhook` Kubernetes Mutating Admission webhook

The gtoken-webhook is a Kubernetes mutating admission webhook, that mutates any K8s Pod running under specially annotated Kubernetes Service Account (see details below).

#### gtoken-webhook mutation flow

The `gtoken-webhook` injects a `gtoken` `initContainer` into a target Pod and an additional `gtoken` sidekick container (to refresh an OIDC ID token a moment before expiration), mounts token volume and injects three AWS-specific environment variables. The `gtoken` container generates a valid GCP OIDC ID Token and writes it to the token volume. It also injects required AWS environment variables.

The AWS SDK will automatically make the corresponding `AssumeRoleWithWebIdentity` calls to AWS STS on your behalf. It will handle in memory caching as well as refreshing credentials as needed.

![GKE-AWS](/img/gke-aws.png)

## The Configuration Flow Guide

### Deploy `gtoken-webhook`

1. To deploy the `gtoken-webhook` server, we need to create a webhook service and a deployment in our Kubernetes cluster. It’s pretty straightforward except one thing, which is the server’s TLS configuration. If you’d care to examine the [deployment.yaml](https://github.com/doitintl/gtoken/blob/master/deployment/deployment.yaml) file, you’ll find that the certificate and corresponding private key files are read from command line arguments, and that the path to these files comes from a volume mount that points to a Kubernetes secret:

```yaml
[...]
      args:
      [...]
      - --tls-cert-file=/etc/webhook/certs/cert.pem
      - --tls-private-key-file=/etc/webhook/certs/key.pem
      volumeMounts:
      - name: webhook-certs
        mountPath: /etc/webhook/certs
        readOnly: true
[...]
   volumes:
   - name: webhook-certs
     secret:
       secretName: gtoken-webhook-certs
```

The most important thing to remember is to set the corresponding CA certificate later in the webhook configuration, so the `apiserver` will know that it should be accepted. For now, we’ll reuse the script originally written by the Istio team to generate a certificate signing request. Then we’ll send the request to the Kubernetes API, fetch the certificate, and create the required secret from the result.

First, run the [webhook-create-signed-cert.sh](https://github.com/doitintl/gtoken/blob/master/deployment/webhook-create-signed-cert.sh) script and check if the secret holding the certificate and key has been created:

```text
./deployment/webhook-create-signed-cert.sh

creating certs in tmpdir /var/folders/vl/gxsw2kf13jsf7s8xrqzcybb00000gp/T/tmp.xsatrckI71
Generating RSA private key, 2048 bit long modulus
.........................+++
....................+++
e is 65537 (0x10001)
certificatesigningrequest.certificates.k8s.io/gtoken-webhook-svc.default created
NAME                         AGE   REQUESTOR              CONDITION
gtoken-webhook-svc.default   1s    alexei@doit-intl.com   Pending
certificatesigningrequest.certificates.k8s.io/gtoken-webhook-svc.default approved
secret/gtoken-webhook-certs configured
```

Once the secret is created, we can create a deployment and service. These are standard Kubernetes deployment and service resources. Up until this point we’ve produced nothing but an HTTP server that’s accepting requests through a service on port `443`:

```sh
kubectl create -f deployment/deployment.yaml

kubectl create -f deployment/service.yaml
```

### Configure Mutating Admission webhook

Now that our webhook server is running, it can accept requests from the `apiserver`. However, we should create some configuration resources in Kubernetes first. Let’s start with our validating webhook, then we’ll configure the mutating webhook later. If you take a look at the [webhook configuration](https://github.com/doitintl/gtoken/blob/master/deployment/mutatingwebhook.yaml), you’ll notice that it contains a placeholder for `CA_BUNDLE`:

```yaml
[...]
      service:
        name: gtoken-webhook-svc
        namespace: default
        path: "/pods"
      caBundle: ${CA_BUNDLE}
[...]
```

There is a [small script](https://github.com/doitintl/gtoken/blob/master/deployment/webhook-patch-ca-bundle.sh) that substitutes the CA_BUNDLE placeholder in the configuration with this CA. Run this command before creating the validating webhook configuration:

```sh
cat ./deployment/mutatingwebhook.yaml | ./deployment/webhook-patch-ca-bundle.sh > ./deployment/mutatingwebhook-bundle.yaml
```

Create mutating webhook configuration:

```sh
kubectl create -f deployment/mutatingwebhook-bundle.yaml
```

### Configure RBAC for gtoken-webhook

Create Kubernetes Service Account to be used with `gtoken-webhook`:

```sh
kubectl create -f deployment/service-account.yaml
```

Define RBAC permission for webhook service account:

```sh
# create a cluster role
kubectl create -f deployment/clusterrole.yaml
# define a cluster role binding
kubectl create 0f deployment/clusterrolebinding.yaml
```

### Flow Variables

Some of the following variables should be provided by user, others will be automatically generated and reused in the following steps.

- `PROJECT_ID` - GCP project ID (provided by user)
- `CLUSTER_NAME` - GKE cluster name (provided by user)
- `GSA_NAME` - Google Cloud Service Account name (provided by user)
- `GSA_ID` - Google Cloud Service Account unique ID (generated by Google)
- `KSA_NAME` - Kubernetes Service Account name (provided by user)
- `KSA_NAMESPACE` - Kubernetes namespace (provided by user)
- `AWS_ROLE_NAME` - AWS IAM role name (provided by user)
- `AWS_POLICY_NAME` - an AWS IAM policy to assign to IAM role (provided by user)
- `AWS_ROLE_ARN` - AWS IAM Role ARN identifier (generated by AWS)

### Google Cloud: Enable GKE Workload Identity

Create a new GKE cluster with [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity) enabled:

```sh
gcloud beta container clusters create ${CLUSTER_NAME} --identity-namespace=${PROJECT_ID}.svc.id.goog
```

or update an existing cluster:

```sh
gcloud beta container clusters update ${CLUSTER_NAME} --identity-namespace=${PROJECT_ID}.svc.id.goog
```

### Google Cloud: Create a Google Cloud Service Account

Create a Google Cloud Service Account:

```sh
# create GCP Service Account
gcloud iam service-accounts create ${GSA_NAME}

# get GCP SA UID to be used for AWS Role with Google OIDC Web Identity
GSA_ID=$(gcloud iam service-accounts describe --format json ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com  | jq -r '.uniqueId')
```

Update `GSA_NAME` Google Service Account with following roles:

- `roles/iam.workloadIdentityUser` - impersonate service accounts from GKE Workloads
- `roles/iam.serviceAccountTokenCreator` - impersonate service accounts to create OAuth2 access tokens, sign blobs, or sign JWTs

```sh
gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --role roles/iam.serviceAccountTokenCreator \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
  ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
```

### AWS: Create AWS IAM Role with Google OIDC Federation

Prepare a role trust policy document for Google OIDC provider:

```sh
cat > gcp-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "accounts.google.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "accounts.google.com:sub": "${GSA_SA}"
        }
      }
    }
  ]
}
EOF
```

Create AWS IAM Role with Google Web Identity:

```sh
aws iam create-role --role-name ${AWS_ROLE_NAME} --assume-role-policy-document file://gcp-trust-policy.json
```

Assign AWS Role desired policies:

```sh
aws iam attach-role-policy --role-name ${AWS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/${AWS_POLICY_NAME}
```

Get AWS Role ARN to be used in K8s SA annotation:

```sh
AWS_ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query Role.Arn --output text)
```

### GKE: Create a Kubernetes Service Account

Create K8s namespace:

```sh
kubectl create namespace ${K8S_NAMESPACE}
```

Create K8s Service Account:

```sh
kubectl create serviceaccount --namespace ${K8S_NAMESPACE} ${KSA_NAME}
```

Annotate K8s Service Account with GKE Workload Identity (GCP Service Account email):

```sh
kubectl annotate serviceaccount --namespace ${K8S_NAMESPACE} ${KSA_NAME}
  iam.gke.io/gcp-service-account=${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
```

Annotate K8s Service Account with AWS Role ARN:

```sh
kubectl annotate serviceaccount --namespace ${K8S_NAMESPACE} ${KSA_NAME}
  amazonaws.com/role-arn=${AWS_ROLE_ARN}
```

### Run Demo

Run a new K8s Pod with K8s ${KSA_NAME} Service Account:

```sh
# run a pod (with AWS CLI onboard) in interactive mod
kubectl run -it --rm --generator=run-pod/v1 --image mikesir87/aws-cli --serviceaccount ${KSA_NAME} test-pod

# in Pod shell: check AWS assumed role
aws sts get-caller-identity

# the output should look similar to below
{
    "UserId": "AROA9GB4GPRFFXVHNSLCK:gtoken-webhook-gyaashbbeeqhpvfw",
    "Account": "906385953612",
    "Arn": "arn:aws:sts::906385953612:assumed-role/bucket-full-gtoken/gtoken-webhook-gyaashbbeeqhpvfw"
}

```

### External References

- **GitHub:** Securely access AWS services from GKE cluser with [doitintl/gtoken](https://github.com/doitintl/gtoken)
- **AWS Docs:** [Creating a Role for Web Identity or OpenID Connect Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html)
- **Blog:** Kubernetes GKE Workload Identity [link](https://blog.doit-intl.com/kubernetes-gke-workload-identity-75fa197ff6bf)
- **AWS Blog:** Introducing fine-grained IAM roles for service accounts [link](https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/)
- **GitHub:** AWS Auth using WebIdentityFederation from Google Cloud [shrikant0013/gcp-aws-webidentityfederation](https://github.com/shrikant0013/gcp-aws-webidentityfederation) GitHub project
- **Blog:** Using GCP Service Accounts to access AWS IAM Roles [blog post](https://cevo.com.au/post/2019-07-29-using-gcp-service-accounts-to-access-aws/) by Colin Panisset
