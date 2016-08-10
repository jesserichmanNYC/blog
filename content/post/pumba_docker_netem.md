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

Microservice architecture is one of the most important software architecture practices, that became tremendously popular during last years. The Docker technology enables microservice architecture: it helps to develop, deploy and operate distributed applications, composed from hundreds of micro-services, packaged into Docker containers.
While development and deployment of such applications became a common knowledge today, creating realistic and useful testing environment still remains a challenge. One of these challenges is related to the complexity of reproducing different network failures.
Network is an arterial system of any distributed application. Thoroughly testing of distributed application requires complex and realistic network test environments.

Once you deploy Docker containers on some Docker cluster, all communication between containers happens over the network. These containers can run on same host, different hosts, different networks and even different datacenters. Network behavior and it's properties have a great impact on overall application availability, stability and performance.

## Network Emulation

> So, what can you do to emulate different network properties, like: delay, packer loss, packet corruption and others? And even more: how can you emulate different network properties between containers, regardless of real network conditions or even if containers are running on the same host?

It happens, that Linux has a built-in network emulation capabilities, starting from kernel 2.6.7 (first released 14 years ago).
Linux allows to show and manipulate traffic control settings, using [tc](http://man7.org/linux/man-pages/man8/tc.8.html) tool (avaiable in `iproute2` package). [netem](http://man7.org/linux/man-pages/man8/tc-netem.8.html) is an extension (queueing discipline) of the `tc` tool, that allows emulation of different network properties, like: *delay*, *packet loss*, *packer reorder*, *duplication*, *corruption* and *bandwidth rate*.

`netem` is a very powerful tool, that can help you to simulate realistic testing network conditions for your distributed application. I highly recommend to take a closer look at it - it's a Swiss knife of network emulation.


## Pumba `netem`

[Pumba](https://github.com/gaia-adm/pumba) is a tool, we developed for our own use. Pumba is a chaos testing tool for Docker containers, inspired by [Netflix Chaos Monkey](https://github.com/Netflix/SimianArmy/wiki/Chaos-Monkey). The main difference, that it works with containers instead of VMs.
Pumba can kill, stop and restart running Docker containers or pause all processes within specified containers. We use it for resilience testing of our distributed applications. Resilience testing confirms that the system recovers from expected or unexpected events without loss of data or functionality. Pumba helps to simulate such events for distributed and containerized application.

Lately, we enhanced Pumba adding a network emulation capabilities, starting with *delay* and *packet loss*. Now it's possible to apply *delay* or *packet loss* on any Docker container.
Under the hood, Pumba uses linux kernel traffic control (`tc`) with `netem` queueing discipline. So, in order to make it work, you need to add `iproute2` package to your Docker images, that you want to test. Some base Docker images already include `iproute2` package, but you need to check.

Pumba wraps low level `netem` options and greatly simplifies its usage. There is no magic, but a lot of code had beed written to make it easier to emulate different network properties for running Docker containers.

Currently Pumba can modify egress traffic only, by adding *delay* or *packet loss*, for specified container(s). Target containers can be specified by name (single name or space separated list of names) or by RE2 regular expression. Pumba modifies container network only for defined duration and once time is passed, Pumba restores original network properties. Pumba will also restore original connection when you will gracefully shutdown the `pumba` process (with `Ctrl-C`) or stop Pumba container (with `docker stop`).

Another supported option, is an ability to apply IP (or IP range) filter to the network emulation. In this case, Pumba will modify outgoing traffic for specified IP and will leave other outgoing traffic unchanged. Using this feature, you can change network properties only for specific inter-container connections and also for specific Docker networks (each Docker network has its own IP range).

Pumba tool can be downloaded as precompiled binary (for Windows, Linux and MacOS) from GitHub project [release page](https://github.com/gaia-adm/pumba/releases), or you can use already prepared Pumba [Docker image](https://hub.docker.com/r/gaiaadm/pumba). Whatever option you like.


## Pumba dealy: `netem delay`

Lets start with very simple demo. Here we will run two Docker containers: one is running `ping` command and other is Pumba Docker container, that adds 3 seconds network *delay* to the first container for 1 minute. After 1 minute, Pumba container restores network connection properties of the first container and exits.

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

## Next

The Pumba project is available for you to try out. It's open source with Apache License.
We will gladly accept ideas, pull requests, issues, or any other contributions to the project.

[Pumba GitHub Repository](https://github.com/gaia-adm/pumba)
