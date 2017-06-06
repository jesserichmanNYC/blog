+++
date = "2017-06-03T18:00:00+02:00"
draft = true
title = "Advanced debugging of Node in Docker"
tags = ["docker", "tutorial", "devops", "hacks", "node", "node.js", "debug", "Dockerfile"]
categories = ["Docker"]
extlink = "https://codefresh.io/blog/debug_node_in_docker/"
+++

## Teaser

Suppose you want to debug a Node.js application already running on a remote machine inside Docker container. And would like to do it without modifying command arguments (enabling `debug` mode) and opening remote Node.js debugger agent port to the whole world.

**I bet you didn't know that it's possible and also have no idea how to do it.**

I encourage you to continue reading this post if you are eager to learn some new cool stuff.


## The TodoMVC demo application

I'm using the [fork](https://github.com/alexei-led/todomvc-express) of **TodoMVC** Node.js application (by Gleb Bahmutov) as a demo application for this blog post. Feel free to clone and play with this repository.

Here is the `Dockerfile`, I've added, for TodoMVC application. It allows to run TodoMVC application inside a Docker container.

```Dockerfile
FROM alpine:3.5

# install node
RUN apk add --no-cache nodejs-current tini

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# Build time argument to set NODE_ENV ('production'' by default)
ARG NODE_ENV
ENV NODE_ENV ${NODE_ENV:-production}

# install npm packages: clean obsolete files
COPY package.json /usr/src/app/
RUN npm config set depth 0 && \
    npm install && \
    npm cache clean && \
    rm -rf /tmp/*

# copy source files
COPY . /usr/src/app

EXPOSE 3000

# Set tini as entrypoint
ENTRYPOINT ["/sbin/tini", "--"]

CMD [ "npm", "start" ]

# add VCS labels for code sync and nice reports
ARG VCS_REF="local"
LABEL org.label-schema.vcs-ref=$VCS_REF \          
      org.label-schema.vcs-url="https://github.com/alexei-led/todomvc-express.git"
```

#### Building and Running TodoMVC in a Docker container:

To build a new Docker image for TodoMVC application, run the `docker build` command.

```shell
$ # build Docker image; set VCS_REF to current HEAD commit (short)
$ docker build -t local/todomvc --build-arg VCS_REF=`git rev-parse --short HEAD` .
$ # run TodoMVC in a Docker container
$ docker run -d -p 3000:3000 --name todomvc local/todomvc node src/start.js
```

## The Plan

**Final Goal** - I would like to be able to attach a Node.js debugger to a Node.js application already up and running inside a Docker container, running on remote host machine in AWS cloud, without modifying the application, container, container configuration or restarting it with additional `debug` flags. Imagine that the application is running and there is some problem happening right now - I want to connect to it with debugger and start looking at the problem.

So, I need a plan - a step by step flow that will help me to achieve the final goal. 

Let's start with exploring the inventory. On the server (AWS EC2 VM) machine, I have a Node.js application running inside a Docker container. On the client (my laptop), I have an IDE (Visual Studio Code, in my case), Node.js application code (`git pull/clone`) and a Node.js debugger.

So, here is my plan:

1. Set already running application to `debug` mode
2. Expose a new Node.js debugger agent port to enable remote debugging in a secure way
3. Syncronize client-server code: both should be on the same commit in `git` tree
4. Attach a local Node.js debugger to the Node.js debugger agent port on remote server and do it in a secure way
5. And, if everything works, I should be able to perform regular debugging tasks, like setting breakpoints, inspecting variables, pausing execution and others.

![Debug Node in Docker](/img/debug_docker_node.png)

