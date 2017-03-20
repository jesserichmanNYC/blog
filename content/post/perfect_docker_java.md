+++
date = "2017-03-07T18:00:00+02:00"
draft = true
title = "Crafting perfect Java Docker build flow"
tags = ["docker", "tutorial", "devops", "hacks", "java", "maven"]
categories = ["DevOps"]
+++

## TL;DR

**Ask** 
> **Question:** *What is the bare minimum I need to **build**, **test** and **run** my Java application?*

**How**
> **Do:** Create a separate Docker image for each step and optimize the way you are running it.

![Duke and Container](/img/duke_docker.png)

## Introduction

I've started to work with Java from 1998, and for a long time, it was my main language. It was a long love–hate relationship. 
During my work career, I wrote a lot of code lines in Java. Despite that fact, I'm not really a fan of writing microservices in Java and putting Java applications into Docker containers. I think that Java is not the best choice for writing microservices. But this is a story for another post, yet to be written.

Sometimes you have to work with Java: maybe Java is your favorite language and you do not want to learn a new one, or you have a lot of legacy code that you need to maintain, or your company decided on Java and you have no other option. 
Whatever reason you have to marry Java with Docker, you better do it properly.

In this post, I will try to show you how you can create a perfect Java-to-Docker build pipeline to effectively produces small, efficient and secure Docker images. 

## Attention

**Beware:** there are many "Docker for Java developers" tutorials out there, that encourage very bad practices. 

