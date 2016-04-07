+++
date = "2016-04-06T20:00:00+02:00"
draft = false
title = "Pumba - Chaos Testing for Docker"
tags = ["Docker", "testing", "chaos testing", "resilience"]
categories = ["Development"]
+++

## Introduction

The best defense against major unexpected failures is to fail often. By causing failures, you can force your services to be built in a way that is more resilient.
Resilience of a system can be defined as its ability to continue functioning even if some components of the system fail. Growing popularity of distributed and microservice architecture makes resilience testing an important testing practice, that none should skip.
Resilience Testing is a testing approach, where you inject different types of failures at infrastructure level (VM, network, containers and  processes) and let your system try to recover from injected failures. This way you simulate real failures that might happend in production environment. Practicing resilience testing, is the best way to enforce hihgly avaiable and resilient architecture.

## What is Pumba?

![Pumba](/img/pumba.png)

First of all, [Pumba](https://en.wikipedia.org/wiki/Timon_and_Pumbaa) (or Pumbaa) is a supporting character from Disney's animated film *The Lion King*. In Swahili, *pumbaa* means "to be foolish, silly, weakminded, careless, negligent". And this actually reflects the desired behavior of this application.

Pumba is inspired by [Netfix Chaos Monkey](https://github.com/Netflix/SimianArmy/wiki/Chaos-Monkey) resilience testing tool for AWS cloud. Pumba takes the same approach down to the contaioner level. It connects to the Docker daemon running on some machine (local or remote) and brings some level of chaos to it, by "randomly" killing, stopping and removing running containers.

If you your system is designed to be resilient, it should be able to recover from such failures. "Failed" services should be restarted and lost connections should be recovered. This is not as trivial as it sounds. You need to design your service differently, be ware that service can fail (for whatever reason) or service it depends on can disappear at any moment (but can reappear later on).

## Why to run Pumba?

Failures happen, and they inevitably happen when least desired. If your application cannot recover from system failures, you are going to face angry customers and maybe even loose them. If you like to be sure, that your system is able to recover from unexpected failures, it would be better to take charge on them and inject them by yourself instead of waiting till they happen. And this is not a one time effort, in age of Continious Delivery, you need to be sure that every change, done to one of ystem services, does not compromise avaiability and resilience. That's why you should practice resilience testing continiously.
With Docker gaining popularity, people use it more and more in production environment, running clusters of containers. Using some kind of container orchestration network (Kubernetes, Swarm, CoreOS fleet), it's possible to restart "failed" container automatically, but how you can be sure that restarted services and other system services can properly recover from such failure?
Here come Pumba. You run it on every Docker host in your cluster and it, once in a whilem, will randomly stop running containers, matching specified name/s or name pattern. You can even specify *signal*, that will be sent to "kill" the container.

## How to run Pumba?

There are two ways to run Pumba.
First, you can download Pumba application for your OS from project [release page](https://github.com/gaia-adm/pumba/releases) and run `pumba -h` to see list of supported options.

```
NAME:
   pumba - Pumba is a resiliency tool that helps applications tolerate random Docker container failures.

USAGE:
   pumba [options...]

VERSION:
   0.1.3

OPTIONS:
   --host, -H "unix:///var/run/docker.sock"  daemon socket to connect to [$DOCKER_HOST]
   --tls                                     use TLS; implied by --tlsverify
   --tlsverify                               use TLS and verify the remote [$DOCKER_TLS_VERIFY]
   --tlscacert "/etc/ssl/docker/ca.pem"      trust certs signed only by this CA
   --tlscert "/etc/ssl/docker/cert.pem"      client certificate for TLS authentication
   --tlskey "/etc/ssl/docker/key.pem"        client key for TLS authentication
   --debug                                   enable debug mode with  verbose logging
   --chaos [--chaos option --chaos option]   chaos command: `container(s,)/re2:regex|interval(s/m/h postfix)|STOP/KILL(:SIGNAL)/RM`
   --help, -h                                show help
   --version, -v                             print the version
```

The command is pretty simple. If you already have Docker client installed and configured on your machine (i.e. `$DOCKER_HOST` environment variable is defined), you will need to specify only `chaos` command options.

### "chaos" command

The `chaos` command is a 3-tuple (or triple), spearated by `|` (vertical bar) character, that specifies container(s), recurrency interval and the "kill" command to run. It's possible to include multiple `chaos` triples for same `pumba` command.

**3-tuple structure**

1. First argument can be:
  - *name* - container name
  - *names* - comma separated list of container names
  - *empty* - empty string; ALL containers
  - *re2:regex* - [RE2](https://github.com/google/re2/wiki/Syntax) regular expression; all matching containers will be "killed". Use `re2:` prefix to specify regular expression.
2. Recurrency interval - `pumba` will run specified command recurrently, based on interval definition
  - An interval is a possibly signed sequence of decimal numbers, each with optional fraction and a unit suffix, such as "300ms", "-1.5h" or "2h45m". Valid time units are "ns", "us" (or "µs"), "ms", "s", "m", "h".
3. "Kill" command
  - `STOP` - stop running container(s)
  - `KILL(:SIGNAL)` - kill running container, with specified (optional) **signal**: `SIGTERM`, `SIGKILL`, `SIGSTOP` and others. `SIGKILL` is the default signal, that will be sent if no signal is specified.
  - `RM` - force remove running container(s)

#### Examples

```
# stop ALL containers once in a 10 minutes
$ ./pumba --chaos "|10m|STOP"
```

```
# every 15 minutes kill `mysql` container and every hour remove containers starting with "hp"
$ ./pumba --chaos "mysql|15m|KILL:SIGTERM" --chaos "re2:^hp|1h|RM"
```

```
# every 30 seconds kill "worker1" and "worker2" containers and every 3 minutes stop "queue" container
$ ./pumba --chaos "worker1,worker2|30s|KILL:SIGKILL" --chaos "queue|3m|STOP"
```

### Running Pumba in Docker Container

The second approach to run Pumba, is to run it with Docker container.
In order to give Pumba access to Docker daemon on host machine, you will need to mount `var/run/docker.sock` unix socket.

```
# run latest stable Pumba docker image (from master repository)
$ docker run -d gaiaadm/pumba:master --chaos "mysql|10m|STOP"
```

Pumba will not kill its container, no matter what. If you will try to run multiple Pumba containers on same host, only last one will run and will stop all previous Pumba containers.
