+++
date = "2016-11-26T16:00:00+02:00"
draft = false
title = "Do not ignore .dockerignore"
tags = ["Docker", "build", "dockerignore", "devops"]
categories = ["Development"]
extlink = "https://codefresh.io/blog/not-ignore-dockerignore/"
+++

# TL;DR

> **Tip:** Consider to define and use `.dockerignore` file for every Docker image you are building. It can help you to reduce Docker image size, speedup `docker build` and avoid unintended secret exposure.

![Overloaded container ship](/img/overloaded.jpg)

# Docker build context

The `docker build` command is used to build a new Docker image. There is one argument you can pass to the `build` command **build context**.

So, what is the Docker **build context**?

First, remember, that Docker is a client-server application, it consists from Docker client and Docker server (also known as *daemon*). The Docker client command line tool talks with Docker server and asks it do things. One of these things is **build**: building a new Docker image. The Docker server can run on the same machine as the client, remote machine or virtual machine, that also can be local, remote or even run on some cloud IaaS.

Why is that important and how is the Docker **build context** related to this fact?

In order to create a new Docker image, Docker server needs an access to files, you want to create the Docker image from. So, you need somehow to send these files to the Docker server. These files are the Docker **build context**. The Docker client packs all **build context** files into `tar` archive and uploads this archive to the Docker server. By default client will take all files (and folders) in current working directory and use them as the **build context**.
It can also accept already created `tar` archive or `git` repository. In a case of `git` repository, the client will clone it with submodules into a temporary folder and will create a **build context** archive from it.

# Impact on Docker build

The first output line, that you see, running the `docker build` command is:
```
Sending build context to Docker daemon 45.3 MB
Step 1: FROM ...
```

This should make things clear. Actually, **every time** you are running the `docker build` command, the Docker client creates a new **build context** archive and sends it to the Docker server. So, you are always paying this "tax": the time it takes to create an archive, storage and network traffic and latency time.

> **Tip:** The **rule of thumb** is not adding files to the **build context**, if you do not need them in your Docker image.

# The **.dockerignore** file

The `.dockerignore` file is the tool, that can help you to define the Docker **build context** you really need. Using this file, you can specify **ignore rules** and **exceptions** from these rules for files and folder, that won't be included in the **build context** and thus won't be packed into an archive and uploaded to the Docker server.

# Why should you care?

Indeed, why should you care? Computers today are fast, networks are also pretty fast (hopefully) and storage is cheap. So, this "tax" may be not that big, right?
I will try to convince you, that you should care.

## Reason #1: Docker image size

The world of software development is shifting lately towards *continuous delivery*, *elastic infrastructure* and *microservice architecture*.

How is that related?

Your systems are composed of multiple components (or *microservices*), each one of them running inside Linux container. There might be tens or hundreds of services and even more service instances. These service instances can be built and deployed independently of each other and this can be done for **every single code commit**. More than that, *elastic infrastructure* means that new compute nodes can be added or removed from the system and its microservices can move from node to node, to support scale or availability requirements. That means, your Docker images will be frequently built and transferred.

When you practice continuous delivery and microservice architecture, image size and image build time **do matter**.

## Reason #2: Unintended secrets exposure

Not controlling your **build context**, can also lead to an unintended exposure of your code, commit history, and secrets (keys and credentials).

If you copy files into you Docker image with `ADD .` or `COPY .` command, you may unintendedly include your source files, whole `git` history (a `.git` folder), secret files (like `.aws`, `.env`, private keys), cache and other files not only into the Docker **build context**, but also into the final Docker image.

There are multiple Docker images currently available on DockerHub, that expose application source code, passwords, keys and credentials (for example [Twitter Vine](http://thehackernews.com/2016/07/vine-source-code.html)).

## Reason #3: The Docker build - cache invalidation

A common pattern is to inject an application's entire codebase into an image using an instruction like this:

```
COPY . /usr/src/app
```

In this case, we're copying the **entire** **build context** into the image. It's also important to understand, that every Dockerfile command generates a new layer. So, if any of included file changes in the entire build context, this change will invalidate the build cache for `COPY . /opt/myapp` layer and a new image layer will be generated on the next build.

If your working directory contains files that are frequently updated (logs, test results, git history, temporary cache files and similar), you are going to regenerate this layer for every `docker build` run.


# The `.dockerignore` syntax

The `.dockerignore` file is similar to `gitignore` file, used by `git` tool. similarly to `.gitignore` file, it allows you to specify a pattern for files and folders that should be ignored by the Docker client when generating a **build context**. While `.dockerignore` file syntax used to describe **ignore patterns** is similar to `.gitignore` it's not the same.

The `.dockerignore` pattern matching syntax is based on Go `filepath.Match()` function and includes some additions.

Here is the complete syntax for the `.dockerignore`:

```
pattern:
    { term }
term:
    '*'         matches any sequence of non-Separator characters
    '?'         matches any single non-Separator character
    '[' [ '^' ] { character-range } ']'
                character class (must be non-empty)
    c           matches character c (c != '*', '?', '\\', '[')
    '\\' c      matches character c

character-range:
    c           matches character c (c != '\\', '-', ']')
    '\\' c      matches character c
    lo '-' hi   matches character c for lo <= c <= hi

additions:
  '**'        matches any number of directories (including zero)
  '!'         lines starting with ! (exclamation mark) can be used to make exceptions to exclusions
    '#'         lines starting with this character are ignored: use it for comments
```

**Note:** Using the `!` character is pretty tricky. The combination of it and patterns before and after line with the `!` character can be used to create more advanced rules.

## Examples

```
# ignore .git and .cache folders
.git
.cache
```

```
# ignore all *.class files in all folders, including build root
**/*.class
```

```
# ignore all markdown files (md) beside all README*.md other than README-secret.md
*.md
!README*.md
README-secret.md
```

# Next

- RTFM - https://docs.docker.com/engine/reference/builder/#/dockerignore-file
- Use `.dockerignore` in every project, where you are building Docker images

----------

Hope you find this post useful. I look forward to your comments and any questions you have.

---

*This is a **working draft** version.* 
*The final post version is published at [Codefresh Blog](https://codefresh.io/blog/not-ignore-dockerignore/) on December 8, 2016*