### Step 1: set already running Node.js application to the `debug` mode

 > The V8 debugger can be enabled and accessed either by starting Node with the `--debug` command-line flag or by signaling an existing Node process with `SIGUSR1`. (Node API documentation)

 Cool! So, in order to switch on Node debugger agent, I just need to send the `SIGUSR1` signal to the Node.js process of TodoMVC application. Remember, it's running inside a Docker container. What command can I use to send process signals to an application running in a Docker container? 

 The `docker kill` - is my choice! This command does not actually "kill" the `PID 1` process, running in a Docker container, but sends a [Unix signal](https://en.wikipedia.org/wiki/Unix_signal) to it (by default it sends `SIGKILL`). 

#### Setting TodoMVC into `debug` mode

So, all I need to do is to send `SIGUSR1` to my TodoMVC application running inside `todomvc` Docker container.

There are two ways to do this:

1. Use `docker kill --signal` command to send `SIGUSR1` to `PID 1` process running inside Docker container, and if it's a "proper" (signal forwarding done right) init application (like `tini`), than this will work
2. Or execute `kill -s SIGUSR1` inside already running Docker container, sending `SIGUSR1` signal to the main Node.js process.

```shell
$ # send SIGUSR1 with docker kill (if using proper init process)
$ docker kill --signal SIGUSR1 todomvc 
$ # OR run kill command for node process inside todomvc container
$ docker exec -it todomvc sh -c 'kill -s SIGUSR1 $(pidof -s node)'
```

Let's verify that Node application is set into `debug` mode.

```shell
$ docker logs todomvc

TodoMVC server listening at http://:::3000
emitting 2 todos
server has new 2 todos
GET / 200 31.439 ms - 3241
GET /app.css 304 4.907 ms - -
Starting debugger agent.
Debugger listening on 127.0.0.1:5858
```

As you can see the Node.js debugger agent was started, but it can accept connections only from the `localhost`, see the last output line: `Debugger listening on 127.0.0.1:5858`

### Step 2: expose Node debug port

In order to attach a remote Node.js debugger to a Node application, running in the `debug` mode, I need: 

1. Allow connection to debugger agent from any (or specific) IP (or IP range)
2. Open port of Node.js debugger agent outside of Docker container

How to do it when an application is already running in a Docker container and a Node.js debugger agent is ready to talk only with a Node.js debugger running on the same machine, plus a Node.js debugger agent port is not accessible from outside of the Docker container?

Of cause it's possible to start every Node.js Docker container with exposed debugger port and allow connection from any IP (using `--debug-port` and `--debug` Node.js flags), but we are not looking for easy ways :).

It's not a good idea from a security point of view (allowing unprotected access to a Node.js debugger). Also, if I restart an already running application with debug flags, I'm going to loose the current execution context and may not be able to reproduce the problem I wanted to debug.

I need a better solution!

Unfortunately, Docker does not allow to expose an additional port of already running Docker container. So, I need somehow connect to a running container network and expose a new port for Node.js debugger agent.

Also, it is not possible to tell a Node.js debugger agent to accept connections from different IP addresses, when Node.js process was already started.

Both of above problems can be solved with help of the small Linux utility called `socat` (SOcket CAT). This is just like the `netcat` but with security in mind (e.g., it support chrooting) and works over various protocols and through files, pipes, devices, TCP sockets, Unix sockets, a client for SOCKS4, proxy CONNECT, or SSL etc.

From `socat` man page:
> `socat` is a command line based utility that establishes two bidirectional byte streams and transfers data between them. Because the streams can be constructed from a large set of different types of data sinks and sources (see address types), and because lots of address options may be applied to the streams, `socat` can be used for many different purposes.

Exactly, what I need!

So, here is the plan. I will run a new Docker container with the `socat` utility onboard, and configure Node.js debugger port forwarding for TodoMVC container.

`socat.Dockerfile`:
```Dockerfile
FROM alpine:3.5
RUN apk add --no-cache socat
CMD socat -h
```

#### Building socat Docker container

```shell
$ docker build -t local/socat - < socat.Dockerfile
```

#### Allow connection to Node debugger agent from any IP

I need to run a "sidecar" `socat` container in the same network namespace as the `todomvc` container and define a port forwarding.

```shell 
$ # define local port forwarding
$ docker run -d --name socat-nid --network=container:todomvc local/socat socat TCP-LISTEN:4848,fork TCP:127.0.0.1:5858
```

Now any traffic that arrives at `4848` port will be routed to the Node.js debugger agent listening on `127.0.0.1:5858`. The `4848` port can accept traffic from any IP. 
It's possible to use an IP range to restrict connection to the `socat` listening port, adding `range=<ANY IP RANGE>` option.

#### Exposing Node.js debugger port from Docker container

First, we will get IP of `todomvc` Docker container.

```shell
$ # get IP of todomvc container
$ TODOMVC_IP=$(docker inspect -f "{{.NetworkSettings.IPAddress}}" todomvc)
```

Then, configure port forwarding to the "sidecar" `socat` port, we define previously, running on the same network as the `todomvc` container.

```shell
$ # run socat container to expose Node.js debugger agent port forwarder
$ docker run -d -p 5858:5858 --name socat local/socat socat TCP-LISTEN:5858,fork TCP:${TODOMVC_IP}:4848
```

Any traffic that will arrive at the `5858` port on the Docker host will be forwarded, first, to the `4848` socat port and then to the Node.js debugger agent running inside the `todomvc` Docker container.

#### Exposing Node.js debugger port for remote access

In most cases, I would like to debug an application running on a remote machine (AWS EC2 instance, for example). I also do not want to expose a Node.js debugger agent port unprotected to the whole world.

One possible and working solution is to use SSH tunneling to access this port.

```shell
$ # Open SSH Tunnel to gain access to servers port 5858. Set `SSH_KEY_FILE` to ssh key location or add it to ssh-agent
$ #
$ # open an ssh tunnel, send it to the bg, and wait 20 seconds for connections
$ # once all connections are closed after 20 seconds then close the tunnel
$ ssh -i ${SSH_KEY_FILE} -f -o ExitOnForwardFailure=yes -L 5858:127.0.0.1:5858 ec2_user@some.ec2.host.com sleep 20
```

Now all traffic to the `localhost:5858` will be tunneled over `SSH` to the remote Docker host machine and after some `socat` forwarding to the Node.js debugger agent running inside the `todomvc` container.

### Step 3: Synchronizing on the same code commit

In order to be able to debug a remote application, you need to make sure that you are using the same code in your IDE as one that is running on remote server.

I will try to automate this step too. Remember the `LABEL` command, I've used in TodoMVC `Dockerfile`? 

These labels help me to identify git repository and commit for the application Docker image: 

1. `org.label-schema.vcs-ref` - contains short SHA for a `HEAD` commit
2. `org.label-schema.vcs-url` - contains an application git repository url (I can use in `clone/pull`)

I'm using (Label Schema Convention)[http://label-schema.org/rc1/], since I really like it and find it useful, but you can select any other convention too.

This approach allows me, for each, properly labeled, Docker image, to identify the application code repository and the commit it was created from.

```shell
$ # get git repository url form Docker image
$ GIT_URL=$(docker inspect local/todomvc | jq -r '.[].ContainerConfig.Labels."org.label-schema.vcs-url"')
$ # get git commit from Docker image
$ GIT_COMMIT=$(docker inspect local/todomvc | jq -r '.[].ContainerConfig.Labels."org.label-schema.vcs-ref"')
$ 
$ # clone git repository, if needed
$ git clone $GIT_URL
$ # set HEAD to same commit as server
$ git checkout $GIT_COMMIT
```

Now, both my local development environment and remote application are on the same git commit. And I can start to debug my code, finally!

### Step 4: Attaching local Node.js debugger to debugger agent port

To start debugging, I need to configure my IDE. In my case, it's [Visual Studio Code](https://code.visualstudio.com/) and I need to add a new `Launch` configuration.

This launch configuration specifies remote debugger server and port to attach and remote location for application source files, which should be in sync with local files (see the previous step).

```json
{
    // For more information about Node.js debug attributes, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {
            "type": "node",
            "request": "attach",
            "name": "Debug Remote Docker",
            "address": "127.0.0.1",
            "port": 5858,
            "localRoot": "${workspaceRoot}/",
            "remoteRoot": "/usr/src/app/"
        }
    ]
}

```
## Summary

And finally, I've met my goal: I'm able to attach a Node.js debugger to a Node.js application, that is already up and running in a Docker container on a remote machine.

It was a long journey to find the proper solution, but after I found it, the process does not look complex at all. Now, once I met a new problem in our environment I can easily attach the Node.js debugger to the running application and start exploring the problem. Nice, isn't it?

I've recorded a short movie, just to demonstrate all steps and prove that things are working fluently, exactly as I've described in this post.

{{< youtube WYOfNTJmE_4 >}}

---

Hope, you find this post useful. I look forward to your comments and any questions you have.

---

*This is a **working draft** version. The final post version is published at [Codefresh Blog](https://codefresh.io/blog/debug_node_in_docker/) on June 6, 2017.*