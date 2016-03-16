+++
date = "2016-03-07T16:39:00+02:00"
draft = false
title = "Testing Strategies for Docker Containers"
tags = ["Docker", "testing", "integration test", "Dockerfile"]
categories = ["Development"]
+++

Congratulations! You know how to build a Docker image and are able to compose multiple containers into a meaningful application. Hopefully, you've already created a Continuous Delivery pipeline and know how to push your newly created image into production or testing environment.

> Now, the question is - *How do we test our Docker containers?*

There are multiple testing strategies we can apply. In this post, I'll highlight them presenting benefits and drawbacks for each.

## The "Naive" approach

This is the default approach for most people. It relies on a CI server to do the job. When taking this approach, the developer is using Docker as a package manager, a better option than the **jar/rpm/deb** approach.
The CI server compiles the application code and executes tests (unit, service, functional, and others). The build artifacts are reused in Docker **build** to produce a new image. This becomes a core deployment artifact. The produced image contains not only application "binaries", but also a required runtime including all dependencies and application configuration.

We are getting application portability, however, we are loosing the development and testing portability. We're not able to reproduce exactly the same development and testing environment outside the CI. To create a new test environment we'll need to setup the testing tools (correct versions and plugins), configure runtime and OS settings, and get the same versions of test scripts as well as perhaps, the test data.

![The Naive Testing Strategy](/img/naive.png)

To resolve these problems leads us to the next one.

## App & Test Container approach

Here, we try to create a single bundle with the application "binaries" including required packages, testing tools (specific versions), test tools plugins, test scripts, test environment with all required packages.

The benefits of this approach:

- We have a repeatable test environment - we can run exactly the same tests using the same testing tools - in our CI, development, staging, or production environment
- We capture test scripts at a specific point in time so we can always reproduce them in any environment
- We do not need to setup and configure our testing tools - they are part of our image

This approach has significant drawbacks:

- Increases the image size - because it contains testing tools, required packages, test scripts, and perhaps even test data
- Pollutes image runtime environment with test specific configuration and may even introduce an unneeded dependency (required by integration testing)
- We also need to decide what to do with the test results and logs; how and where to export them

Here's a simplified `Dockerfile`. It illustrates this approach.

