+++
date = "2017-01-02T18:00:00+02:00"
draft = false
title = "Everyday hacks for Docker"
tags = ["docker", "tutorial", "devops", "hacks"]
categories = ["DevOps"]
extlink = "https://codefresh.io/blog/everyday-hacks-docker/"
+++


In this post, I've decided to share with you some useful commands and tools, I'm frequently using, working with amazing Docker technology.
There is no particular order or "coolness level" for every "hack". I will try to present the use case and how does specific command or tool help me with my work.

![Docker Hacks](/img/docker_animals.png)

## Cleaning up

Working with Docker for some time, you start to accumulate development junk: unused volumes, networks, exited containers and unused images.

### One command to "rule them all"
```
$ docker system  prune
```

`prune` is a very useful command (works also for `volume` and `network` sub-commands), but it's only available for Docker 1.13. So, if you are using older Docker versions, then following commands can help you to replace the `prune` command.

### Remove dangling volumes

`dangling` volumes - volumes not in use by any container. To remove them, combine two commands: first, list volume IDs for `dangling` volumes and then remove them.

```
$ docker volume rm $(docker volume ls -q -f "dangling=true")
```

### Remove exited containers

The same principle works here too: first, list containers (only IDs) you want to remove (with filter) and then remove them (consider `rm -f` to force remove).

```
$ docker rm $(docker ps -q -f "status=exited")
```

### Remove dangling images

`dangling` images are Docker untagged images, that are the leaves of the images tree (not intermediary layers).

```
docker rmi $(docker images -q -f "dangling=true")
```

### Autoremove interactive containers

When you run a new interactive container and want to avoid typing `rm` command after it exits, use `--rm` option. Then when you exit from created container, it will be automatically destroyed.
```
$ docker run -it --rm alpine sh
```

## Inspect Docker resources

