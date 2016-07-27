+++
date = "2016-04-16T20:00:00+02:00"
draft = false
title = "Pumba - Chaos Testing for Docker"
tags = ["Docker", "testing", "chaos testing", "resilience"]
categories = ["Development"]
+++

**Update (27-07-27):** Updated post to latest `v0.2.0` Pumba version change.

## Introduction

The best defense against unexpected failures is to build resilient services. Testing for resiliency enables the teams to learn where their apps fail before the customer does. By intentionally causing failures as part of resiliency testing, you can enforce your policy for building resilient systems.
Resilience of the system can be defined as its ability to continue functioning even if some components of the system are failing - [ephemerality](https://en.wikipedia.org/wiki/Ephemerality). Growing popularity of distributed and microservice architecture makes resilience testing critical for applications that now require 24x7x365 operation.
Resilience testing is an approach where you intentionally inject different types of failures at the infrastructure level (VM, network, containers, and processes) and let the system try to recover from these unexpected failures that can happen in production. Simulating realistic failures at any time is the best way to enforce highly available and resilient systems.

## What is Pumba?

![Pumba](/img/pumba_docker.png)

First of all, [Pumba](https://en.wikipedia.org/wiki/Timon_and_Pumbaa) (or Pumbaa) is a supporting character from Disney's animated film *The Lion King*. In Swahili, *pumbaa* means "to be foolish, silly, weak-minded, careless, negligent". This reflects the unexpected behavior of the application.

Pumba is inspired by highly popular [Netfix Chaos Monkey](https://github.com/Netflix/SimianArmy/wiki/Chaos-Monkey) resilience testing tool for AWS cloud. Pumba takes a similar approach but applies it at the container level. It connects to the Docker daemon running on some machine (local or remote) and brings a level of chaos to it: "randomly" killing, stopping, and removing running containers.

If your system is designed to be resilient, it should be able to recover from such failures. "Failed" services should be restarted and lost connections should be recovered. This is not as trivial as it sounds. You need to design your services differently. Be aware that a service can fail (for whatever reason) or service it depends on can disappear at any point of time (but can reappear later). Expect the unexpected!

## Why run Pumba?

Failures happen and they inevitably happen when least desired. If your application cannot recover from system failures, you are going to face angry customers and maybe even loose them. If you want to be sure that your system is able to recover from unexpected failures, it would be better to take charge of them and inject failures yourself instead of waiting till they happen. This is not a one time effort. In age of Continuous Delivery, you need to be sure that every change to any one of system services, does not compromise system availability. That's why you should practice **continuous resilience testing**.
With Docker gaining popularity as people are deploying and running clusters of containers in production. Using a container orchestration network (e.g. Kubernetes, Swarm, CoreOS fleet), it's possible to restart a "failed" container automatically. How can you be sure that restarted services and other system services can properly recover from failures? If you are not using container orchestration frameworks, life is even harder: you will need to handle container restarts by yourself.

This is where Pumba shines. You can run it on every Docker host, in your cluster, and Pumba will "randomly" stop running containers - matching specified name/s or name patterns. You can even specify the *signal* that will be sent to "kill" the container.

## What Pumba can do?

Pumba can create different failures for your running Docker containers. Pumba can kill, stop or remove running containers. It can also pause all processes withing running container for specified period of time.
Pumba can also do network emulation, simulating different network failures, like: delay, packet loss/corruption/reorder, bandwidth limits and more.
*Disclaimer:* `netem` command is under development and only `delay` command is supported in Pumba `v0.2.0`.

You can pass list of containers to Pumba or just write a regular expression to select matching containers. If you will not specify containers, Pumba will try to disturb all running containers. Use `--random` option, to randomly select only one target container from provided list.

## How to run Pumba?

There are two ways to run Pumba.

First, you can download Pumba application (single binary file) for your OS from project [release page](https://github.com/gaia-adm/pumba/releases) and run `pumba help` to see list of supported commands and options.

```
$ pumba help

Pumba version v0.2.0
NAME:
   Pumba - Pumba is a resilience testing tool, that helps applications tolerate random Docker container failures: process, network and performance.

USAGE:
   pumba [global options] command [command options] containers (name, list of names, RE2 regex)

VERSION:
   v0.2.0

COMMANDS:
     kill     kill specified containers
     netem    emulate the properties of wide area networks
     pause    pause all processes
     stop     stop containers
     rm       remove containers
     help, h  Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --host value, -H value      daemon socket to connect to (default: "unix:///var/run/docker.sock") [$DOCKER_HOST]
   --tls                       use TLS; implied by --tlsverify
   --tlsverify                 use TLS and verify the remote [$DOCKER_TLS_VERIFY]
   --tlscacert value           trust certs signed only by this CA (default: "/etc/ssl/docker/ca.pem")
   --tlscert value             client certificate for TLS authentication (default: "/etc/ssl/docker/cert.pem")
   --tlskey value              client key for TLS authentication (default: "/etc/ssl/docker/key.pem")
   --debug                     enable debug mode with verbose logging
   --json                      produce log in JSON format: Logstash and Splunk friendly
   --slackhook value           web hook url; send Pumba log events to Slack
   --slackchannel value        Slack channel (default #pumba) (default: "#pumba")
   --interval value, -i value  recurrent interval for chaos command; use with optional unit suffix: 'ms/s/m/h'
   --random, -r                randomly select single matching container from list of target containers
   --dry                       dry runl does not create chaos, only logs planned chaos commands
   --help, -h                  show help
   --version, -v               print the version
```

### Kill Container command

```
$ pumba kill -h

NAME:
   pumba kill - kill specified containers

USAGE:
   pumba kill [command options] containers (name, list of names, RE2 regex)

DESCRIPTION:
   send termination signal to the main process inside target container(s)

OPTIONS:
   --signal value, -s value  termination signal, that will be sent by Pumba to the main process inside target container(s) (default: "SIGKILL")
```

### Pause Container command

```
$ pumba pause -h

NAME:
   pumba pause - pause all processes

USAGE:
   pumba pause [command options] containers (name, list of names, RE2 regex)

DESCRIPTION:
   pause all running processes within target containers

OPTIONS:
   --duration value, -d value  pause duration: should be smaller than recurrent interval; use with optional unit suffix: 'ms/s/m/h'
```

### Stop Container command

```
$ pumba stop -h
NAME:
   pumba stop - stop containers

USAGE:
   pumba stop [command options] containers (name, list of names, RE2 regex)

DESCRIPTION:
   stop the main process inside target containers, sending  SIGTERM, and then SIGKILL after a grace period

OPTIONS:
   --time value, -t value  seconds to wait for stop before killing container (default 10) (default: 10)
```

### Remove (rm) Container command

```
$ pumba rm -h

NAME:
   pumba rm - remove containers

USAGE:
   pumba rm [command options] containers (name, list of names, RE2 regex)

DESCRIPTION:
   remove target containers, with links and voluems

OPTIONS:
   --force, -f    force the removal of a running container (with SIGKILL)
   --links, -l    remove container links
   --volumes, -v  remove volumes associated with the container
```

### Network Emulation (netem) command

```
$ pumba netem -h

NAME:
   Pumba netem - delay, loss, duplicate and re-order (run 'netem') packets, to emulate different network problems

USAGE:
   Pumba netem command [command options] [arguments...]

COMMANDS:
     delay      dealy egress traffic
     loss
     duplicate
     corrupt

OPTIONS:
   --duration value, -d value   network emulation duration; should be smaller than recurrent interval; use with optional unit suffix: 'ms/s/m/h'
   --interface value, -i value  network interface to apply delay on (default: "eth0")
   --target value, -t value     target IP filter; netem will impact only on traffic to target IP
   --help, -h                   show help

NAME:
   Pumba netem - delay, loss, duplicate and re-order (run 'netem') packets, to emulate different network problems

USAGE:
   Pumba netem command [command options] [arguments...]

COMMANDS:
     delay      dealy egress traffic
     loss       TODO: planned to implement ...
     duplicate  TODO: planned to implement ...
     corrupt    TODO: planned to implement ...

OPTIONS:
   --duration value, -d value   network emulation duration; should be smaller than recurrent interval; use with optional unit suffix: 'ms/s/m/h'
   --interface value, -i value  network interface to apply delay on (default: "eth0")
   --target value, -t value     target IP filter; netem will impact only on traffic to target IP
   --help, -h                   show help
```

#### Network Emulation Delay sub-command

```
$ pumba netem delay -h

NAME:
   Pumba netem delay - dealy egress traffic

USAGE:
   Pumba netem delay [command options] containers (name, list of names, RE2 regex)

DESCRIPTION:
   dealy egress traffic for specified containers; networks show variability so it is possible to add random variation; delay variation isn't purely random, so to emulate that there is a correlation

OPTIONS:
   --amount value, -a value       delay amount; in milliseconds (default: 100)
   --variation value, -v value    random delay variation; in milliseconds; example: 100ms ± 10ms (default: 10)
   --correlation value, -c value  delay correlation; in percents (default: 20)
```

#### Examples

```
# stop random container once in a 10 minutes
$ ./pumba --random --interval 10m kill --signal SIGSTOP
```

```
# every 15 minutes kill `mysql` container and every hour remove containers starting with "hp"
$ ./pumba --interval 15m kill --signal SIGTERM mysql &
$ ./pumba --interval 1h rm re2:^hp &
```

```
# every 30 seconds kill "worker1" and "worker2" containers and every 3 minutes stop "queue" container
$ ./pumba --interval 30s kill --signal SIGKILL worker1 worker2 &
$ ./pumba --interval 3m stop queue &
```

```
# Once in 5 minutes, Pumba will delay for 2 seconds (2000ms) egress traffic for some (randomly chosen) container,
# named `result...` (matching `^result` regexp) on `eth2` network interface.
# Pumba will restore normal connectivity after 2 minutes. Print debug trace to STDOUT too.
$ ./pumba --debug --interval 5m --random netem --duration 2m --interface eth2 delay --amount 2000 re2:^result
```

### Running Pumba in Docker Container

The second approach to run it in a Docker container.

In order to give Pumba access to Docker daemon on host machine, you will need to mount `var/run/docker.sock` unix socket.

```
# run latest stable Pumba docker image (from master repository)
$ docker run -d -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba:master pumba kill --interval 10s --signal SIGTERM ^hp
```

Pumba will not kill its own container.

Note: For Mac OSX - before you run Pumba, you may want to do the following after downloading the [pumba_darwin_amd64](https://github.com/gaia-adm/pumba/releases) binary:
```
chmod +x pumba_darwin_amd64
mv pumba_darwin_amd64 /usr/local/bin/pumba
pumba
```

### Next

The Pumba project is available for you to try out. We will gladly accept ideas, pull requests, issues, and contributions to the project.

[Pumba GitHub Repository](https://github.com/gaia-adm/pumba)
