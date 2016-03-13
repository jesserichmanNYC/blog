+++
date = "2015-12-30T11:09:47+02:00"
draft = false
title = "Docker Pattern: Deploy and update dockerized application on cluster"
tags = ["Docker", "CoreOS", "fleet"]
categories = ["Development"]
+++

Docker is great technology that simplifies development and deployment of distributed applications.

While Docker serves as a core technology, many issues remain to be solved. We find ourselves struggling with some of these issues. For example:

* How to create an elastic Docker cluster?
* How to deploy and connect multiple containers together?
* How to build CI/CD process?
* How to register and discover system services and more?

For most, there are open source projects, or services available from the community as well as commercially, including from Docker, Inc.

In this post, I would like to address one such problem:

### How to automate Continuous Delivery for a Docker cluster?

In our application, every service is packaged as a Docker image. Docker image is our basic deployment unit. In a runtime environment (production, testing and others), we may have multiple containers, created from this image. For each service, we have a separate Git repository and one or more Dockerfile(s). We use this for building, testing, and packaging - will explain our project structure in the next blog post.

We've setup an automated Continuous Integration(CI) process. We use CircleCI. For every push to some branch for the service in a Git repository, the CI service triggers a new Docker build process and creates a new Docker image for the service. As part of the build process, if everything compiles and all unit and component tests pass, we push a newly created Docker image to our DockerHub repository.

At the end of CI process, we have a newly tested and ‘kosher’ Docker image in our DockerHub repository. Very nice indeed! However, we are left with several questions: 

* How to perform a rolling update of a modified service? 
* What is the target environment (i.e. some Docker cluster)? 
* How to find the ip of a dynamically created CoreOS host (we use AWS auto-scale groups)?
* How to connect to it in a secure way without the need to expose the SSH keys or cloud credentials (we use AWS for infrastructure)?

Our application runs on a CoreOS cluster. We have automation scripts that creates the CoreOS cluster on multiple environments: developer machine, AWS, or some VM infrustructure. When we have a new service version (i.e. Docker image), we need to find a way to deploy this service to the cluster. CoreOS uses **fleet** for cluster orchestration. **Fleetctl** is a command line client that can talk with the **fleet** backend and allows you to manage the CoreOS cluster. However, this only works in a local environment (machine or network). For some commands, **fleetctl** uses HTTP API and for others an SSH connection. The HTTP API is not protected so it makes no sense to expose it from your cloud environment. The SSH connection does not work when your architecture assumes there is no direct SSH connection to the cluster. Connecting through some SSH bastion machine, requiring the use of multiple SSH keys, and creating SSH configuration files, are not supported by the **fleetctl** program. I have no desire to store SSH keys or my cloud credentials for my production environment on any CI server due to security concerns.

### So, what do we do?

First, we want to deploy a new service or update some service when there is a new Docker image or image version available. We also want to be selective and pick images created from code in a specific branch or even specific build.

The basic idea is to create a Docker image that captures the system configuration. This image stores the configuration of all services at a specific point in time and from specific branches. The container created from this image should be run from within the target cluster. Besides captured configuration, we also have the deployment tool (**fleetctl** in our case), plus some code that detects services which need to be updated, deleted, or installed as a new service.

This idea leads to another question:

### How do you define and capture system configuration?

In CoreOS, every service can be described in **systemd unit** files. This is a plain text file that describes how and when to launch your service. I’m not going to explain how to write such files. There is a lot of info online. What's important in our case, the service systemd unit file contains a `docker run` command with parameters and image name that needs to be downloaded and executed. We keep the service systemd unit file in the same repository as the service code.

The image name: usually defined as a `repository/image_name:tag` string. **Tag** is the most important thing in our solution. As explained above, our CI server automatically builds a new Docker image on every push of the service to the GitHub repository. The CI job also tags the newly created image with 2 tags:
1. `branch` tag — taken from GitHub branch that triggered the build (`master`, `develop`, `feature-*` braches in our case)
2. `build_num-branch` tag — where we add a running build number prefix, just before branch name
As a result, in DockerHub, we have images for the latest build in any branch and also for every image we can identify the build job number and the branch it was created from.

As I said before, we keep service systemd unit file in the same repository as code. This file **does not** contain an image tag, only the repository and image name. See example below:

```
ExecStart=/usr/bin/docker run —name myservice -p 3000:3000 myrepo/myservice
```

Our CI service build job generates a new service **systemd** unit file for every successful build, replacing the above service invocation command with one that also contains a new tag. Using `build_num-branch` pattern (`develop` branch in our example), we use two simple utilities for this job: `cat` and `sed`. It’s possible to use a more advanced template engine.

```
ExecStart=/usr/bin/docker run — name myservice -p 3000:3000 myrepo/myservice:58-develop
```

As a last step, the CI build job “deploys” this new unit file to the system configuration Git repository.

```
git commit -am “Updating myservice tag to ‘58-develop’” myservice.service
git push origin develop
```

Another CI job that monitors changes in the system configuration repository will trigger a build and create a new Docker image that captures updated system configuration.

All we need to do now is to execute this Docker image on the Docker cluster. Something like this:

```
docker run -it —-rm=true myrepo/mysysconfig:develop
```

Our **system configuration** Dockerfile:

```
FROM alpine:3.2
MAINTAINER Alexei Ledenev <alexei.led@gmail.com>

ENV FLEET_VERSION 0.11.5

ENV gaia /home/gaia
RUN mkdir -p ${gaia}

WORKDIR ${gaia}
COPY *.service ./
COPY deploy.sh ./
RUN chmod +x deploy.sh

# install packages and fleetctl client
RUN apk update && \
 apk add curl openssl bash && \
 rm -rf /var/cache/apk/* && \
 curl -L “https://github.com/coreos/fleet/releases/download/v${FLEET_VERSION}/fleet-v${FLEET_VERSION}-linux-amd64.tar.gz" | tar xz && \
 mv fleet-v${FLEET_VERSION}-linux-amd64/fleetctl /usr/local/bin/ && \
 rm -rf fleet-v${FLEET_VERSION}-linux-amd64

CMD [“/bin/bash”, “deploy.sh”]
```

`deploy.sh` is a shell script for every service check. If it needs to be updated, created, or deleted, it executes the corresponding **fleetctl** command.

The final step:

### How do you run this “system configuration” container?

Currently, in our environment, we do this manually (from SSH shell) for development clusters and use systemd timers for CoreOS clusters on AWS. Systemd timer allows us to define a cron like job at the CoreOS cluster level.

We have plans to define a WebHook endpoint that will allow us to trigger deployment/update based on a WebHook event from the CI service.

Hope you find this post useful. I look forward to your comments and any questions you have.