For example: 
- [Spark and Docker tutorial](https://sparktutorials.github.io/2015/04/14/getting-started-with-spark-and-docker.html)
- [Introducing Docker for Java Developers](https://examples.javacodegeeks.com/devops/docker/introduction-docker-java-developers/) 
- [Using Java with Docker Engine](http://www.developer.com/java/data/using-java-with-docker-engine.html)
- and many more ...

These are examples of awful tutorials. 

> Make yourself a favor and do not follow these tutorials!

## What should you know about Docker?

First, take some time and try to understand what stands behind popular Docker technology. Any reasonable developer can understand it - it's not a quantum mechanics.

Docker is a very convenient interface that wraps Linux container technology. It allows creating a properly isolated Linux processes from `tar` archives that contain all required files and some metadata. A good place to learn about Docker internals is [Understanding Docker](https://docs.docker.com/engine/understanding-docker/) article.

## Running Java application

Since Docker container is just an isolated process, you need to package into your Java Docker image only files, that are required to run your application. And _what are these files?_

First, you need Java Runtime Environment, aka **JRE**. **JRE** is a software package, that contains what is required to run a Java program. It includes a Java Virtual Machine (**JVM**) implementation together with an implementation of the Java Class Library. 

I personally recommend using [OpenJDK](http://openjdk.java.net/) JRE. OpenJDK is licensed under [GPL](https://en.wikipedia.org/wiki/GNU_General_Public_License) with [Classpath Exception](http://www.gnu.org/software/classpath/license.html). The *Classpath Exception* part is important. This license allows using OpenJDK with a software of any license, not just the GPL. In particular, you can use OpenJDK with proprietary software without disclosing its code.
If you decide to go with Oracle JDK/JRE, please read the following post before: [Running Java on Docker? You're Breaking the Law](http://blog.takipi.com/running-java-on-docker-youre-breaking-the-law/).

Since rare java application can be developed with standard library only, you might need to add 3rd party Java libraries, you are using for running your application and application compiled bytecode, as Java classes or packaged in _JAR_ archives. If you are using native code, you will need to add corresponding native libraries/packages too.

Now, think:
 - _Do you really need all Ubuntu or Debian packages alongside with your Java application? 
 - _Do you want to patch security holes in packages you do not use?_
 - _Do you want to spend network and storage on unused files?_

Some might say: _"but if all your images share same Docker layers, you download them just once, right?"_. True, but it can be far from a reality. 
Usually, you have lots of different images: some you built lately, others a long time ago, others just download from DockerHub and use. All these images have a different base image or a different version of the base image, so they do not share a lot. You need to invest a lot to align all images to same base image and then spend lots of time updating these images for no reason.

Some might say: _"but, who cares about image size? we download them just once and run forever"_. IMHO Docker image size is important. 
The size has impact on 
- network latency - need to transfer it over wires 
- storage - need to store all these bytes somewhere
- service availability and elasticity - when using Docker scheduler, like Kubernetes, Swarm, DC/OS or other (scheduler can move containers between hosts)
- security - do you really, I mean **really** need `libpng` package with all its [CVE vulnerabilities](https://www.cvedetails.com/vulnerability-list/vendor_id-7294/Libpng.html) in Java application?
- development agility - small Docker images == faster build time and faster deployment

Without taking care, Java Docker images tends to grow to enormous sizes. I've met Java image of 3GB size, where the actual application and all required JAR libraries took only 150MB. 

Consider using [Alpine Linux image](https://hub.docker.com/_/alpine/), which is only a 5MB image, as a base Linux image. To create a **Builder** image, add required JDK and Java Build tools. For **Runtime** image adding JRE should be sufficient in most cases. Lots of ["Official Docker images"](https://github.com/docker-library/official-images) have Alpine-based flavor. 

**Note**: Many, but not all Linux packages have versions compiled with `musl libc` C runtime library. Sometimes you want to use a package that is compiled with `glibc` (GNU C runtime library). Take a look at [Alpine GNU C library (glibc) Docker image](). This image is based on Alpine Linux image and contains `glibc` to enable proprietary projects compiled against `glibc` (e.g. OracleJDK, Anaconda) work on Alpine.

Usually, you also need to expose some kind of interface to access your Java application, that runs in Docker container. 
When you deploy Java application with Docker container, the default Java deployment model is changing. Originally, Java server-side deployment assumed that you have already pre-configured Java Web Server (Tomcat, WebLogic, JBoss, or other) and you are deploying an application **WAR** (Web Archive) packaged Java application to this server, alongside with other applications. Lots of tools were developed around this concept, allowing you to update running application without stopping a server, routing traffic to the new application, resolving possible class loading conflicts and more. With Docker-based deployment, you do not need these tools anymore, you also do not need fat enterprise ready Java Application servers. The only thing that you need is a stable and scalable network server that can serve your API over HTTP/TCP or other protocol of your choice. Search Google for "embedded java server" and take one that you like most. 

For this demo, I forked [Spring Boot REST example](https://github.com/khoubyari/spring-boot-rest-example) and modified it a bit. This is my [fork](https://github.com/alexei-led/spring-boot-rest-example) GitHub repository.

### Building Application Docker image

In order to run this demo, I need JRE, compiled and packaged Java application and all 3rd party libraries. 
The `Dockerfile` bellow is used to run the demo. It is based on slim Alpine Linux with OpenJDK JRE and contains single application WAR file with all dependencies embedded into it.

```dockerfile
# Base Alpine Linux based image with OpenJDK JRE only
FROM openjdk:8-jre-alpine

# copy application WAR (with libraries inside)
COPY target/spring-boot-*.war /app.war

# specify default command
CMD ["/usr/bin/java", "-jar", "-Dspring.profiles.active=test", "/app.war"]
```

To build the Docker image, execute:

```sh
$ docker build -t blog/sbdemo:latest .
```

Running `docker history` command on created Docker image, it's possible to see that the image contains
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

### Running Application Docker container

In order to run the demo application, run following command:

```sh
$ docker run -d --name demo-default -p 8090:8090 -p 8091:8091 blog/sbdemo:latest
```

Check, that application is up and running (I'm using `httpie` tool here):

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

One thing you need to know about Java process memory allocation, is that in reality, it consumes more physical memory than specified with the `-Xmx` JVM option. The `-Xmx` option specifies only _maximum_ Java heap size. But Java process is a regular Linux process and what is interesting is how much actual _physical memory_ this process is consuming. Or in other words - _what is the **R**esident **S**et **S**ize (**RSS**) value for running Java process?_.

Theoretically, in case of a Java application, required `RSS` size can be calculated by:
```
RSS = Heap size + MetaSpace + OffHeap size
```
where OffHeap consists of thread stacks, direct buffers, mapped files (libraries and jars) and JVM code itself.

There is a very good post about this topic: [Analyzing java memory usage in a Docker container](http://trustmeiamadeveloper.com/2016/03/18/where-is-my-memory-java/) by Mikhail Krestjaninoff.

So, when you are running Java application in Docker container and want to set limits on Java memory, make sure that memory limits (`--memory`) for `docker run` commands should be bigger, than one you specify for `-Xmx` option.


#### Offtopic: Using OOM Killer instead of GC

There is an interesting **JDK Enhancement Proposal** (**JEP**) by Aleksey Shipilev: [Epsilon GC](http://openjdk.java.net/jeps/8174901). This JEP proposes to develop a GC that only handles memory allocation, but does not implement any actual memory reclamation mechanism. 

This feature, combined with `--restart` (Docker restart policy) should theoretically allow supporting "Extremely short lived jobs" implemented in Java. 
For ultra-performance-sensitive applications, where developers are conscious about memory allocations or want to create completely garbage-free applications - GC cycle may be considered an implementation bug that wastes cycles for no good reason. In such use case, its could be better to allow **OOM Killer** (Out of Memory) to kill the process and use Docker restart policy to restarting the process.

Anyway **Epsilon GC** is not available yet, so it's just an interesting theoretical use case for a moment.


## Building Java application with Builder container

As you can probably see, in the previous step, I did not explain how I've created the application WAR file. 
Of cause there is a Maven project file `pom.xml` and every Java developer knows how to build it. But, in order to do so, you need to install *same Java Build tools* (JDK and Maven) on *every machine*, where you are building the application. You need to have same versions, use same repositories and share same configurations. It's possible, but if you have different projects and need different tools versions and configurations, the development environment management can quickly become a nightmare. You may also need to run your build on a clean machine that does not have Java or Maven installed, _what should you do?_

And Docker can help here too. With Docker, you can create and share portable development and build environments. The idea is to create a special **Builder** Docker image, that contains all tools you need to properly build your Java application, e.g.: JDK, Ant, Maven, Gradle, SBT or others.

To create a really useful **Builder** Docker image, you need to know well how you Java Build tools are working and how `docker build` invalidates build cache. Without proper design, you will end up with non-effective and slow builds.

### Maven in Docker

While most of these tools have been created nearly a generation ago, they still are very popular and widely used by Java developers. 

Java developers cannot imagine their life without some additional build tool. There are multiple Java build tools out there, but most of them share similar concepts and serve same targets - resolve cumbersome package dependencies, and run different build tasks, for example, **_compile, lint, test, package, and deploy_**. 

In this post, I will use [Maven](https://maven.apache.org), but the same approach can be applied to [Gradle](https://gradle.org/), [SBT](www.scala-sbt.org/) and other less popular Java Build tools.

It's important to learn how is your Java Build tool working and how can it be tuned. Apply this knowledge, when creating a **Builder** Docker image and the way you are going to run it.

Maven uses project level `pom.xml` file to resolves project dependencies. It downloads missing `JAR` files from private and public Maven repositories, _caches_ these files for future builds. Thus next time you will run your build, it won't download anything if your dependency had not been changed. 

#### Official Maven Docker image: should you use it?

Maven team provides an official [Docker image](https://hub.docker.com/r/_/maven/). There are multiple tags that allows you to select an image that can answer your needs. Take a deeper look at `Dockerfile` files and `mvn-entrypoint.sh` shell script and try to understand what each image is doing. 
There are two flavors of official Maven Docker images: regular images (JDK version, Maven version and Linux distro) and `onbuild` images. 

_What is official Maven image good for?_

Official Maven image does a good work containerizing Maven tool itself. Teh image contains some JDK and Maven version. Using such image, you can run Maven build on any machine without installing JDK or Maven.

**Example:** running `mvn clean install` on local folder

```sh
$ docker run -it --rm --name my-maven-project -v "$PWD":/usr/src/app -w /usr/src/app maven:3.2-jdk-7 mvn clean install
```

Maven local repository, for official Maven images, is placed inside a Docker *volume*. That means, all downloaded dependencies **are not part of this image** and will **disappear** once Maven container is destroyed. You need to mount Maven repository Docker volume to some persistent storage (at least local folder on host), if you do not want to download dependencies on every build.

**Example:** running `mvn clean install` on local folder with properly mounted Maven local repository

```sh
$ docker run -it --rm --name my-maven-project -v "$PWD":/usr/src/app -v "$HOME"/.m2:/root/.m2 -w /usr/src/app maven:3.2-jdk-7 mvn clean install
```

Now, lets take a look at `onbuild` Maven Docker images.

_What are these `onbuild` images?_

`onbuild` Docker image exists to "simplify" developer's life, allowing him/er not to write a `Dockerfile`. Actually a developer should write a `Dockerfile`, but it's usually enough to have single line in it: `FROM maven:<versions>-onbuild`.

Looking into `onbuild` `Dockerfile` on the [GitHub repository](https://github.com/carlossg/docker-maven) ...

```dockerfile
FROM maven:<version>

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

ONBUILD ADD . /usr/src/app
ONBUILD RUN mvn install
```

... you can see several `Dockerfile` commands with `ONBUILD` prefix. The `ONBUILD` tells Docker to postpone execution of these build commands until building a new image that inherits from the current image.

So, 2 build commands will be executed, when you build your application `Dockerfile` created `FROM: maven:<version>-onbuild`: 

1. Add current folder (all files, if you are not using `.dockerignore`) to the new Docker image
2. Run `mvn install` target

This `onbuild` Maven Docker image is not as useful as previous image. 
First, it copies everything from current repository, so do not use it without properly configured `.dockerignore` file. 
Second, think: _what kind of image you are trying building?_

The new image includes JDK, Maven version, application code (and potentially **all files** from current directory), and **all files** produced by Maven `install` phase (can be compiled, tested and packaged app; plus lots of build junk files you do not need).

So, this Docker image contains everything, but, for some strange reason, does not contain local repository. I have no idea why Maven team created this image.

> Do not use Maven `onbuild` images!

If you just want to use Maven tool, use non-`onbuild` image. If you want to create proper **Builder** image, I will show you how to do this later in this post.
 

#### Where to keep Maven cache?

Official Maven Docker image choose to keep Maven cache folder outside of container, exposing it as a Docker data _volume_, using `VOLUME root/.m2` command in the `Dockerfile`. A Docker _data volume_ is a directory within one or more containers that bypasses the Docker Union File System, in simple words: it's not part of the Docker image. 

What you should know understand Docker _data volumes_:

- Volumes are initialized when a container is created. 
- Data volumes can be shared and reused among containers.
- Changes to a data volume are made directly to the mounted endpoint (usually some directory on host, but can be other device too)
- Changes to a data volume will not be included when you update an image or persist Docker container.
- Data volumes persist even if the container itself is deleted.

So, in order to _reuse_ Maven _cache_ between different builds, mount a Maven cache _data volume_ to some persistent storage (at least local folder).

```sh
$ docker run -it --rm --volume "$PWD"/pom.xml://usr/src/app/pom.xml --volume "$HOME"/.m2:/root/.m2 maven:3-jdk-8-alpine mvn install
``` 

The command above runs the official Maven Docker image (Maven 3 and OpenJDK 8 on Alpine Linux), mounts project `pom.xml` file into working directory and `"$HOME"/.m2` folder for Maven _cache_ data volume. Maven running inside this Docker container will download all required JAR files into host's local folder `$HOME/.m2`. Next time you create new Maven Docker container for same `pom.xml` file and same _cache_ mount, Maven will reuse this _cache_ and will download only missing or updated JAR files.


#### Maven Builder Docker image

First, let's try to formulate _what is the **Builder** Docker image_ and _what should it contain?_ 

> **Builder** is a Docker image that contains **everything** to allow you creating a reproducible build on any machine and at any point of time.

So, _what should it contain?_

* Linux shell and some tools - consider using Alpine Linux
* JDK (version) - you need `javac` compiler, right?
* Maven (version) - Java build tool itself
* Application source code and `pom.xml` file/s - it's a code _SNAPSHOT_ at specific point of time; just code, no need to include `.git` repository or other files
* Project dependencies (Maven local repository) - all `pom` and `jar` files you need to build and test your application, at any time, even offline, even if library disappear from the web

The **Builder** captures code, dependency and tools at specific point of time and stores them inside a Docker image. The **Builder** container can be used to create the application "binaries" on any machine, at any time and even without internet connection (or with poor connection).

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

Let's go over this `Dockerfile ` and I will try to explain reasoning behind each command.

1. `FROM: openjdk:8-jdk-alpine` - select and freeze JDK version: OpenJDK 8 and Linux Alpine
2. Install Maven
    - `ARG ...` - Use build arguments to allow to override Maven version and local repsitory location (`MAVEN_VERSION` and `USER_HOME_DIR`) with `docker build --build-arg ...`
    - `RUN mkdir -p ... curl ... tar ...`- Download and install (`untar` and `ln -s `) Apache Maven 
    - Speed up Maven JVM a bit: `MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1"`, read following [post](https://zeroturnaround.com/rebellabs/your-maven-build-is-slow-speed-it-up/)
3. `RUN mvn -T 1C install && rm -rf target` Download project dependencies:
    - Copy project `pom.xml` file and run `mvn install` command and remove build artifacts (I did not find Maven command only to download prject dependencies without building anything)
    - This Docker image layer will be rebuild only when project's `pom.xml` file changes
4. `COPY src /usr/src/app/sr` - copy project source files (source, tests and resources)

**Note:** if you are using Maven [Surefire plugin](http://maven.apache.org/surefire/maven-surefire-plugin) and want to have all dependencies for offline build, make sure to [lock down Surefire test provider](http://maven.apache.org/surefire/maven-surefire-plugin/examples/providers.html).

When you build a new **Builder** version, I suggest you use a `--cache-from` option passing previous **Builder** image to it. This will allow you reuse any unmodified Docker layer and avoid obsolete downloads most of the time (if `pom.xml` did not change or you did not decide to upgrade Maven or JDK).

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


### Build flow automation

In this section, I will show how to use Docker build flow automation service to automate and orchestrate all steps from this post.

I'm going to use [Codefresh.io](https://codefresh.io) Docker CI/CD service (the company I'm working for) to create a **Builder** Docker image for Maven, run tests, create application WAR, build Docker image for application and deploy it to DockerHub.

The Codefresh automation flow `YAML` (also called *pipeline*) is pretty straight forward.
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