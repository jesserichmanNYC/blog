+++
date = "2016-01-14T16:14:47+02:00"
draft = false
title = "Docker Pattern: The Build Container"
tags = ["Docker", "pattern", "Dockerfile"]
categories = ["Development"]
+++

If you are developing a microservice in compiled language or even interpreted language that requires some additional “build” steps to package and lint your application code, I would like to share with you one pretty useful pattern.

In our project, we are using Docker as our main deployment package: every microservice is delivered as a Docker image. Each microservice also has it’s own code repository (we are using GitHub) and its own CI build job.

Some of our services are written in Java. And Java code requires additional tooling and process, before you get working code. These tooling and all additional packages they are depended from are not required when compiled program is running.

Since, we have been trying to have a repeatable and uniform environment for all our services, we think it’s a good idea to package Java tools and packages into container too. It allows us to be able to build Java-based microservice on any machine, including CI, without any specific environment requirements, like: JDK version, profiling and testing tools, OS, Maven, environment variables, and similar.

Thus, for every service, we have two Dockerfiles: one for service runtime and other packed with tools required to build service code. We usually name these files as `Dockerfile` and `Dockerfile.build`.
We are using `-f, --file=""` flag to specify Dockerfile file name for `docker build` command.

Here is our `Dockerfile.build` file:

```sh
FROM maven:3.3.3-jdk-8

ENV GAIA_HOME=/usr/local/gaia/

RUN mkdir -p $GAIA_HOME
WORKDIR $GAIA_HOME

# speedup maven build, read https://keyholesoftware.com/2015/01/05/caching-for-maven-docker-builds/
# selectively add the POM file
ADD pom.xml $GAIA_HOME

# get all the downloads out of the way
RUN ["mvn","verify","clean","--fail-never"]

# add source
ADD . $GAIA_HOME

# run maven verify
RUN ["mvn","verify"]
```

As you can see, it’s a pretty simple file, with one little trick we are using to speedup our Maven build.

Now, we have all tools, that are required to compile our service. We can run this Docker container on any machine, without requiring even to have any JDK installed. We can run same Docker container on developer laptops and on our CI server.

Actually, this trick also greatly simplifies our CI process - we do not require CI to support any specific compiler,  version or tool; all we need is Docker engine, all other stuff we are bringing by ourselves.

> BYOT - Bring Your Own Tolling! :-)

In order to compile the service code, we need to build and run the **builder** container.

```sh
docker build -t build-img -f Dockerfile.build
docker create --name build-cont build-img
```

Once we’ve built the image and created a new container from this image, we already have our service compiled inside the container. Now the remaining task is to extract build artifacts from the container. We could use Docker volumes - this is one possible option. But actually we like the fact, that image, we’ve created, contains all tools and build artifacts inside it. It allows us to get any build artefacts from this image at anytime, by just creating a new container from it.

So, to extract our build artifacts, we are using `docker cp` command. This command allows to copy files from container to local file system.

Here is how we are using this command:

```sh
docker cp build-cont:/usr/local/gaia/target/mgs.war ./target/mgs.war
```

As a result, we have a compiled service code packaged into single WAR file. We can get exactly same WAR file on any machine, by just running our **builder** container, or by rebuilding the **builder** container against same code commit (using Git tag or specific commit ID) on any machine.

Now we can create a Docker image with our service and required runtime, which is usually some version of JRE and servlet container.

Here is our `Dockerfile` for the service. It's an image with Jetty, JRE8 and our service WAR file.

```sh
FROM jetty:9.3.0-jre8

RUN mkdir -p /home/jetty && chown jetty:jetty /home/jetty

COPY ./target/*.war $JETTY_BASE/webapps/
```

By running `docker build .`, we can have a new image with our newly “built” service.

## The Reciept

- Have one `Dockerfile` with all tools and packages required to build your service. Name it `Dockerfile.build` or give it other name you like.
- Have another `Dockerfile` with all packages required to run your service.
- Keep both above files alongside with your service code.
- Build a new **builder** image, create a container from it and extract build artifacts, either using volumes or `docker cp` command.
- Build the service image.
- That's all, falks!

## Summary

In our case, Java-based service, the difference between **builder** container and service container is huge. Java JDK is much bigger package, than JRE: it's also requires to have all X Window packages installed inside your container. For the runtime, you can have a pretty slim image with your service code, JRE and some basic Linux packages, or even start from `scratch`.
