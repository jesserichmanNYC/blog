+++
date = "2016-12-18T14:00:00+02:00"
draft = false
title = "Deploy Docker Compose (v3) to Swarm (mode) Cluster"
tags = ["docker", "swarm", "docker-compose", "compose", "devops", "cluster"]
categories = ["DevOps"]
+++

> **Disclaimer:** all code snippets bellow are working only with **Docker 1.13+**

# TL;DR

**Docker 1.13** simplifies deployment of composed application to a **swarm** (mode) cluster. And you can do it without creating a new `dab` (*Distribution Application Bundle*) file, but just using familiar and well-known `docker-compose.yml` syntax (with some additions) and `--compose-file` option.

![Compose to Swarm](/img/compose_swarm.png)


# Swarm cluster

Docker Engine 1.12 introduced a new **swarm mode** for natively managing a cluster of Docker Engines called a **swarm**. Docker **swarm mode** implements [Raft Consensus Algorithm](https://docs.docker.com/engine/swarm/raft/) and does not require using external key value store anymore, such as [Consul](https://www.consul.io/) or [etcd](https://github.com/coreos/etcd).

If you want to run a **swarm** cluster on a developer's machine, there are several options.

The first option and most widely known, is to use a `docker-machine` tool with some virtual driver (Virtualbox, Parallels or other).

But, in this post I will use another approach: using [docker-in-docker](https://hub.docker.com/_/docker/) Docker image with Docker for Mac, see more details in my [Docker Swarm cluster with docker-in-docker on MacOS](../swarm_dind) post.

## Docker Registry mirror

When you deploy a new service on local swarm cluster, I recommend to setup local Docker registry mirror and run all swarm nodes with `--registry-mirror` option, pointing to local Docker registry. By running a local Docker registry mirror, you can keep most of the redundant image fetch traffic on your local network and speedup service deployment.

### Docker Swarm cluster bootstrap script

I've prepared a shell script to bootstrap 4 nodes swarm cluster with Docker registry mirror and very nice [swarm visualizer](https://github.com/ManoMarks/docker-swarm-visualizer) application.

The script initialize docker engine as a **swarm master**, then starts 3 new docker-in-docker containers and join them to the **swarm** cluster as worker nodes. All worker nodes run with `--registry-mirror` option.

{{< gist alexei-led a4d31ee446a0fbcab845b93fe4a9b09d "create_swarm_cluster.sh" >}}

## Deploy multi-container application - the "old" way

The Docker `compose` is a tool (and deployment specification format) for defining and running composed multi-container Docker applications. Before Docker 1.12, you could use `docker-compose` tool to deploy such applications to a **swarm** cluster. With 1.12 release, it's not possible anymore: `docker-compose` can deploy your application only on single Docker host.

In order to deploy it to a **swarm** cluster, you need to create a special deployment specification file (also knows as *Distribution Application Bundle*) in `dab` format (see more [here](https://github.com/docker/docker/blob/master/experimental/docker-stacks-and-bundles.md)).

The way to create this file, is to run the `docker-compose bundle` command. The output of this command is a JSON file, that describes  multi-container composed application with Docker images referenced by `@sha256` instead of tags. Currently `dab` file format does not support multiple settings from `docker-compose.yml` and does not allow to use supported options from `docker service create` command.

Such a pity story: the `dab` bundle format looks promising, but currently is totally useless (at least in Docker 1.12).

## Deploy multi-container application - the "new" way

With Docker 1.13, the "new" way to deploy a multi-container composed application is to use `docker-compose.yml` again (*hurrah!*). Kudos to Docker team!

***Note**: And you do not need the `docker-compose` tool, only `yaml` file in **docker-compose** format (`version: "3"`)

```
$ docker deploy --compose-file docker-compose.yml myapp
```

## Docker compose v3 (`version: "3"`)

*So, what's new in docker compose version 3?*

First, I suggest you take a deeper look at [docker-compose schema](https://github.com/aanand/compose-file/blob/master/schema/data/config_schema_v3.0.json). It is an extension of well-known `docker-compose` format.

**Note:** `docker-compose` tool (`ver. 1.9.0`) does not support `docker-compose.yaml version: "3"` yet.

The most visible change is around **swarm** ***service deployment.
Now you can specify all options supported by `docker service create/update` commands:

- number of service replicas (or global service)
- service labels
- hard and soft limits for service (container) CPU and memory
- service restart policy
- service rolling update policy
- deployment placement constraints [link](https://github.com/docker/docker/blob/master/docs/reference/commandline/service_create.md#specify-service-constraints---constraint)

### Docker compose v3 example

I've created a "new" compose file (v3) for classic "Cats vs. Dogs" example. This example application contains 5 services with following deployment configurations:

1. `voting-app` - a Python webapp which lets you vote between two options; requires `redis`
2. `redis` - Redis queue which collects new votes; deployed on `swarm manager` node
3. `worker` .NET worker which consumes votes and stores them in `db`;
  - **# of replicas:** 2 replicas
  - **hard limit:** max 25% CPU and 512MB memory
  - **soft limit:** max 25% CPU and 256MB memory
  - **placement:** on `swarm worker` nodes only
  - **restart policy:** restart on-failure, with 5 seconds delay, up to 3 attempts
  - **update policy:** one by one, with 10 seconds delay and 0.3 failure rate to tolerate during the update
4. `db` - Postgres database backed by a Docker volume; deployed on `swarm manager` node
5. `result-app` Node.js webapp which shows the results of the voting in real time; 2 replicas, deployed on `swarm worker` nodes

Run the `docker deploy --compose-file docker-compose.yml` command to deploy my version of "Cats vs. Dogs" application on a swarm cluster.

{{< gist alexei-led a4d31ee446a0fbcab845b93fe4a9b09d "docker-compose.yml" >}}

----------

Hope you find this post useful. I look forward to your comments and any questions you have.

----------

*The is a **working draft** version.* 
*The final post version is published at [Codefresh Blog](https://codefresh.io/blog/deploy-docker-compose-v3-swarm-mode-cluster/) on December 25, 2016*