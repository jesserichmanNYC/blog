+++
date = "2016-03-07T16:39:00+02:00"
draft = false
title = "Testing Strategies for Docker Containers"
tags = ["Docker", "testing", "integration test", "Dockerfile"]
categories = ["Development"]
+++

So, you know how to build a Docker image and you are able to compose multiple containers into some meaningful application. Congratulations! You are in the right direction.
Hopefully you've already created a Continuous Delivery pipeline and know how to push your newly created image into production or testing environment.

> Now, the question is - *How do you test your Docker containers?*

There are multiple testing strategies you can apply. In this post I will try to review most of them, presenting benefits and drawbacks for each strategy.

## The "Naive" - Testing Strategy

This is the default approach, most people are taking. It relays on CI server to do the job. When taking this approach, the developer is using Docker as a package manager, kind of a better replacement for previously used **jar/rpm/deb** approach.
The CI server compiles the application code and executes tests (unit, service, functional and others). The build artifacts are reused in Docker **build** to produce a new image, that becomes a core deployment artifact. The produced image contains not only application "binaries", but also a required runtime, all dependencies and application configuration.

While you are getting the application portability, you are loosing the development and testing portability. You are not able to reproduce exactly the same development and testing environment outside of your CI. To create a new test environment you will need to setup all testing tools (correct versions and plugins), configure runtime and OS settings and get the same versions of test scripts and maybe also test data.

![The Naive Testing Strategy](/img/naive.png)

The attempt to resolve above problems leads us to the next strategy.

## App & Test Container - Testing Strategy

In this approach we try to create a single bundle, that decide the application "binaries" and required packages, also contains testing tools (specific versions), testing plugins, test scripts, test environment and all required packages.

The benefits of this approach are obvious:

- You have a repeatable test environment - you can run exactly same tests, using same testing tools, in CI, development, staging or production environment
- You capture test scripts at a specific point of time, so you can always reproduce them in any environment
- You do not need to setup and configure your testing tools - they are part of your image

But this approach also has significant drawbacks:

- You increase the image size - now it also contains testing tools, required packages, test script and maybe even test data
- You pollute image runtime environment with test specific configuration and may even introduce an unneeded dependency (required by integration testing)
- You also need to decide what to do with the tests results and logs; how and where to export them

Take a look at simplified `Dockerfile` bellow, it attempts to illustrate the described approach.

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

![App & Test Container](/img/app_test.png)

## Test Aware Container - Testing Strategy

There should be a better approach for in-container testing and I will try to describe one.

Today Docker's promise is **"Build -> Ship -> Run"** - build your image, ship it to some registry and run it anywhere. IMHO there is one missing step - **Test**. The right sequence and more complete should be **:Build -> Test -> Ship -> Run**.

First, I will try to describe a "test-friendly" Dockerfile syntax and extensions to Docker commands, that could be done to natively support this important step. It's not a real syntax, but bear with me. I will try to define the "ideal" version and will show how to implement something that is pretty close.

```
ONTEST [INSTRUCTION]
```

