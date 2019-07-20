+++
date = "2019-03-08T10:00:00+02:00"
draft = true
title = "Kubernetes Continuous Integration"
tags = ["Kubernetes", "CI/CD","Continuous Integration", "Helm"]
categories = ["Development"]
+++

# Kubernetes configuration as Code

Complex Kubernetes application consists from multiple Kubernetes resources, defined in YAML files. Authoring a properly formatted YAML files that are also a valid Kubernetes specification, that should also comply to some policy can be a challenging task.

These YAML files are your application deployment and configuration code and should be addressed as code.

As with code, Continuous Integration approach should be applied to a Kubernetes configuration files.

## Git Repository

Create a separate Git repository that contains Kubernetes configuration files. Define a Continuous Integration pipeline that is triggered automatically for for every change and can validate it without human intervention.

## Helm

Helm helps you manage complex Kubernetes applications. Using Helm Charts you define, install, test and upgrade Kubernetes application.

Here I'm going to focus on using Helm for authoring complex Kubernetes application.

The same Kubernetes application can be installed in multiple environments: development, testing, staging and production. Helm template helps to separate application structure from environment configuration by keeping environment specific values in external files.

### Dependency Management

Helm also helps with dependency management. A typical Kubernetes application can be composed from multiple services developed by other teams and open source community.

A `requirements.yaml` file is a YAML file in which developers can declare Helm chart dependencies, along with the location of the chart and the desired version. For example, this requirements file declares two dependencies:

Where possible, use version ranges instead of pinning to an exact version. The suggested default is to use a patch-level version match:

```txt
version: ~1.2.3
```

This will match version 1.2.3 and any patches to that release. In other words, ~1.2.3 is equivalent to >= 1.2.3, < 1.3.0

## YAML

YAML is the most convenient way to write Kubernetes configuration files. YAML is easier for humans to read and write than other common data formats like XML or JSON. Still it's recommended to use automatic YAML linters to avoid syntax and formatting errors.

[yamlint](https://github.com/adrienverge/yamllint)

### Helm Chart Validation

Helm has a `helm lint` command that runs a series of tests to verify that the chart is well-formed. The `helm lint` also converts YAML to JSON, and this ways is able to detect some YAML errors.

```text
helm lint mychart

==> Linting mychart
[ERROR] templates/deployment.yaml: unable to parse YAML
    error converting YAML to JSON: yaml: line 53: did not find expected '-' indicator
```

There are few issues with `helm lint`, you should be aware of:
    - no real YAML validation is done: only YAML to JSON conversion errors are detected
    - it shows wrong error line number: no the actual line in a template that contains the detected error

So, I recommend also to use YAML linter, like `yamllint` to perform YAML validation.

First, you need to generate Kubernetes YAML files from a Helm chart. The `helm template` renders chart templates locally and prints the output to the `stdout`.

```sh
helm template --namespace test --values dev-values.yaml
```

Pipe `helm template` and `yamllint` together to validate rendered YAML files.

```sh
helm template mychart | yamllint -

stdin
  41:81     error    line too long (93 > 80 characters)  (line-length)
  43:1      error    trailing spaces  (trailing-spaces)
  151:9     error    wrong indentation: expected 10 but found 8  (indentation)
  245:10    error    syntax error: expected <block end>, but found '<block sequence start>'
  293:1     error    too many blank lines (1 > 0)  (empty-lines)
```

Now there are multiple ways to inspect these errors:

```sh
# using vim editor
vim <(helm template mychart)

# using cat command (with line number)
cat -n <(helm template mychart)

# printing error line and few lines around it, replacing spaces with dots
helm template hermes | sed -n 240,250p | tr ' ' '⋅'
```

## Valid Kubernetes Configuration

When authoring Kubernetes configuration files, it's important not only check if they are valid YAML files, but if they are valid Kubernetes files.

It turns out that the Kubernetes supports OpenAPI specification and it's possible to generate Kubernetes JSON schema for every Kubernetes API version.

[Gareth Rushgrove](https://github.com/garethr) wrote a [blog post](https://www.morethanseven.net/2017/06/26/schemas-for-kubernetes-types/) on this topic and maintains the [garethr/kubernetes-json-schema](https://github.com/garethr/kubernetes-json-schema) GitHub repository with most recent Kubernetes and OpenShift JSON schemas for all API versions. What a great contribution to the community!

Now, with Kubernetes API JSON schema, it's possible to validate any YAML file if it's a valid Kubernetes configuration file.

The [kubeval](https://github.com/garethr/kubeval) tool (also authored by Gareth Rushgrove) is to help.

Run `kubeval` piped with `helm template` command.

```sh
helm template mychart | kubeval
```

The output below sows single detected error in `Service` definition: invalid annotation. The `kubeval` could be more specific, by providing `Service` name, but event AS IS it is a valuable output for detecting Kubernetes configuration errors.

```text
The document stdin contains a valid Secret
The document stdin contains a valid Secret
The document stdin contains a valid ConfigMap
The document stdin contains a valid ConfigMap
The document stdin contains a valid PersistentVolumeClaim
The document stdin contains an invalid Service
---> metadata.annotations: Invalid type. Expected: object, given: null
The document stdin contains a valid Service
The document stdin contains a valid Deployment
The document stdin contains a valid Deployment
The document stdin is empty
The document stdin is empty
The document stdin is empty
The document stdin is empty
```


https://github.com/garethr/kubetest
