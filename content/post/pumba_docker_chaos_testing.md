+++
date = "2016-04-06T20:00:00+02:00"
draft = false
title = "Pumba - Chaos Testing for Docker"
tags = ["Docker", "testing", "chaos testing", "resilience"]
categories = ["Development"]
+++

## Introduction

The best defence against major unexpected failures is to fail often. By causing failures, you can force your services to be built in a way, that makes them more resilient.
Resilience of the system can be defined as its ability to continue functioning even if some components of the system are failing. Growing popularity of distributed and microservice architecture makes resilience testing an important testing practice, that none should skip.
Resilience Testing is a testing approach, where you inject different types of failures at infrastructure level (VM, network, containers and  processes) and let your system try to recover from the injected failures. This way you simulate real failures, that might happen in production environment. Practicing resilience testing, is the best way to enforce highly avaiable and resilient architecture.

## What is Pumba?

![Pumba](/img/pumba_docker.png)

First of all, [Pumba](https://en.wikipedia.org/wiki/Timon_and_Pumbaa) (or Pumbaa) is a supporting character from Disney's animated film *The Lion King*. In Swahili, *pumbaa* means "to be foolish, silly, weakminded, careless, negligent". And this actually reflects the desired behaviour of application, I've tried to build :)

Pumba is inspired by highly popular [Netfix Chaos Monkey](https://github.com/Netflix/SimianArmy/wiki/Chaos-Monkey) resilience testing tool for AWS cloud. Pumba takes similar approach, but applies it to container level. It connects to the Docker daemon running on some machine (local or remote) and brings some level of chaos to it: "randomly" killing, stopping and removing running containers.

If your system is designed to be resilient, it should be able to recover from such failures. "Failed" services should be restarted and lost connections should be recovered. This is not as trivial as it sounds. You need to design your services differently, be aware, that service can fail (for whatever reason) or service it depends on can disappear at any point of time (but can reappeared later on). Expect unexpected!

## Why to run Pumba?

Failures happen, and they inevitably happen when least desired. If your application cannot recover from system failures, you are going to face angry customers and maybe even loose them. If you want to be sure, that your system is able to recover from unexpected failures, it would be better to take charge on them and inject failures by yourself instead of waiting till they happen. And this is not a one time effort. In age of Continious Delivery, you need to be sure that every change, done to one of system services, does not compromise system avaiability and resilience. That's why you should practice **continuous resilience testing**.
With Docker gaining popularity, people use it more and more in production environment, running clusters of containers. Using some kind of container orchestration network (Kubernetes, Swarm, CoreOS fleet), it's possible to restart "failed" container automatically, but how you can be sure that restarted services and other system services can properly recover from different system failures? And if you are not using container orchestration frameworks, life is even harder: you will need to handle container restarts by yourself.

Here comes Pumba. You run it on every Docker host, in your cluster and it, once in a while, will "randomly" stop running containers, matching specified name/s or name patterns. You can even specify the *signal*, that will be sent to "kill" the container.

## How to run Pumba?

There are two ways to run Pumba.

First, you can download Pumba application (single binary file) for your OS from project [release page](https://github.com/gaia-adm/pumba/releases) and run `pumba help` and `pumba run --help` to see list of supported options.

```
$ pumba help

NAME:
   Pumba - Pumba is a resiliency tool that helps applications tolerate random Docker container failures.

USAGE:
   pumba [global options] command [command options] [arguments...]

VERSION:
   0.1.4

COMMANDS:
    run	Pumba starts making chaos: periodically (and randomly) kills/stops/remove specified containers

GLOBAL OPTIONS:
   --host, -H "unix:///var/run/docker.sock"  daemon socket to connect to [$DOCKER_HOST]
   --tls                                     use TLS; implied by --tlsverify
   --tlsverify                               use TLS and verify the remote [$DOCKER_TLS_VERIFY]
   --tlscacert "/etc/ssl/docker/ca.pem"      trust certs signed only by this CA
   --tlscert "/etc/ssl/docker/cert.pem"      client certificate for TLS authentication
   --tlskey "/etc/ssl/docker/key.pem"        client key for TLS authentication
   --debug                                   enable debug mode with verbose logging
   --help, -h                                show help
   --version, -v                             print the version
```

```
$ pumba run --help

NAME:
   pumba run - Pumba starts making chaos: periodically (and randomly) kills/stops/remove specified containers

USAGE:
   pumba run [command options] [arguments...]

OPTIONS:
   --chaos, -c [--chaos option --chaos option]    chaos command: `container(s,)/re2:regex|interval(s/m/h postfix)|STOP/KILL(:SIGNAL)/RM`
   --random, -r                                   Random mode: randomly select single matching container to 'kill'
```

The `run` command is pretty simple. If you already have Docker client installed and configured on your machine (i.e. `$DOCKER_HOST` environment variable is defined), you will need only to execute `run` with `--chaos` options (and optionally `--random`). And that's all.

### The "run" command

The `run` command follows by one or more `--chaos` options, each of them is a 3-tuple (or triple), separated by `|` (vertical bar) character, that specifies container(s), recurrence interval and the "kill" command to run.

#### `--chaos, -c` option(s): 3-tuple structure

1. First argument can be:
  - *name* - container name
  - *names* - comma separated list of container names
  - *empty* - empty string; means ALL containers
  - *re2:regex* - [RE2](https://github.com/google/re2/wiki/Syntax) regular expression; all matching containers will be "killed". Use `re2:` prefix to specify regular expression.
2. Recurrence interval - `pumba` will run specified command recurrently, based on interval definition
  - An interval is a possibly signed sequence of decimal numbers, each with optional fraction and a unit suffix, such as "300ms", "-1.5h" or "2h45m". Valid time units are "ns", "us" (or "µs"), "ms", "s", "m", "h".
3. "Kill" command
  - `STOP` - stop running container(s)
  - `KILL(:SIGNAL)` - kill running container, with specified (optional) **signal**: `SIGTERM`, `SIGKILL`, `SIGSTOP` and others. `SIGKILL` is the default signal, that will be sent if no signal is specified.
  - `RM` - force remove running container(s)

#### `--random, -r` option

Use this option to randomly select **single** matching container, specified by `--chaos` option.

#### Examples

```
# stop random container once in a 10 minutes
$ ./pumba run --chaos "|10m|STOP" --random
```

```
# every 15 minutes kill `mysql` container and every hour remove containers starting with "hp"
$ ./pumba run -c "mysql|15m|KILL:SIGTERM" -c "re2:^hp|1h|RM"
```

```
# every 30 seconds kill "worker1" and "worker2" containers and every 3 minutes stop "queue" container
$ ./pumba run --chaos "worker1,worker2|30s|KILL:SIGKILL" --chaos "queue|3m|STOP"
```

### Running Pumba in Docker Container

The second approach to run Pumba, is to run it with Docker container.
In order to give Pumba access to Docker daemon on host machine, you will need to mount `var/run/docker.sock` unix socket.

```
# run latest stable Pumba docker image (from master repository)
$ docker run -d gaiaadm/pumba:master run --chaos "|10m|STOP" --random
```

Pumba will not kill its own container, no matter what. If you will try to run multiple Pumba containers on same host, only last one will run and will stop all previous Pumba containers.

### Next

I've just created the Pumba project and will gladly accept ideas, Pull Requests, issues and contributions to the project.
[Pumba GitHub Repository](https://github.com/gaia-adm/pumba)