The idea is to define a special `ONTEST` instruction, similar to existing [`ONBUILD`](https://docs.docker.com/engine/reference/builder/#onbuild) instruction. The `ONTEST` instruction adds to the image a trigger instruction to be executed at a later time, when the image will be tested. Any build instruction can be registered as a trigger.

The `ONTEST` instruction should be respected by a new `docker test` command.

```
docker test [OPTIONS] IMAGE [COMMAND] [ARG...]
```

The `docker test` command syntax will be similar to `docker run` command, with one significant difference: a new "testable" image will be automatically generated and even tagged with `<image name>:<image tag>-test` tag ("test" postfix added to the original image tag). This "testable" image will generated `FROM` the application image, executing all build instructions, defined after `ONTEST` command and executing `ONTEST CMD` (or `ONTEST ENTRYPOINT`).
The `docker test` command should return a non-zero code, if any of tests fails. The test results should be written into automatically generated `VOLUME`, that points to `/var/tests/results` folder.

Take a look at modified `Dockerfile` bellow - it  includes a new proposed `ONTEST` instruction.

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

![Test Aware Container](/img/test_aware.png)

### Make "Test Aware Container Testing Strategy" Real Today

First, I think Docker need to take testing more seriously and make it part of the container management lifecycle. Still, there is a need to have a simple working solution today and here I will try to describe one, that is pretty close to desired state.

As mentioned before, Docker has very useful `ONBUILD` instruction. This instruction allows to trigger another build instructions on succeeding builds.
The basic idea is to use `ONBUILD` instruction, when running `docker-test` command.

Here is the detailed flow, executed by `docker-test` command:

1. `docker-test` will seach for `ONBUILD` instructions in application `Dockerfile` and will ...
2. generate a temporary `Dockerfile.test` from original `Dockerfile`
2. execute `docker build -f Dockerfile.test [OPTIONS] PATH` with additional options, supported by `docker build` command; `-test` will be automatically appended to `tag` option
3. ff build is successful, execute `docker run -v ./tests/results:/var/tests/results [OPTIONS] IMAGE:TAG-test [COMMAND] [ARG...]`
4. Remove `Dockerfile.test` file

Why not to create a new `Dockerfile.test` without messing with `ONBUILD` instruction?
My answer is that in order to test right image (and tag) you will need to keep `FROM` always updated to **image:tag** you want to test. And this is not trivial.

There is also a limitation in the described approach - it's not suitable for "onbuild" images (images used to automatically build your app), like [Maven:onbuild](https://hub.docker.com/_/maven/)

Take a look at the simple implementation of `docker-test` command bellow. It's presented here just to highlight the concept; real `docker-test` command should be able to handle `build` and `run` command options and be able to handle errors properly.

```sh
#!/bin/bash
image="app"
tag="latest"

echo "FROM ${image}:${tag}" > Dockerfile.test &&
docker build -t "${image}:${tag}-test" -f Dockerfile.test . &&
docker run -it --rm -v $(pwd)/tests/results:/var/tests/results "${image}:${tag}-test" &&
rm Dockerfile.test
```

## Integration Test Container - Testing Strategy

And now most interesting part of this post is coming (in my opinion).

Suppose you have an application built from tens or hundreds of microservices. Suppose you succeed to create an automated CI/CD pipeline: where each microservice is built and tested by CI and delivered into some environment (testing, staging or production), when its build and tests pass. Pretty cool, isn't it?
Your CI tests are pretty capable of testing each microservice in isolation, running unit and service tests (or API contract tests). Maybe even micro-integration tests - tests were run on subsystem created ad-hoc (for example with `docker compose` help).
But what about real integration testing or long running tests (like performance and stress)? What about resilience tests ("chaos monkey" like tests)? Security scans? What about other test and scan activities that take time and should be run on a fully operational system?

There should be a better way, than just dropping a new microservice version into production and tightly monitor it for a while!

I suggest to create a special **Integration Test Container**. Such containers will contain only testing tools and test artifacts: test scripts, test data, test environment configuration and etc. To simplify orchestration and automation of such containers, I suggest to define and follow some conventions and metadata labels (using the Dockerfile `LABEL` instruction).  

### Integration Test Labels

- **test.type** - test type; default `integration`; can be one of: `integration`, `performance`, `security`, `chaos` or any text; presence of this label states that this is the **Integration Test Container**
- **test.results** - `VOLUME` for test results; default `/var/tests/results`
- **test.XXX** - any other test related metadata; just use **test.** prefix for label name

### Integration Test Container

The **Integration Test Container** is just a regular Docker container, but it does not contain any application logic and code. Its the sole purpose is to create a repeatable and portable testing. The recommended content of the **Integration Test Container** should be something, like this:

- *The Testing Tool* - Phantom.js, Selenium, Chakram, Gatling, ...
- *Testing Tool Runtime* - Node.js, JVM, Python, Ruby, ...
- *Test Environment Configuration* - environment variables, config files, bootstrap scripts, ...
- *Tests* - as compiled packages or script files
- *Test Data* - any kind of data files, used by tests: json, csv, txt, xml, ...
- *Test Startup Script* - some "main" startup script to run tests; just create `test.sh` and launch your testing tool from it.

**Integration Test Containers** are supposed to run in a real operation environment, where all microservices are deployed, like: testing, staging or production. These containers can be deployed exactly as all other services being deployed. They use same network layer and thus can access multiple services, using selected service discovery method (usually DNS). Accessing multiple services is required for real integration testing: you need to simulate and validate how your system is working in multiple places. Keeping integration tests inside some application service container not only increases container footprint, but also creates an unneeded dependency between multiple services. Keep all these dependencies at the level of **Integration Test Container**. Once your tests (and testing tools) are packaged inside the container, you can always rerun same tests on any environment or event developer machine. You can always return "back in time" and rerun specific version of **Integration Test Container**.

![Integration Test Container](/img/int_test.png)


WDYT?
