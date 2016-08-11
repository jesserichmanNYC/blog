+++
date = "2016-08-01T20:00:00+02:00"
draft = false
title = "Network emulation for Docker containers"
tags = ["Docker", "testing", "chaos testing", "netem", "network"]
categories = ["Development"]
+++

## TL;DR

> [Pumba](https://github.com/gaia-adm/pumba) `netem delay` and `netem loss` commands can emulate network *delay* and *packet loss* between Docker containers, even on single host. Give it a try!

## Introduction

Microservice architecture has been adopted by software teams as a way to deliver business value faster. Container technology enables delivery of microservices into any environment. Docker has accelerated this by providing an easy to use toolset for development teams to build, ship, and run distributed applications. These applications can be composed of hundreds of microservices packaged in Docker containers.

In a recent NGINX [survey](https://www.nginx.com/resources/library/app-dev-survey/) [Finding #7], the “biggest challenge holding back developers” is the trade-off between quality and speed. As Martin Fowler indicates, [testing strategies in microservices architecture](http://martinfowler.com/articles/microservice-testing) can be very complex. Creating a realistic and useful testing environment is an aspect of this complexity.

One challenge is **simulating network failures** to ensure **resiliency** of applications and services.

The network is a critical arterial system for ensuring reliability for any distributed application. Network conditions are different depending on where the application is accessed. Network behavior can greatly impact the overall application availability, stability, performance, and user experience (UX). It’s critical to simulate and understand these impacts before the user notices. Testing for these conditions requires conducting realistic network tests.

After Docker containers are deployed in a cluster, all communication between containers happen over the network. These containers run on a single host, different hosts, different networks, and in different datacenters.

> How can we test for the impact of network behavior on the application? What can we do to emulate different network properties between containers on a single host or among clusters on multiple hosts?

## Pumba with Network Emulation

[Pumba](https://github.com/gaia-adm/pumba) is a chaos testing tool for Docker containers, inspired by [Netflix Chaos Monkey](https://github.com/Netflix/SimianArmy/wiki/Chaos-Monkey). The main benefit is that it works with containers instead of VMs. Pumba can kill, stop, restart running Docker containers or pause processes within specified containers. We use it for resilience testing of our distributed applications. Resilience testing ensures reliability of the system. It allows the team to verify their application recovers correctly regardless of any event (expected or unexpected) without any loss of data or functionality. Pumba simulates these events for distributed and containerized applications.


### Pumba `netem`

We enhanced [Pumba](https://github.com/gaia-adm/pumba) with network emulation capabilities starting with *delay* and *packet loss*. Using `pumba netem` command we can apply *delay* or *packet loss* on any Docker container. Under the hood, **Pumba** uses Linux kernel traffic control ([tc](http://man7.org/linux/man-pages/man8/tc.8.html)) with [netem](http://man7.org/linux/man-pages/man8/tc-netem.8.html) queueing discipline. To work, we need to add [iproute2](https://wiki.linuxfoundation.org/networking/iproute2) to Docker images, that we want to test. Some base Docker images already include [iproute2](https://wiki.linuxfoundation.org/networking/iproute2) package.

Pumba `netem delay` and `netem loss` commands can emulate network *delay* and *packet loss* between Docker containers, even on a single host.

Linux has a built-in network emulation capabilities, starting from kernel 2.6.7 (released 14 years ago). Linux allows us to manipulate traffic control settings, using [tc](http://man7.org/linux/man-pages/man8/tc.8.html) tool, available in [iproute2](https://wiki.linuxfoundation.org/networking/iproute2); [netem](http://man7.org/linux/man-pages/man8/tc-netem.8.html) is an extension (*queueing discipline*) of the tc tool. It allows emulation of network properties — *delay*, *packet loss*, *packer reorder*, *duplication*, *corruption*, and *bandwidth rate*.

**Pumba** `netem` commands can help development teams simulate realistic network conditions as they build, ship, and run microservices in Docker containers.

**Pumba** with low level `netem` options, greatly simplifies its usage. We have made it easier to emulate different network properties for running Docker containers.

In the current release, **Pumba** modifies *egress* traffic only by adding *delay* or *packet loss* for specified container(s). Target containers can be specified by name (single name or as a space separated list) or via regular expression ([RE2](https://github.com/google/re2/wiki/Syntax)). **Pumba** modifies container network conditions for a specified duration. After a set time interval, **Pumba** restores normal network conditions. **Pumba** also restores the original connection with a graceful shutdown of the `pumba` process `Ctrl-C` or by stopping the **Pumba** container with `docker stop` command.
An option is available to apply an IP range filter to the network emulation. With this option, **Pumba** will modify outgoing traffic for specified IP and will leave other outgoing traffic unchanged. Using this option, we can change network properties for a specific inter-container connection(s) as well as specific Docker networks — each Docker network has its own IP range.

### Pumba delay: `netem delay`

To demonstrate, we’ll run two Docker containers: one is running a `ping` command and the other is **Pumba** Docker container, that adds 3 seconds network *delay* to the ping container for 1 minute. After 1 minute, **Pumba** container restores the network connection properties of the ping container as it exits gracefully.

{{< figure src="https://asciinema.org/a/82428.png" link="https://asciinema.org/a/82430?t=7" title="Pumba [netem delay] demo" >}}

```
# open two terminal windows: (1) and (2)

# terminal (1)
# create new 'tryme' Alpine container (with iproute2) and ping `www.example.com`
$ docker run -it --rm --name tryme alpine sh -c "apk add --update iproute2 && ping www.example.com"

# terminal (2)
# run pumba: add 3s delay to `tryme` container for 1m
$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
         pumba netem --interface eth0 --duration 1m delay --time 3000 tryme

# See `ping` delay increased by 3000ms for 1 minute
# You can stop Pumba earlier with `Ctrl-C`
```

### `netem delay` examples

This section contains more advanced network emulation examples for `delay` command.

```
# add 3 seconds delay for all outgoing packets on device `eth0` (default) of `mydb` Docker container for 5 minutes

$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
    pumba netem --duration 5m \
      delay --time 3000 \
      mydb
```

```
# add a delay of 3000ms ± 30ms, with the next random element depending 20% on the last one,
# for all outgoing packets on device `eth1` of all Docker container, with name start with `hp`
# for 10 minutes

$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
    pumba netem --duration 5m --interface eth1 \
      delay \
        --time 3000 \
        --jitter 30 \
        --correlation 20 \
      re2:^hp
```

```
# add a delay of 3000ms ± 40ms, where variation in delay is described by `normal` distribution,
# for all outgoing packets on device `eth0` of randomly chosen Docker container from the list
# for 10 minutes

$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
    pumba --random \
      netem --duration 5m \
        delay \
          --time 3000 \
          --jitter 40 \
          --distribution normal \
        container1 container2 container3
```

## Pumba packet loss: `netem loss`, `netem loss-state`, `netem loss-gemodel`

Lets start with *packet loss* demo. Here we will run three Docker containers. `iperf` **server** and **client** for sending data and Pumba Docker container, that will add packer loss on client container.
We are using **perform network throughput tests** tool [iperf](http://manpages.ubuntu.com/manpages/xenial/man1/iperf.1.html) to demonstrate *packet loss*.

{{< figure src="https://asciinema.org/a/82430.png" link="https://asciinema.org/a/82430" title="Pumba [netem loss] demo" >}}

```
# open three terminal windows

# terminal (1) iperf server
# server: `-s` run in server mode; `-u` use UDP;  `-i 1` report every second
$ docker run -it --rm --name tryme-srv alpine sh -c "apk add --update iperf && iperf -s -u -i 1"

# terminal (2) iperf client
# client: `-c` client connects to <server ip>; `-u` use UDP
$ docker run -it --rm --name tryme alpine sh -c "apk add --update iproute2 iperf && iperf -c 172.17.0.3 -u"

# terminal (3)
# run pumba: add 20% packet loss to `tryme` container for 1m
$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
         pumba netem --duration 1m loss --percent 20 tryme

# See server report on terminal (1) 'Lost/Total Datagrams' - should see lost packets there
```

It is generally understood that *packet loss* distribution in IP networks is “bursty”. To simulate more realistic *packet loss* events, different probability models are used.
Pumba currently supports 3 different loss probability models for *packet loss". Pumba defines separate *loss* command for each probability model.
- `loss` - independent probability loss model (Bernoulli model); it's the most widely used loss model where packet losses are modeled by a random process consisting of Bernoulli trails
- `loss-state` - 2-state, 3-state and 4-state State Markov models
- `loss-gemodel` - Gilbert and Gilbert-Elliott models

Papers on network packer loss models:
- "Indepth: Packet Loss Burstiness" [link](http://www.voiptroubleshooter.com/indepth/burstloss.html)
- "Definition of a general and intuitive loss model for packet networks and its implementation in the Netem module in the Linux kernel." [link](netgroup.uniroma2.it/TR/TR-loss-netem.pdf)
- `man netem` [link](http://man7.org/linux/man-pages/man8/tc-netem.8.html)

### `netem loss` examples

```
# loss 0.3% of packets
# apply for `eth0` network interface (default) of `mydb` Docker container for 5 minutes

$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
    pumba netem --duration 5m \
      loss --percent 0.3 \
      mydb
```

```
# loss 1.4% of packets (14 packets from 1000 will be lost)
# each successive probability (of loss) depends by a quarter on the last one
#   Prob(n) = .25 * Prob(n-1) + .75 * Random
# apply on `eth1` network interface  of Docker containers (name start with `hp`) for 15 minutes

$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
    pumba netem --interface eth1 --duration 15m \
      loss --percent 1.4 --correlation 25 \
      re2:^hp
```

```
# use 2-state Markov model for packet loss probability: P13=15%, P31=85%
# apply on `eth1` network interface of 3 Docker containers (c1, c2 and c3) for 12 minutes

$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
    pumba netem --interface eth1 --duration 12m \
      loss-state -p13 15 -p31 85 \
      c1 c2 c3
```

```
# use Gilbert-Elliot model for packet loss probability: p=5%, r=90%, (1-h)=85%, (1-k)=7%
# apply on `eth2` network interface of `mydb` Docker container for 9 minutes and 30 seconds

$ docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock gaiaadm/pumba \
    pumba netem --interface eth2 --duration 9m30s \
      loss-gemodel --pg 5 --pb 90 --one-h 85 --one-k 7 \
      mydb
```

## Contribution

Special thanks to [Neil Gehani](https://medium.com/@GehaniNeil) for helping me with this post and to [Inbar Shani](https://github.com/inbarshani) for initial Pull Request with `netem` command.

## Next

To see more examples on how to use Pumba with [netem] commands, please refer to the [Pumba GitHub Repository](https://github.com/gaia-adm/pumba). We have open sourced it. We gladly accept ideas, pull requests, issues, or any other contributions.

Pumba can be downloaded as precompiled binary (Windows, Linux and MacOS) from the [GitHub project release page](https://github.com/gaia-adm/pumba/releases). It’s also available as a [Docker image](https://hub.docker.com/r/gaiaadm/pumba/).

[Pumba GitHub Repository](https://github.com/gaia-adm/pumba)