[jq](https://stedolan.github.io/jq/) - `jq` is a lightweight and flexible command-line `JSON` processor. It is like `sed` for JSON data - you can use it to slice and filter and map and transform structured data with the same ease that `sed`, `awk`, `grep` and friends let you play with text.

[`docker info`](https://docs.docker.com/engine/reference/commandline/info/) and [`docker inspect`](https://docs.docker.com/engine/reference/commandline/inspect/) commands can produce output in `JSON` format. Combine these commands with `jq` processor.

### Pretty JSON and jq processing
```
# show whole Docker info
$ docker info --format "{{json .}}" | jq .

# show Plugins only
$ docker info --format "{{json .Plugins}}" | jq .

# list IP addresses for all containers connected to 'bridge' network
$ docker network inspect bridge -f '{{json .Containers}}' | jq '.[] | {cont: .Name, ip: .IPv4Address}'
```

## Watching containers lifecycle

Sometimes you want to see containers being activated and exited, when you run some docker commands or try different restart policies.
[`watch`](http://man7.org/linux/man-pages/man1/watch.1.html) command combined with [`docker ps`](https://docs.docker.com/engine/reference/commandline/ps/) can be pretty useful here. 
The `docker stats` command, even with `--format` option is not useful for this use case since it does not allow you to see same info as you can see with `docker ps` command.

### Display a table with 'ID Image Status' for active containers and refresh it every 2 seconds
```
$ watch -n 2 'docker ps --format "table {{.ID}}\t {{.Image}}\t {{.Status}}"'
```

## Enter into host/container Namespace

Sometimes you want to connect to the Docker host. The `ssh` command is the default option, but this option can be either not available, due to security settings, firewall rules or not documented (try to find how to `ssh` into Docker for Mac VM).

[`nsenter`](https://github.com/jpetazzo/nsenter), by Jérôme Petazzoni, is a small and very useful tool for above cases. `nsenter` allows to `enter` into `n`ame`s`paces. I like to use minimalistic (`580 kB`) [walkerlee/nsenter](https://hub.docker.com/r/walkerlee/nsenter/) Docker image.

### Enter into Docker host
Use `--pid=host` to enter into Docker host namespaces

```
# get a shell into Docker host
$ docker run --rm -it --privileged --pid=host walkerlee/nsenter -t 1 -m -u -i -n sh
```

### Enter into ANY container
It's also possible to enter into any container with `nsenter` and `--pid=container:[id OR name]`. But in most cases, it's better to use standard [`docker exec`](https://docs.docker.com/engine/reference/commandline/exec/) command. The main difference is that `nsenter` doesn't enter the *cgroups*, and therefore evades resource limitations (can be useful for debugging).

```
# get a shell into 'redis' container namespace
$ docker run --rm -it --privileged --pid=container:redis walkerlee/nsenter -t 1 -m -u -i -n sh
```

## Heredoc Docker container

Suppose you want to get some tool as a Docker image, but you do not want to search for a suitable image or to create a new `Dockerfile` (no need to keep it for future use, for example). Sometimes storing a Docker image definition in a file looks like an overkill - you need to decide how do you edit, store and share this Dockerfile. Sometimes it's better just to have a single line command, that you can copy, share, embed into a shell script or create special command `alias`.
So, when you want to create a new ad-hoc container with a single command, try a [Heredoc](http://www.tldp.org/LDP/abs/html/here-docs.html) approach.


### Create Alpine based container with 'htop' tool
```
$ docker build -t htop - << EOF
FROM alpine
RUN apk --no-cache add htop
EOF
```

## Docker command completion

Docker CLI syntax is very rich and constantly growing: adding new commands and new options. It's hard to remember every possible command and option, so having a nice command completion for a terminal is a **must have**.

Command completion is a kind of terminal plugin, that lets you auto-complete or auto-suggest what to type in next by hitting *tab* key. Docker command completion works both for commands and options. Docker team prepared command completion for `docker`, `docker-machine` and `docker-compose` commands, both for `Bash` and `Zsh`.

If you are using Mac and [Homebrew](http://brew.sh), then installing Docker commands completion is pretty straight forward.

```
# Tap homebrew/completion to gain access to these
$ brew tap homebrew/completions

# Install completions for docker suite
$ brew install docker-completion
$ brew install docker-compose-completion
$ brew install docker-machine-completion
```

For non-Mac install read official Docker documentation: [docker engine](https://github.com/docker/docker/tree/master/contrib/completion), [docker-compose](https://docs.docker.com/compose/completion/) and [docker-machine](https://docs.docker.com/machine/completion/)

## Start containers automatically

When you are running process in Docker container, it may fail due to multiple reasons. Sometimes to fix this failure it's enough to rerun the failed container. If you are using Docker orchestration engine, like Swarm or Kubernetes, the failed service will be restarted automatically.
But if you are using plain Docker and want to restart container, based on *exit code* of container's main process or always (regardless the *exit code*), Docker 1.12 introduced a very helpful option for `docker run` command: [restart](https://docs.docker.com/engine/reference/run/#restart-policies-restart#restart-policies---restart).

### Restart always
Restart the `redis` container with a restart policy of **always** so that if the container exits, Docker will restart it.
```
$ docker run --restart=always redis
```

### Restart container on failure
Restart the `redis` container with a restart policy of **on-failure** and a maximum restart count of `10`.
```
$ docker run --restart=on-failure:10 redis
```

## Network tricks

There are cases when you want to create a new container and connect it to already existing network stack. It can be Docker host network or another container's network. This can be pretty useful for debugging and audition network issues.
The `docker run --network/net` option support this use case.

### Use Docker host network stack
```
$ docker run --net=host ...
```
The new container will attach to same network interfaces as the Docker host.

### Use another container's network stack
```
$ docker run --net=container:<name|id> ...
```
The new container will attach to same network interfaces as another container. The target container can be specified with `id` or `name`.

### Attachable overlay network

Using docker engine running in **swarm mode**, you can create a multi-host `overlay` network on a manager node. When you create a new *swarm service*, you can attach it to the previously created `overlay` network. 

Sometimes to inspect network configuration or debug network issues, you want to attach a new Docker container, filled with different network tools, to existing `overlay` network and do this with `docker run` command and not to create a new "debug service".

Docker 1.13 brings a new option to `docker network create` command: `attachable`. The `attachable` option enables manual container attachment.

```
# create an attachable overlay network
$ docker network create --driver overlay --attachable mynet
# create net-tools container and attach it to mynet overlay network
$ docker run -it --rm --net=mynet net-tools sh
```

---

*This is a **working draft** version.* 
*The final post version is published at [Codefresh Blog](https://codefresh.io/blog/everyday-hacks-docker/) on January 5, 2017.*