```dockerfile
FROM "<bases image>":"<version>"

WORKDIR "<path>"

# install packages required to run app and tests
RUN apt-get update && apt-get install -y \
    "<app runtime> and <dependencies>" \  # add app runtime and required packages
    "<test tools> and <dependencies>" \     # add testing tools and required packages
    && rm -rf /var/lib/apt/lists/*

# copy app files
COPY app app
COPY run.sh run.sh

# copy test scripts
COPY tests tests

# copy "main" test command
COPY test.sh test.sh

# ... EXPOSE, RUN, ADD ... for app and test environment

# main app command
CMD [run.sh, "<app arguments>"]

# it's not possible to have multiple CMD commands, but this is the "main" test command
# CMD [/test.sh, "<test arguments>"]
```
[Dockerfile](https://gist.github.com/alexei-led/cbb3d46fcf422a24aacd)

![App & Test Container](/img/app_test.png)

There has to be a better way for in-container testing and there is.

## Test Aware Container Approach

Today, Docker's promise is **"Build -> Ship -> Run"** - build the image, ship it to some registry, and run it anywhere. IMHO there's a critical missing step - **Test**. The right and complete sequence should be **:Build -> Test -> Ship -> Run**.

Let's look at a "test-friendly" Dockerfile syntax and extensions to Docker commands. This important step could be supported natively. It's not a real syntax, but bear with me. I'll define the "ideal" version and show how to implement something that's very close.

```
ONTEST [INSTRUCTION]
```

Let's define a special `ONTEST` instruction, similar to existing [`ONBUILD`](https://docs.docker.com/engine/reference/builder/#onbuild) instruction. The `ONTEST` instruction adds a trigger instruction to the image to be executed at a later time when the image is tested. Any build instruction can be registered as a trigger.

The `ONTEST` instruction should be recognized by a new `docker test` command.

```
docker test [OPTIONS] IMAGE [COMMAND] [ARG...]
```

The `docker test` command syntax will be similar to `docker run` command, with one significant difference: a new "testable" image will be automatically generated and even tagged with `<image name>:<image tag>-test` tag ("test" postfix added to the original image tag). This "testable" image will generated `FROM` the application image, executing all build instructions, defined after `ONTEST` command and executing `ONTEST CMD` (or `ONTEST ENTRYPOINT`).
The `docker test` command should return a non-zero code if any tests fail. The test results should be written into an automatically generated `VOLUME` that points to `/var/tests/results` folder.

Let's look at a modified `Dockerfile` below - it includes the new proposed `ONTEST` instruction.

```dockerfile
FROM "<base image>":"<version>"

WORKDIR "<path>"

# install packages required to run app
RUN apt-get update && apt-get install -y \
    "<app runtime> and <dependencies>" \  # add app runtime and required packages
    && rm -rf /var/lib/apt/lists/*

# install packages required to run tests   
ONTEST RUN apt-get update && apt-get install -y \
           "<test tools> and <dependencies>"    \     # add testing tools and required packages
           && rm -rf /var/lib/apt/lists/*

# copy app files
COPY app app
COPY run.sh run.sh

# copy test scripts
ONTEST COPY tests tests

# copy "main" test command
ONTEST COPY test.sh test.sh

# auto-generated volume for test results
# ONTEST VOLUME "/var/tests/results"

# ... EXPOSE, RUN, ADD ... for app and test environment

# main app command
CMD [run.sh, "<app arguments>"]

# main test command
ONTEST CMD [/test.sh, "<test arguments>"]
```
[Dockerfile](https://gist.github.com/alexei-led/4f39cca8a03b1503978a)

![Test Aware Container](/img/test_aware.png)

### Making "Test Aware Container" Real

We believe Docker should make `docker-test` part of the container management lifecycle. There is a need to have a simple working solution today and I'll describe one that's very close to the ideal state.

As mentioned before, Docker has a very useful `ONBUILD` instruction. This instruction allows us to trigger another build instruction on succeeding builds. The basic idea is to use `ONBUILD` instruction when running `docker-test` command.

The flow executed by `docker-test` command:

1. `docker-test` will search for `ONBUILD` instructions in application `Dockerfile` and will ...
2. generate a temporary `Dockerfile.test` from original `Dockerfile`
2. execute `docker build -f Dockerfile.test [OPTIONS] PATH` with additional options supported by `docker build` command: `-test` that will be automatically appended to `tag` option
3. If build is successful, execute `docker run -v ./tests/results:/var/tests/results [OPTIONS] IMAGE:TAG-test [COMMAND] [ARG...]`
4. Remove `Dockerfile.test` file

Why not create a new `Dockerfile.test` without requiring the `ONBUILD` instruction?

Because in order to test right image (and tag) we'll need to keep `FROM` always updated to **image:tag** that we want to test. This is not trivial.

There is a limitation in the described approach - it's not suitable for "onbuild" images (images used to automatically build your app), like [Maven:onbuild](https://hub.docker.com/_/maven/)

Let's look at a simple implementation of `docker-test` command. It highlights the concept: the `docker-test` command should be able to handle `build` and `run` command options and be able to handle errors properly.

```sh
#!/bin/bash
image="app"
tag="latest"

echo "FROM ${image}:${tag}" > Dockerfile.test &&
docker build -t "${image}:${tag}-test" -f Dockerfile.test . &&
docker run -it --rm -v $(pwd)/tests/results:/var/tests/results "${image}:${tag}-test" &&
rm Dockerfile.test
```

Let's focus on the most interesting and relevant part.

## Integration Test Container

Let's say we have an application built from tens or hundreds of microservices. Let's say we have an automated CI/CD pipeline, where each microservice is built and tested by our CI and deployed into some environment (testing, staging or production) after the build and tests pass. Pretty cool, eh?
Our CI tests are capable of testing each microservice in isolation - running unit and service tests (or API contract tests). Maybe even micro-integration tests - tests run on subsystem are created in ad-hoc manner (for example with `docker compose` help).

This leads to some issues that we need to address:

- What about real integration tests or long running tests (like performance and stress)?
- What about resilience tests ("chaos monkey" like tests)?
- Security scans?
- What about test and scan activities that take time and should be run on a fully operational system?

There should be a better way than just dropping a new microservice version into production and tightly monitoring it for a while.

There should be a special **Integration Test Container**. These containers will contain only testing tools and test artifacts: test scripts, test data, test environment configuration, etc. To simplify orchestration and automation of such containers, we should define and follow some conventions and use metadata labels (Dockerfile `LABEL` instruction).  

### Integration Test Labels

- **test.type** - test type; default `integration`; can be one of: `integration`, `performance`, `security`, `chaos` or any text; presence of this label states that this is an **Integration Test Container**
- **test.results** - `VOLUME` for test results; default `/var/tests/results`
- **test.XXX** - any other test related metadata; just use **test.** prefix for label name

### Integration Test Container

The **Integration Test Container** is just a regular Docker container. Tt does not contain any application logic and code. Its sole purpose is to create repeatable and portable testing. Recommended content of the **Integration Test Container**:

- *The Testing Tool* - Phantom.js, Selenium, Chakram, Gatling, ...
- *Testing Tool Runtime* - Node.js, JVM, Python, Ruby, ...
- *Test Environment Configuration* - environment variables, config files, bootstrap scripts, ...
- *Tests* - as compiled packages or script files
- *Test Data* - any kind of data files, used by tests: json, csv, txt, xml, ...
- *Test Startup Script* - some "main" startup script to run tests; just create `test.sh` and launch the testing tool from it.

**Integration Test Containers** should run in an operational environment where all microservices are deployed: testing, staging or production. These containers can be deployed exactly as all other services. They use same network layer and thus can access multiple services; using selected service discovery method (usually DNS). Accessing multiple services is required for real integration testing - we need to simulate and validate how our system is working in multiple places. Keeping integration tests inside some application service container not only increases the container footprint but also creates an unneeded dependency between multiple services. We keep all these dependencies at the level of the **Integration Test Container**. Once our tests (and testing tools) are packaged inside the container, we can always rerun the same tests on any environment including the developer machine. You can always go back in time and rerun a specific version of **Integration Test Container**.

![Integration Test Container](/img/int_test.png)


WDYT? Your feedback, particularly on standardizing the `docker-test` command, is greatly appreciated.
