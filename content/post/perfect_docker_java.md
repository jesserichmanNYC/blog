+++
date = "2017-03-07T18:00:00+02:00"
draft = false
title = "Crafting perfect Java Docker build flow"
tags = ["docker", "tutorial", "devops", "hacks", "java", "maven"]
categories = ["DevOps"]
extlink = "https://codefresh.io/blog/java_docker_pipeline/"
+++

## TL;DR

> _What is the bare minimum you need to **build**, **test** and **run** my Java application in Docker container?_

> **The recipe:** Create a separate Docker image for each step and optimize the way you are running it.

![Duke and Container](/img/duke_docker.png)

## Introduction

I started working with Java in 1998, and for a long time, it was my main programming language. It was a long love–hate relationship.

DDuring my work career, I wrote a lot of code in Java. Despite that fact, I don’t think Java is usually the right choice for writing microservices running in [Docker](https://www.docker.com/) containers.

But, sometimes you have to work with Java. Maybe Java is your favorite language and you do not want to learn a new one, or you have a legacy code that you need to maintain, or your company decided on Java and you have no other option.

Whatever reason you have to **_marry Java with Docker_**, you better **_do it properly_**.

In this post, I will show you how to create an effective Java-Docker build pipeline to consistently produce small, efficient, and secure Docker images.


## Be careful

There are plenty of _“Docker for Java developers”_ tutorials out there, that unintentionally encourage some Docker bad practices. 

For example: 

- [Spark and Docker tutorial](https://sparktutorials.github.io/2015/04/14/getting-started-with-spark-and-docker.html)
- [Introducing Docker for Java Developers](https://examples.javacodegeeks.com/devops/docker/introduction-docker-java-developers/) 
- [Using Java with Docker Engine](http://www.developer.com/java/data/using-java-with-docker-engine.html)
- and others ...

For current demo project, first two tutorials took around 15 minutes to build (first build) and produced images of 1.3GB size each.

> Make yourself a favor and do not follow these tutorials!

## What should you know about Docker?

Developers new to Docker are often tempted to think of it as just another VM. Instead, think of Docker as a “child process”. The files and packages needed for an entire VM are different from those needed by just another process running a dev machine. Docker is even better than a child process because it allows better isolation and environmental control.

If you’re new to Docker, I suggest reading this [Understanding Docker](https://docs.docker.com/engine/understanding-docker/) article. Docker isn’t so complex than any developer should not be able to understand how it works.

## Dockerizing Java application

### What files need to be included in a Java Application’s Docker image?

Since Docker containers are just isolated processes, your Java Docker image should only contain the files required to run your application.

_What are these files?_

It starts with a Java Runtime Environment (**JRE**). **JRE** is a software package, that has everything required to run a Java program. It includes an implementation of the Java Virtual Machine (**JVM**) with an implementation of the _Java Class Library_.

I recommend using [OpenJDK](http://openjdk.java.net/) JRE. OpenJDK is licensed under [GPL](https://en.wikipedia.org/wiki/GNU_General_Public_License) with [Classpath Exception](http://www.gnu.org/software/classpath/license.html). The _Classpath Exception_ part is important. This license allows using OpenJDK with any software of any license, not just the GPL. In particular, you can use OpenJDK in proprietary software without disclosing your code.

Before using Oracle’s JDK/JRE, please read the following post: [“Running Java on Docker? You’re Breaking the Law.”](http://blog.takipi.com/running-java-on-docker-youre-breaking-the-law/)

Since it’s rare for Java applications to be developed using only the standard library, you most likely need to also add 3rd party Java libraries. Then add the application compiled bytecode as plain _Java Class_ files or packaged into _JAR_ archives. And, if you are using native code, you will need to add corresponding native libraries/packages too.

### Choosing a base Docker image for Java Application

In order to choose the base Docker image, you need to answer the following questions:

- _What native packages do you need for your Java application?_
- _Should you choose Ubuntu or Debian as your base image?_
- _What is your strategy for patching security holes, including packages you are not using at all?_
- _Do you mind paying extra (money and time) for network traffic and storage of unused files?_

Some might say: _“but, if all your images share the same Docker layers, you only download them just once, right?”_

That’s _true_ in theory, but in reality is often very different.

Usually, you have lots of different images: some you built lately, others a long time ago, others you pull from DockerHub. All these images do not share the same base image or version. You need to invest a lot of time to align these images to share the same base image and then keep these images up-to-date.

Some might say: _“but, who cares about image size? we download them just once and run forever”_. 

Docker image size is actually very important.

The size has an impact on …

- **network latency** - need to transfer Docker image over the web
- **storage** - need to store all these bits somewhere
- **service availability and elasticity** - when using a Docker scheduler, like Kubernetes, Swarm, DC/OS or other (scheduler can move containers between hosts)
- **security** - do you really, I mean really need the libpng package with all its [CVE vulnerabilities](https://www.cvedetails.com/vulnerability-list/vendor_id-7294/Libpng.html) for your Java application?
- **development agility** - small Docker images == faster build time and faster deployment

Without being careful, Java Docker images tends to grow to enormous sizes. I’ve seen 3GB Java images, where the real code and required JAR libraries only take around 150MB.

Consider using [Alpine Linux image](https://hub.docker.com/_/alpine/), which is only a 5MBs image, as a base Docker image. Lots of ["Official Docker images"](https://github.com/docker-library/official-images) have an Alpine-based flavor.

**Note**: Many, but not all Linux packages have versions compiled with `musl libc` C runtime library. Sometimes you want to use a package that is compiled with `glibc` (GNU C runtime library). The [frolvlad/alpine-glibc](https://hub.docker.com/r/frolvlad/alpine-glibc/) image based on Alpine Linux image and contains `glibc` to enable proprietary projects, compiled against `glibc` (e.g. OracleJDK, Anaconda), working on Alpine.

### Choosing the right Java Application server

Frequently, you also need to expose some kind of interface to reach your Java application, that runs in a Docker container.

When you deploy Java applications with Docker containers, the default Java deployment model changes.

Originally, Java server-side deployment assumes that you have already pre-configured a Java Web Server (Tomcat, WebLogic, JBoss, or other) and you are deploying an application **WAR** (Web Archive) packaged Java application to this server and run it together with other applications, deployed on the same server.

Lots of tools are developed around this concept, allowing you to update running applications without stopping the Java Application server, route traffic to the new application, resolve possible class loading conflicts and more.

With Docker-based deployments, you do not need these tools anymore, you don't even need the fat "enterprise-ready" Java Application servers. The only thing that you need is a stable and scalable network server that can serve your API over HTTP/TCP or other protocol of your choice. Search Google for [“embedded Java server”](https://www.google.com/search?q="embedded java server") and take one that you like most.

For this demo, I forked [Spring Boot's REST example](https://github.com/khoubyari/spring-boot-rest-example) and modified it a bit. The demo uses [Spring Boot](https://projects.spring.io/spring-boot/) with an embedded [Tomcat](http://tomcat.apache.org/) server. Here is my [fork](https://github.com/alexei-led/spring-boot-rest-example) on GitHub repository (`blog` branch).

### Building a Java Application Docker image

In order to run this demo, I need to create a Docker image with JRE, the compiled and packaged Java application, and all 3rd party libraries.

Here is the `Dockerfile` I used to build my Docker image. This demo Docker image is based on slim Alpine Linux with OpenJDK JRE and contains the application WAR file with all dependencies embedded into it. It's just the bare minimum required to run the demo application.

```dockerfile
# Base Alpine Linux based image with OpenJDK JRE only
FROM openjdk:8-jre-alpine

# copy application WAR (with libraries inside)
COPY target/spring-boot-*.war /app.war

# specify default command
CMD ["/usr/bin/java", "-jar", "-Dspring.profiles.active=test", "/app.war"]
```

To build the Docker image, run the following command:

```sh
$ docker build -t blog/sbdemo:latest .
```

Running the `docker history` command on created Docker image will let you to see all layers that make up this image:

- 4.8MB Alpine Linux Layer
- 103MB OpenJDK JRE Layer
- 61.8MB Application WAR file

```
$ docker history blog/sbdemo:latest

IMAGE               CREATED             CREATED BY                                      SIZE                COMMENT
16d5236aa7c8        About an hour ago   /bin/sh -c #(nop)  CMD ["/usr/bin/java" "-...   0 B                 
e1bbd125efc4        About an hour ago   /bin/sh -c #(nop) COPY file:1af38329f6f390...   61.8 MB             
d85b17c6762e        2 months ago        /bin/sh -c set -x  && apk add --no-cache  ...   103 MB              
<missing>           2 months ago        /bin/sh -c #(nop)  ENV JAVA_ALPINE_VERSION...   0 B                 
<missing>           2 months ago        /bin/sh -c #(nop)  ENV JAVA_VERSION=8u111       0 B                 
<missing>           2 months ago        /bin/sh -c #(nop)  ENV PATH=/usr/local/sbi...   0 B                 
<missing>           2 months ago        /bin/sh -c #(nop)  ENV JAVA_HOME=/usr/lib/...   0 B                 
<missing>           2 months ago        /bin/sh -c {   echo '#!/bin/sh';   echo 's...   87 B                
<missing>           2 months ago        /bin/sh -c #(nop)  ENV LANG=C.UTF-8             0 B                 
<missing>           2 months ago        /bin/sh -c #(nop) ADD file:eeed5f514a35d18...   4.8 MB              
```

### Running the Java Application Docker container

In order to run the demo application, run following command:

```sh
$ docker run -d --name demo-default -p 8090:8090 -p 8091:8091 blog/sbdemo:latest
```

Let's check, that application is up and running (I’m using the `httpie` tool here):

```sh
$ http http://localhost:8091/info

HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 09 Mar 2017 14:43:28 GMT
Server: Apache-Coyote/1.1
Transfer-Encoding: chunked

{
    "build": {
        "artifact": "${project.artifactId}",
        "description": "boot-example default description",
        "name": "spring-boot-rest-example",
        "version": "0.1"
    }
}

```

#### Setting Docker container memory constraints

One thing you need to know about Java process memory allocation is that in reality it consumes more physical memory than specified with the `-Xmx` JVM option. The `-Xmx` option specifies only the maximum Java heap size. But the Java process is a regular Linux process and what is interesting, is how much actual physical memory this process is consuming.

Or in other words - _what is the **Resident Set Size** (**RSS**) value for running a Java process?_

Theoretically, in the case of a Java application, a required RSS size can be calculated by:

```
RSS = Heap size + MetaSpace + OffHeap size
```

where _OffHeap_ consists of thread stacks, direct buffers, mapped files (libraries and jars) and JVM code itself.

There is a very good post on this topic: [Analyzing java memory usage in a Docker container](http://trustmeiamadeveloper.com/2016/03/18/where-is-my-memory-java/) by Mikhail Krestjaninoff.

When using the  `--memory`  option in `docker run` make sure the limit is larger (at least twice) than what you specify for `-Xmx`.

#### Offtopic: Using OOM Killer instead of GC

There is an interesting **JDK Enhancement Proposal (JEP)** by Aleksey Shipilev: [Epsilon GC]((http://openjdk.java.net/jeps/8174901). This JEP proposes to develop a GC that only handles memory allocation, but does not implement any actual memory reclamation mechanism.

This GC, combined with `--restart` (Docker restart policy) should theoretically allow supporting “Extremely short lived jobs” implemented in Java.

For ultra-performance-sensitive applications, where developers are conscious about memory allocations or want to create completely garbage-free applications - GC cycle may be considered an implementation bug that wastes cycles for no good reason. In such use case, it could be better to allow **OOM Killer** (Out of Memory) to kill the process and use Docker restart policy to restarting the process.

Anyway, **Epsilon GC** is not available yet, so it’s just an interesting theoretical use case for a moment.


## Building Java applications with Builder container

As you can probably see, in the previous step, I did not explain how I’ve created the application WAR file.

Of course, there is a Maven project file `pom.xml` which most Java developers should be familiar with. But, in order to actually build, you need to install the _same Java Build tools_ (JDK and Maven) on _every machine_, where you are building the application. You need to have the same versions, use the same repositories and share the same configurations. While's tt’s possible, managing different projects that rely on different tools, versions, configurations, and development environments can quickly become a nightmare.

What if you might also want to run a build on a clean machine that does not have Java or Maven installed? _What should you do?_

### Java Builder Container

Docker can help here too. With Docker, you can create and share portable development and build environments. The idea is to create a special **Builder** Docker image, that contains all tools you need to properly build your Java application, e.g.: JDK, Ant, Maven, Gradle, SBT or others.

To create a really useful **Builder** Docker image, you need to know well how you Java Build tools are working and how `docker build` invalidates build cache. Without proper design, you will end up with non-effective and slow builds.

### Running Maven in Docker

While most of these tools were created nearly a generation ago, they are still are very popular and widely used by Java developers.

Java development life is hard to imagine without some extra build tools. There are multiple Java build tools out there, but most of them share similar concepts and serve the same targets - resolve cumbersome package dependencies, and run different build tasks, such as, **compile, lint, test, package, and deploy**.

In this post, I will use [Maven](https://maven.apache.org), but the same approach can be applied to [Gradle](https://gradle.org/), [SBT](http://www.scala-sbt.org/), and other less popular Java Build tools.

It’s important to learn how your Java Build tool works and how can it's tuned. Apply this knowledge, when creating a **Builder** Docker image and the way you are running a **Builder** Docker container.

Maven uses the project level `pom.xml` file to resolve project dependencies. It downloads missing `JAR` files from private and public Maven repositories, and _caches_ these files for future builds. Thus, next time you run your build, it won’t download anything if your dependency had not been changed.

#### Official Maven Docker image: should you use it?

The Maven team provides an official [Docker images](https://hub.docker.com/r/_/maven/). There are multiple images (under different tags) that allow you to select an image that can answer your needs. Take a deeper look at the `Dockerfile` files and `mvn-entrypoint.sh` shell scripts when selecting Maven image to use.

There are two flavors of official Maven Docker images: regular images (JDK version, Maven version, and Linux distro) and `onbuild` images.

##### What is the official Maven image good for?

The official Maven image does a good job containerizing the Maven tool itself. The image contains some JDK and Maven version. Using such image, you can run Maven build on any machine without installing a JDK and Maven.

**Example:** running `mvn clean install` on local folder

```sh
$ docker run -it --rm --name my-maven-project -v "$PWD":/usr/src/app -w /usr/src/app maven:3.2-jdk-7 mvn clean install
```

Maven local repository, for official Maven images, is placed inside a Docker _data volume_. That means, all downloaded dependencies **are not part of the image** and **will disappear** once the Maven container is destroyed. If you do not want to download dependencies on every build, mount Maven repository Docker volume to some persistent storage (at least local folder on the Docker host). 

**Example:** running `mvn clean install` on local folder with properly mounted Maven local repository

```sh
$ docker run -it --rm --name my-maven-project -v "$PWD":/usr/src/app -v "$HOME"/.m2:/root/.m2 -w /usr/src/app maven:3.2-jdk-7 mvn clean install
```

Now, let's take a look at onbuild Maven Docker images.

##### What is Maven `onbuild` image?

Maven `onbuild` Docker image exists to _“simplify”_ developer’s life, allowing him/er skip writing a `Dockerfile`. Actually, a developer should write a `Dockerfile`, but it’s usually enough to have the single line in it:

```dockerfile
FROM maven:<versions>-onbuild
```

Looking into onbuild Dockerfile on the GitHub repository …

```dockerfile
FROM maven:<version>

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

ONBUILD ADD . /usr/src/app
ONBUILD RUN mvn install
```

… you can see several `Dockerfile` commands with the ONBUILD prefix. The `ONBUILD` tells Docker to postpone the execution of these build commands until building a new image that inherits from the current image.

In our example, two build commands will be executed, when you build the application `Dockerfile` created `FROM: maven:<version>-onbuild` :

- Add current folder (all files, if you are not using `.dockerignore`) to the new Docker image
- Run `mvn install` Maven target

The `onbuild` Maven Docker image is not as useful as the previous image.

First of all, it copies everything from the current repository, so do not use it without a properly configured `.dockerignore` file.

Then, think: _what kind of image you are trying to build?_

The new image, created from `onbuild`  Maven Docker image, includes JDK, Maven, application code (and potentially **all files** from current directory), and **all files** produced by Maven `install` phase (compiled, tested and packaged app; plus lots of build junk files you do not really need).

So, this Docker image contains everything, but, for some strange reason, does not contain a local Maven repository. I have no idea why the Maven team created this image.

> **Recommendation:** Do not use Maven onbuild images!

If you just want to use Maven tool, use non-onbuild image.

If you want to create proper Builder image, I will show you how to do this later in this post.

#### Where to keep Maven cache?

Official Maven Docker image chooses to keep Maven cache folder outside of the container, exposing it as a Docker _data volume_, using `VOLUME root/.m2` command in the `Dockerfile`. A Docker data volume is a directory within one or more containers that bypasses the Docker Union File System, in simple words: it’s not part of the Docker image.

What you should know about Docker _data volumes_:

- Volumes are initialized when a container is created.
- Data volumes can be shared and reused among containers.
- Changes to a data volume are made directly to the mounted endpoint (usually some directory on host, but can be some storage device too)
- Changes to a data volume will not be included when you update an image or persist Docker container.
- Data volumes persist even if the container itself is deleted.

So, in order to _reuse_ Maven _cache_ between different builds, mount a Maven _cache data volume_ to some persistent storage (for example, a local directory on the Docker host).

```sh
$ docker run -it --rm --volume "$PWD"/pom.xml://usr/src/app/pom.xml --volume "$HOME"/.m2:/root/.m2 maven:3-jdk-8-alpine mvn install
``` 

The command above runs the official Maven Docker image (Maven 3 and OpenJDK 8), mounts project `pom.xml` file into working directory and `$HOME"/.m2` folder for Maven _cache data volume_. Maven running inside this Docker container will download all required JAR files into host’s local

Maven running inside this Docker container will download all required `JAR` files into host’s local folder `$HOME/.m2`. Next time you create new Maven Docker container for the same `pom.xml` file and the same _cache_ mount, Maven will reuse the _cache_ and will download only missing or updated `JAR` files.

#### Maven Builder Docker image

First, let’s try to formulate _what is the **Builder** Docker image and what should it contain?_

> **Builder** is a Docker image that contains **everything** to allow you creating a reproducible build on any machine and at any point of time.

So, _what should it contain?_

- Linux shell and some tools - I prefer Alpine Linux
- JDK (version) - for the `javac` compiler
- Maven (version) - Java build tool
- Application source code and `pom.xml` file/s - it’s the application code `SNAPSHOT` at specific point of time; just code, no need to include a `.git` repository or other files
- Project dependencies (Maven local repository) - all `POM` and `JAR` files you need to build and test Java application, at any time, even offline, even if library disappear from the web

The **Builder** image captures code, dependencies, and tools at a specific point of time and stores them inside a Docker image. The **Builder** container can be used to create the application “binaries” on any machine, at any time and even without internet connection (or with poor connection).

Here is the sample `Dockerfile` for my demo **Builder**:

```dockerfile
FROM openjdk:8-jdk-alpine

# ----
# Install Maven
RUN apk add --no-cache curl tar bash

ARG MAVEN_VERSION=3.3.9
ARG USER_HOME_DIR="/root"

RUN mkdir -p /usr/share/maven && \
  curl -fsSL http://apache.osuosl.org/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz | tar -xzC /usr/share/maven --strip-components=1 && \
  ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

ENV MAVEN_HOME /usr/share/maven
ENV MAVEN_CONFIG "$USER_HOME_DIR/.m2"
# speed up Maven JVM a bit
ENV MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1"

ENTRYPOINT ["/usr/bin/mvn"]

# ----
# Install project dependencies and keep sources 

# make source folder
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# install maven dependency packages (keep in image)
COPY pom.xml /usr/src/app
RUN mvn -T 1C install && rm -rf target

# copy other source files (keep in image)
COPY src /usr/src/app/src
```

Let’s go over this `Dockerfile` and I will try to explain the reasoning behind each command.

- `FROM: openjdk:8-jdk-alpine` - select and freeze JDK version: OpenJDK 8 and Linux Alpine
- Install Maven
  - `ARG ...` - Use build arguments to allow overriding Maven version and local repository location (`MAVEN_VERSION` and `USER_HOME_DIR`) with `docker build --build-arg ...`
  - `RUN mkdir -p ... curl ... tar ...` - Download and install (`untar` and `ln -s`) Apache Maven
  - Speed up Maven JVM a bit: `MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1"`, read the following [post](https://zeroturnaround.com/rebellabs/your-maven-build-is-slow-speed-it-up/)
- `RUN mvn -T 1C install && rm -rf target` Download project dependencies:
  - Copy project `pom.xml` file and run `mvn install` command and remove build artifacts as far as I know, there is no Maven command that will let you download without installing)
  - This Docker image layer will be rebuilt only when project’s `pom.xml` file changes
- `COPY src /usr/src/app/src` - copy project source files (source, tests, and resources)

**Note:** if you are using [Maven Surefire plugin](http://maven.apache.org/surefire/maven-surefire-plugin) and want to have all dependencies for the offline build, make sure to [lock down Surefire test provider](http://maven.apache.org/surefire/maven-surefire-plugin/examples/providers.html).

When you build a new **Builder** version, I suggest you use a `--cache-from` option passing previous Builder image to it. This will allow you reuse any unmodified Docker layer and avoid obsolete downloads most of the time (if `pom.xml` did not change or you did not decide to upgrade Maven or JDK).

```sh
$ # pull latest (or specific version) builder image
$ docker pull myrep/mvn-builder:latest
$ # build new builder
$ docker build -t myrep/mvn-builder:latest --cache-from myrep/mvn-builder:latest .
``` 

##### Use Builder container to run tests

```sh
$ # run tests - test results are saved into $PWD/target/surefire-reports
$ docker run -it --rm -v "$PWD"/target:/usr/src/app/target myrep/mvn-builder -T 1C -o test
```

##### Use Builder container to create application WAR

```sh
$ # create application WAR file (skip tests) - $PWD/target/spring-boot-rest-example-0.3.0.war
$ docker run -it --rm -v $(shell pwd)/target:/usr/src/app/target myrep/mvn-builder package -T 1C -o -Dmaven.test.skip=true
```
## Summary

Take a look at images bellow:

```sh
REPOSITORY      TAG     IMAGE ID     CREATED        SIZE
sbdemo/run      latest  6f432638aa60 7 minutes ago  143 MB
sbdemo/tutorial 1       669333d13d71 12 minutes ago 1.28 GB
sbdemo/tutorial 2       38634e4d9d5e 3 hours ago    1.26 GB
sbdemo/builder  mvn     2d325a403c5f 5 days ago     263 MB
```

- `sbdemo/run:latest` - Docker image for demo runtime: Alpine, OpenJDK JRE only, demo WAR
- `sbdemo/builder:mvn` - **Builder** Docker image: Alpine, OpenJDK 8, Maven 3, code, dependency
- `sbdemo/tutorial:1` - Docker image created following first tutorial (just for reference)
- `sbdemo/tutorial:2` - Docker image created following second tutorial (just for reference)


## Bonus: Build flow automation

In this section, I will show how to use Docker build flow automation service to automate and orchestrate all steps from this post.

### Build Pipeline Steps

I'm going to use [Codefresh.io](https://codefresh.io) Docker CI/CD service (the company I'm working for) to create a **Builder** Docker image for Maven, run tests, create application WAR, build Docker image for application and deploy it to DockerHub.

The Codefresh automation flow `YAML` (also called *pipeline*) is pretty straight forward:

- it contains ordered list of steps
- each step can be of type: 
- - `build` - for `docker build` command
- - `push` - for `docker push`
- - `composition` - for creating environment, specified with `docker-compose`
- - `freestyle` (default if not specified) - for `docker run` command
- `/codefresh/volume/` _data volume_ (`git clone` and files generated by steps) is mounted into each step
- current working directory for each step is set to `/codefresh/volume/` by default (can be changed) 

For detailed description and other examples, take a look at the [documentation](https://docs.codefresh.io/docs/steps).

For my demo flow I've created following automation steps:

1. `mvn_builder` - create Maven **Builder** Docker image
2. `mv_test` - execute tests in **Builder** container, place test results into `/codefresh/volume/target/surefire-reports/` _data volume_ folder
3. `mv_package` - create application `WAR` file, place created file into `/codefresh/volume/target/` _data volume_ folder
4. `build_image` - build application Docker image with JRE and application `WAR` file
5. `push_image` - tag and push the application Docker image to DockerHub

Here is the full Codefresh `YAML`:

```yaml
version: '1.0'

steps:

  mvn_builder:
    type: build
    description: create Maven builder image
    dockerfile: Dockerfile.build
    image_name: <put_you_repo_here>/mvn-builder

  mvn_test:
    description: run unit tests 
    image: ${{mvn_builder}}
    commands:
      - mvn -T 1C -o test
  
  mvn_package:
    description: package application and dependencies into WAR 
    image: ${{mvn_builder}}
    commands:
      - mvn package -T 1C -o -Dmaven.test.skip=true

  build_image:
    type: build
    description: create Docker image with application WAR
    dockerfile: Dockerfile
    working_directory: ${{main_clone}}/target
    image_name: <put_you_repo_here>/sbdemo

  push_image:
    type: push
    description: push application image to DockerHub
    candidate: '${{build_image}}'
    tag: '${{CF_BRANCH}}'
    credentials:
      # set docker registry credentials in project configuration
      username: '${{DOCKER_USER}}'
      password: '${{DOCKER_PASS}}'
```
---

Hope, you find this post useful. I look forward to your comments and any questions you have.

---

_This is a **working draft** version. The final post version is published at [Codefresh Blog](https://codefresh.io/blog/java_docker_pipeline/) on March 22, 2017._