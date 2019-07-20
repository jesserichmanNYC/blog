+++
date = "2017-10-04T18:00:00+02:00"
draft = false
title = "Chaos Testing for Docker Containers"
tags = ["docker", "chaos monkey", "chaos testing", "chaos", "testing", "devops", "chaos engineering", "netem", "network emulation"]
categories = ["Chaos Testing"]
+++

What follows is the text of my presentation, *Chaos Testing for Docker Containers* that I gave at [ContainerCamp](https://2017.container.camp/uk) in London this year. 
I've also decided to turn the presentation into an article. I edited the text slightly for readability and added some links for more context. You can find the original video recording and slides at the end of this post.

![Docker Chaos Testing](/img/sink_cargo.jpg)

## Intro

Software development is about building software services that support business needs. More complex businesses processes we want to automate and integrate with. the more complex software system we are building. And solution complexity is tend to grown over time and scope.

The reasons for growing complexity can be different. Some systems just tend to handle too many concerns, or require a lot of integrations with external services and internal legacy systems. These systems are written and rewritten multiple times over several years by different people with different skills, trying to satisfy constantly changing business requirements, using different technologies, following different technology and architecture trends.

So, my point, is that building software, that unintentionally become more and more complex over time, is easy - we all done in the past it or doing it right now. Building a "good" software architecture for complex systems and preserving it's "good" abilities for some period of time, is really hard.

When you have too many "moving" parts, integrations, constantly changing requirements, that lead to code changes, security upgrades, hardware modernization, multiple network communication channels and etc, it can become a "Mission Impossible" to avoid unexpected failures.

## Stuff happens!

All systems fail from time to time. And your software system will fail too. Take this as a fact of life. There will always be something that can — and will — go wrong. No matter how hard we try, we can’t build perfect software, nor can the companies we depend on. Even the most stable and respectful services from companies, that practice CI/CD, test driven development (TDD/BDD), have huge QA departments and well defined release procedures, fail. 

Just a few examples from the last year outages:

1. **BM, January 26** 
    - IBM's cloud credibility took a hit at the start of the year when a management portal used by customers to access its Bluemix cloud infrastructure went down for several hours. While no underlying infrastructure actually failed, users were frustrated in finding they couldn't manage their applications or add or remove cloud resources powering workloads.
    - IBM said the problem was intermittent and stemmed from a botched update to the interface.
2. **GitLab, January 31** 
    - GitLab's popular online code repository, GibLab.com, suffered an 18-hour service outage that ultimately couldn't be fully remediated. 
    - The problem resulted when an employee removed a database directory from the wrong database server during maintenance procedures.
3. **AWS, February 28** 
    - [This was the outage](http://www.crn.com/news/cloud/300083958/aws-storage-outage-wreaking-havoc-on-web-services-providers.htm) that shook the industry.
    - An Amazon Web Services engineer trying to debug an S3 storage system in the provider's Virginia data center accidentally typed a command incorrectly, and much of the Internet – including many enterprise platforms like Slack, Quora and Trello – was down for four hours.
4. **Microsoft Azure, March 16**
    - Storage availability issues plagued Microsoft's Azure public cloud for more than eight hours, mostly affecting customers in the Eastern U.S.
    - Some users had trouble provisioning new storage or accessing existing resources in the region. A Microsoft engineering team later identified the culprit as a storage cluster that lost power and became unavailable.

Visit [Outage.Report](http://outage.report) or [Downdetector](http://downdetector.com) to see a constantly updating long list of outages reported by end-users.

## Chasing Software Quality

As software engineers, we what to be proud of software systems we are building. We want theses systems to be of high quality, without functional bugs, security holes, providing exceptional performance, resilient to unexpected failures, self-healing, always available and easy to maintain and modernize.

Every new project starts with "high quality" picture in mind and none wants to create crappy software, but very few of us (or none) are able to achieve and keep intact all good "abilities". So, what we can do to improve overall system quality? Should we do more testing? 

I tend to say "Yes" - software testing is critical. But just running unit, functional and performance testing is not enough. 

Today, building complex distributed system is much easier with all new amazing technology we have and experience we gathered. Microservice Architecture is a real trend nowadays and miscellaneous container technologies support this architecture. It's much easier to deploy, scale, link, monitor, update and manage distributed systems, composed from multiple "microservices". 
When we are building distributed systems, we are choosing **P** (*Pratition Tolerance*) from the [CAP theorem](https://en.wikipedia.org/wiki/CAP_theorem) and second to it either **A** (*Availability* - the most popular choice) or **C** (*Consistency*). So, we need to find a good approach for testing **AP** or **CP** systems.

Traditional testing disciplines and tools do not provide a good answer to *how does your distributed system behave when unexpected stuff happens in production?*. 
Sure, you can learn from previous failures, after the fact, and you should definitely do it. But, learning from past experience should not be the only way to prepare for the future failures.

Waiting for things to break in production is not an option. But what’s the alternative?

## Chaos Engineering

The alternative is to break things on purpose. And Chaos Engineering is a particular approach to doing just that. The idea of Chaos Engineering is to *embrace the failure!*
Chaos Engineering for distributed software systems was originally popularized by Netflix. 

Chaos Engineering defines an empirical approach to resilience testing of distributed software systems. You are testing a system by conducting *chaos experiments*.

Typical *chaos experiment*:
- define a *normal/steady* state of the system (e.g. by monitoring a set of system and business metrics)
- pseudo-randomly inject faults (e.g. by terminating VMs, killing containers or changing network behavior)
- try to discover system weaknesses by deviation from expected or steady-state behavior 

The harder it is to disrupt the steady state, the more confidence we have in the behavior of the system.  

## Chaos Engineering tools

Of cause it's possible to practice Chaos Engineering manually, or relay on automatic system updates, but we, as engineers like to automate boring manual tasks, so there are some nice tools to use.

Netflix built a some [useful tools](https://github.com/Netflix/SimianArmy/wiki) for practicing Chaos Engineering in public cloud (AWS):
- Chaos Monkey - kill EC2, kill processes, burn CPU, fill disk, detach volumes, add network latency, etc
- Chaos Kong - remove whole AWS Regions

These are very good tools, I encourage you to use them. But when I've started my new container based project (2 years ago), it looks like these tools provided just a *wrong* granularity for *chaos* I wanted to create, and I wanted to be able to create the *chaos* not only in real cluster, but also on single developer machine, to be able to debug and tune my application. So, I've searched Google for *Chaos Monkey for Docker*, but did not find anything, besides some basic Bash scripts. 
So, I've decided to create my own tool. And since it happens to be quite a useful tool from the very first version, I've shared it with a community as an open source. It's a Chaos ~~Monkey~~ Warthog for Docker - [Pumba](https://github.com/gaia-adm/pumba)

## Pumba - Chaos Testing for Docker

*What is Pumba(a)?*

Those of us who have kids or was a kid in 90s should remember this character from Disney's animated film **The Lion King**. In Swahili, **pumbaa** means "*to be foolish, silly, weak-minded, careless, negligent*". I like the Swahili meaning of this word. It matched perfectly for the tool I wanted to create.

### What Pumba can do?

Pumba disturbs running Docker runtime environment by injecting different failures. Pumba can `kill`, `stop`, `remove` or `pause` Docker container. 
Pumba can also do a network emulation, simulating different network failures, like: delay, packet loss (using different probability loss models), bandwidth rate limits and more. For network emulation, Pumba uses Linux kernel traffic control `tc` with `netem` queueing discipline, read more [here](http://man7.org/linux/man-pages/man8/tc-netem.8.html). If `tc` is not available within target container, Pumba uses a *sidekick* container with `tc` on-board, attaching it to the target container network.

You can pass list of containers to the Pumba or just write a regular expression to select matching containers. If you will not specify containers, Pumba will try to disturb all running containers. Use `--random` option, to randomly select only one target container from the provided list. It's also possible to define a repeatable time interval and duration parameters to better control the amount of *chaos* you want to create.

Pumba is available as a single binary file for Linux, MacOS and Windows, or as a Docker container.

```sh
# Download binary from https://github.com/gaia-adm/pumba/releases
curl https://github.com/gaia-adm/pumba/releases/download/0.4.6/pumba_linux_amd64 --output /usr/local/bin/pumba
chmod +x /usr/local/bin/pumba && pumba --help

# Install with Homebrew (MacOS only)
brew install pumba && pumba --help

# Use Docker image
docker run gaiaadm/pumba pumba --help

```

### Pumba commands examples

First of all, run `pumba --help` to get help about available commands and options and `pumba <command> --help` to get help for the specific command and sub-command. 

```sh
# pumba help
pumba --help

# pumba kill help
pumba kill --help

# pumba netem delay help
pumba netem delay --help
```

Killing randomly chosen Docker container from  `^test` regex list.

```sh
# on main pane/screen, run 7 test containers that do nothing
for i in {0..7}; do docker run -d --rm --name test$i alpine tail -f /dev/null; done
# run an additional container with 'skipme' name
docker run -d --rm --name skipme alpine tail -f /dev/null

# run this command in another pane/screen to see running docker containers
watch docker ps -a

# go back to main pane/screen and kill (once in 10s) random 'test' container, ignoring 'skipme'
pumba --random --interval 10s kill re2:^test
# press Ctrl-C to stop Pumba at any time
```

Adding a `3000ms` (`+-50ms`) delay to the *engress* traffic for the `ping` container for `20` seconds, using *normal* distribution model.

```sh
# run "ping" container on one screen/pane
docker run -it --rm --name ping alpine ping 8.8.8.8

# on second screen/pane, run pumba netem delay command, disturbing "ping" container; sidekick a "tc" helper container
pumba netem --duration 20s --tc-image gaiadocker/iproute2 delay --time 3000 jitter 50 --distribution normal ping
# pumba will exit after 20s, or stop it with Ctrl-C
```

To demonstrate packet loss capability, we will need three screens/panes. I will use `iperf` network bandwidth measurement [tool](https://iperf.fr).
On the first pane, run *server* docker container with `iperf` on-board and start there a UDP server. On the second pane, start *client* docker container with `iperf` and send datagrams to the *server* container. Then, on the third pane, run `pumba netem loss` command, adding a packet loss to the *client* container. Enjoy the chaos.

```sh
# create docker network
docker network create -d bridge testnet

# > Server Pane
# run server container
docker run -it --name server --network testnet --rm alpine sh -c "apk add --no-cache iperf; sh"
# shell inside server container: run a UDP Server listening on UDP port 5001
sh$ iperf -s -u -i 1

# > Client Pane
# run client container
docker run -it --name client --network testnet --rm alpine sh -c "apk add --no-cache iperf; sh"
# shell inside client container: send datagrams to the server -> see no packet loss
sh$ iperf -c server -u

# > Server Pane
# see server receives datagrams without any packet loss

# > Pumba Pane
# inject 20% packet loss into client container, for 1m
pumba netem --duration 1m --tc-image gaiadocker/iproute2 loss --percent 20 client

# > Client Pane
# shell inside client container: send datagrams to the server -> see ~20% packet loss
sh$ iperf -c server -u

```

## Session and slides

{{< youtube 68ZepHa5UVg >}}

[Slides](https://speakerdeck.com/alexeiled/chaos-testing-for-docker-containers)

---

Hope, you find this post useful. I look forward to your comments and any questions you have.
