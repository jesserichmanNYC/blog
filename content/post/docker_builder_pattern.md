+++
date = "2016-01-14T16:14:47+02:00"
draft = false
title = "Docker Pattern: The Build Container"
tags = ["Docker", "pattern", "Dockerfile"]
categories = ["Development"]
+++

Let's say that you're developing a microservice in a compiled language or an interpreted language that requires some additional “build” steps to package and lint your application code. This is a useful docker pattern for the "build" container.

In our project, we're using Docker as our main deployment package: every microservice is delivered as a Docker image. Each microservice also has it’s own code repository (GitHub), and its own CI build job.

Some of our services are written in Java. Java code requires additional tooling and processes before you get working code. This tooling and all associated packages are depended from and not required when a compiled program is running.

We have been trying to develop a repeatable process and uniform environment for deploying our services. We believe it’s good to package Java tools and packages into containers too. It allows us to build a Java-based microservice on any machine, including CI, without any specific environment requirements: JDK version, profiling and testing tools, OS, Maven, environment variables, etc.

For every service, we have two(2) Dockerfiles: one for service runtime and the second packed with tools required to build the service. We usually name these files as `Dockerfile` and `Dockerfile.build`. We are using `-f, --file=""` flag to specify Dockerfile file name for `docker build` command.

Here is our `Dockerfile.build` file:

```sh
FROM maven:3.3.3-jdk-8

ENV GAIA_HOME=/usr/local/gaia/

RUN mkdir -p $GAIA_HOME
WORKDIR $GAIA_HOME

# speed up maven build, read https://keyholesoftware.com/2015/01/05/caching-for-maven-docker-builds/
# selectively add the POM file
ADD pom.xml $GAIA_HOME

# get all the downloads out of the way
RUN ["mvn","verify","clean","--fail-never"]

# add source
ADD . $GAIA_HOME

# run maven verify
RUN ["mvn","verify"]
```

As you can see, it’s a simple file with one little trick to speed up our Maven build.

Now, we have all the tools required to compile our service. We can run this Docker container on any machine without requiring to have JDK installed. We can run the same Docker container on a developer's laptop and on our CI server.

This trick greatly simplifies our CI process - we no longer require our CI to support any specific compiler, version, or tool. All we need is the Docker engine. Everything else, we bring ourselves.

> BYOT - Bring Your Own Tooling! :-)

In order to compile the service code, we need to build and run the **builder** container.

```sh
docker build -t build-img -f Dockerfile.build
docker create --name build-cont build-img
```

Once we’ve built the image and created a new container from this image, we have our service compiled inside the container. The only remaining task is to extract build artifacts from the container. We could use Docker volumes - this is one possible option. Actually, we like that the image we’ve created, contains all the tools and build artifacts inside it. It allows us to get any build artifacts from this image at anytime, just by creating a new container from it.

To extract our build artifacts, we are using `docker cp` command. This command copies files from the container to the local file system.

Here is how we are using this command:

```sh
docker cp build-cont:/usr/local/gaia/target/mgs.war ./target/mgs.war
```

As a result, we have a compiled service code, packaged into single WAR file. We get exactly the same WAR file on any machine just by running our **builder** container, or by rebuilding the **builder** container against the same code commit (using Git tag or specific commit ID) on any machine.

We can now create a Docker image with our service and required runtime, which is usually some version of JRE and servlet container.

Here is our `Dockerfile` for the service. It's an image with Jetty JRE8 and our service WAR file.

```sh
FROM jetty:9.3.0-jre8

RUN mkdir -p /home/jetty && chown jetty:jetty /home/jetty

COPY ./target/*.war $JETTY_BASE/webapps/
```

By running `docker build .`, we have a new image with our newly “built” service.

## The Recipe:

- Have one `Dockerfile` with all tools and packages required to build your service. Name it `Dockerfile.build` or give it a name you like.
- Have another `Dockerfile` with all packages required to run your service.
- Keep both files with your service code.
- Build a new **builder** image, create a container from it and extract build artifacts, using volumes or `docker cp` command.
- Build the service image.
- That's all folks!

## Summary

In our case, Java-based service, the difference between **builder** container and service container is huge. Java JDK is much bigger package than JRE: it also requires all X Window packages installed inside your container. For the runtime, you can have a slim image with your service code, JRE, and some basic Linux packages, or even start from `scratch`.
