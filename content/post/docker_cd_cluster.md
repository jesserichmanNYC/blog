+++
date = "2015-12-30T11:09:47+02:00"
draft = true
title = "Docker Pattern: Deploy and update dockerized application on cluster"
tags = ["Docker", "CoreOS", "fleet"]
categories = ["Development"]
+++

Docker is a great technology that enables and simplifies development and deployment of distributed applications. During last year, I’m leading one of such projects.
While Docker serves as a core technology, there are too many puzzle pieces that are left aside and you find yourself struggling with these issues. How to create an elastic Docker cluster, how to deploy and connect multiple containers together, how to build CI and CD, how to register and discover other system services and more. For most of these issues there are open source projects, or services available from community and multiple companies, including Docker, Inc.

In this post I would like to share our solution for one of such problems: *how to automate Continuous Delivery for Docker cluster?*

In our application, every single service is packaged into Docker image. Docker image is our basic deployment unit. In runtime environment (production, testing and others) we can have multiple containers created from this image. For each service, we have a separate Git repository (hosted on GitHub) and one or more Dockerfile files we use for build, test and package (I might explain our project structure in the next blog post)

We set up a fully automated Continuous Integration (CI) process, where for every push to some branch in the service GitHub repository, the CI service, we are using (kudos to CircleCI), is triggering a new Docker build process and creates a new Docker image for the service. As a result of this build, if everything compiles and all units and component tests are passed, we push a newly created Docker image to our DockerHub repository.

At the end of CI process, we have a new tested and ‘kosher’ Docker image in our DockerHub repository. Very nice! Indeed! But, we are left to struggle with set of questions: how to perform a rolling update of modified service? What is the target environment (i.e. some Docker cluster)? how to find ip of dynamically created CoreOS host (we are using AWS auto-scale groups)? and how to connect to it in a secure way, without need to expose my SSH keys or cloud credentials (we are using AWS for infrastructure)?

Our application runs on CoreOS cluster. We have automation scripts, that can create CoreOS cluster on multiple environments: developer machine, AWS or some VM infrustructure. But now, when we have a new service version (i.e. Docker image), we need to find a way to deploy this service to the cluster. CoreOS is using **fleet** for cluster orchestration. **Fleetctl** is a command line client, that can talk with **fleet** backend and allows you to manage the CoreOS cluster. The problem is that it works only in local environment (machine or network). For some commands **fleetctl** is using HTTP API and for others SSH connection. The HTTP API is not protected, so it makes no sense to expose it from your cloud environment. The SSH connection also does not work, when you architecture assumes that there is no direct SSH connection to the cluster, but only through some SSH bastion machine and this requires to use multiple SSH keys and prepare some SSH configuration files, which are not supported by **fleetctl** program. I also have no desire to store SSH keys or my cloud credentials from my production environment on any CI server.

So, what choice do we have?

First, I want to be able to deploy a new service or update some service, when there is a new Docker image or image version available. I also what to be able to be picky and select images created from code in specific branch or even specific build.

The basic idea is to create a Docker image that captures system configuration. This image stores configuration of all services at specific point in time and from specific branches. The container created from this image should be run from within the target cluster. Beside captured configuration, it also has a deployment tool (**fleetctl** in our case), plus some code, that can help you to detect services that need to be updated, deleted or installed as a new service.

This idea moves focus to another question: *how do you define and capture system configuration?*

In CoreOS, every service can be described in **systemd unit** files. This is a plain text file, that describes how and when to launch your service. I’m not going to explain how to write such files, there is a lot of info on the internet. What is important, in our case, that service systemd unit file contains a `docker run` command with parameters and image name, that need to be downloaded and executed. We keep the service systemd unit file in same repository as the service code.

The image name usually is defined as `repository/image_name:tag` string. **Tag** is the most important thing in our solution. As I explained above, our CI server automatically builds a new Docker image on every push to service GitHub repository. CI job also tags the newly created image with 2 tags:
1. `branch` tag — taken from GitHub branch, that triggered the build (`master`, `develop`, `feature-*` braches in our case)
2. `build_num-branch` tag — where we add a running build number prefix, just before branch name
As a result, in DockerHub, we have images for the latest build in any branch and also for every image we can identify build job number and the branch it was created from.

As, I said before, we keep service systemd unit file in the same repository as code, and this file **does not** contain an image tag, only repository and image name. See example bellow:

```
ExecStart=/usr/bin/docker run —name myservice -p 3000:3000 myrepo/myservice
```

Our CI service build job generates a new service systemd unit file for every successful build, replacing above service invocation command with one, that also contain a new tag, using `build_num-branch` pattern (`develop` branch in our example). We are using two simple utilities for this job: `cat` and `sed`, but it’s possible to use some more advanced templating engine.

```
ExecStart=/usr/bin/docker run — name myservice -p 3000:3000 myrepo/myservice:58-develop
```

And as a last step, CI build job “deploys” this new unit file to the system configuration Git repository.

```
git commit -am “Updating myservice tag to ‘58-develop’” myservice.service
git push origin develop
```

Another CI job, that monitors changes in the system configuration repository will trigger a build and will create a new Docker image that captures updated system configuration.

Now, all you need to do, is to execute this Docker image on Docker cluster. Something, like this:

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

and `deploy.sh` is a shell script, that for every service checks if it needs to be updated, created or deleted and executes the corresponding **fleetctl** command.

The last remaining step is: *how do you run this “system configuration” container?

Currently, in our environment we are doing this manually (from SSH shell) for development clusters and use systemd timers for CoreOS clusters on AWS. Systemd timer allows us to define a cron like job at CoreOS cluster level.

We also have plans to define a WebHook endpoint that will allow us to trigger deployment/update, based on WebHook event from CI service.

Hope, that some of you will find this post helpful.
