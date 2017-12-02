+++
date = "2017-10-11T18:00:00+02:00"
draft = false
title = "Continuous Delivery and Continuous Deployment to Kubernetes production"
tags = ["kubernetes", "docker", "tutorial", "helm", "continuous delivery", "continuous deployment", "devops", "cd", "ci"]
categories = ["Kubernetes"]
extlink = "https://codefresh.io/blog/cd_helm_kubernetes/"
+++

> THIS IS A DRAFT VERSION OF POST TO COME, PLEASE DO NOT SHARE

## Starting Point

Over last years we've been adopting several concepts for our project, straggling to make them working together.

The first one is the *Microservice Architecture*. We did not started it clean and by the book, rather applied it to the already existing project: splitting big services into smaller and breaking excessive coupling. The refactoring work is not finished yet. New services, we are building, starts looking more like "microservices", while there are still few that, I would call "micro-monoliths".
I have a feeling that this is a typical situation for already existing project, that tries to adopt this new architecture pattern: _you are almost there, but there is always a work to be done_.

Another concept is using Docker for building, packaging and deploying application services. We bet on Docker from the very beginning and it used for most of our services and it happens to be a good bet. 
There are still few pure cloud services, that we are using when running our application on public cloud, thing like Databases, Error Analytics, Push Notifications and some others.

And one of the latest bet we made was Kubernetes. Kubernetes became a main runtime platform for our application. Adopting Kubernetes, allowed us not only to hide away a lots of operational complexity, achieving better availability and scalability, but also be able to run our application on any public cloud and on-premise deployment.

With great flexibility, that Kubernetes brings, come an additional deployment complexity.
Suddenly your services are not just plain Docker containers, but there are a lot of new (and useful) Kubernetes resources that you need to take care for: *ConfigMsaps*, *Secrets*, *Services*, *Deployments*, *StatefulSets*, *PVs*, *PVCs*, *Ingress*, *Jobs* and others. And it's no always obvious where to keep all these resources and how they are related to Docker images built by CI tool.


## "Continuous Delivery" vs. "Continuous Deployment"

The ambiguity of **CD** term annoys me a lot. Different people mean different things when use this term. 
Still, it looks like there is a common agreement that *Continuous Deployment (CD)* is a super-set of *Continuous Delivery (CD)*. The main difference, so far, is that the *first CD* is 100% automated, while in *second CD* there are still some steps that should be done manually.

In our project, for example, we succeeded to achieve *Continuous Delivery*, that serves us well both for SaaS and on-premise version of our product. Our next goal is to create *Continuous Deployment* for SaaS version of our product. We would like to be able release a change automatically to production, without human intervention, and be able to rollback to the previous version if something went wrong.


## Kubernetes Application and Release Content 

Let's talk about *Release Content*. When we are releasing a change to some runtime environment, it's not only a code change, that is represented by a new Docker image tag. Change can be done to configuration, secret, ingress rules, jobs we are running, volumes and other assets. And we want to be able to release these changes too, just like we can release a new code change. Actually a change can be a mixture of both and in practice it's not a rare use case. 

So, we need a good methodology and supporting technology, that will allow us to release a new version of our Kubernetes application, that may contain multiple changes that are not only new Docker image tags. We also need a way to do it repeatedly on any runtime environment (Kubernetes cluster in our case) and be able to rollback ALL changes to the previous version if something went wrong.

That's why we adopted [Helm](https://www.helm.sh) as our main release management tool for Kubernetes.


## Helm recap

This post is not about Helm, so the Helm recap will be very short. I encourage you to read Helm documentation, it's complete and well written.

Core Helm concepts are:

- **Chart** - is a package (`tar` file) with Kubernetes `YAML` templates (with all required Kubernetes resources) and default values (also stored in `YAML` files). Helm uses *chart* to install a new or update an existing *release*.
- **Release** - is a Kubernetes application instance, installed with Helm
- **Revision** - when updating an existing *release*, a new *revision* is created. Helm can rolls back a *release* to a previous *revision*.
- **Chart Repository** - is a location where packaged *charts* can be stored and shared.


## Git Repository Management

I suggest the following guideline for Git-to-Docker repository management:

1. Create a `git` repository for each service - service code and Dockerfile.
2. Create a single `git` repository for application Helm chart.
3. I suggest to adopt [GitHub Flow model](http://www.nicoespeon.com/en/2013/08/which-git-workflow-for-my-project/#the-github-flow) for service code management

![GitHub Flow](/img/github-flow-branching-model.jpg)


## Docker Continuous Integration

Building and testing code on `push` event and packaging it into some build artifact is a common knowledge and there are tons of tools, services and tutorials how to do it. Our Codefresh service is tuned to do this for building Docker images. Codefresh Docker CI has one significant benefit versus other similar services - besides just being a pretty fast CI for Docker, it maintains a traceability links between git commits, builds, docker images and releases to runtime environments. You can always see what is running in your Kubernetes cluster, where it come from (release, build) and what does it contain: images, image metadata (quality, security, etc.), code commits.

![Docker CI](/img/docker_ci.png)

### Typical Docker CI flow:

1. Trigger CI pipeline on `push` event
2. Build and test service code. *Tip:* give a try to a Docker multistage build.
3. *Tip:* Embed the git commit details into the Docker image (use Docker labels). I suggest to follow [Label Schema convention](http://label-schema.org).
4. Tag Docker image with `{branch}-{short SHA}` 
5. Push newly created Docker image into preferred Docker Registry

### Docker multistage build

With a Docker mulstistage build, you can even remove a need to learn a CI DSL syntax, like Jenkins Job/Pipeline, or other YAML based DSL. Just use a familiar `Dockerfile` imperative syntax to describe all required CI stages (build, lint, test) and create a thin final Docker image that contains only bare minimum required to run the service.

Using multistage Docker build, has other benefits. It allows you to use the same CI flow both on the developer machine and the CI server and even easily switch between different CI services. The only thing you need is a Docker daemon ('> 17.05').

#### Example: Node.js multistage Docker build

```dockerfile
#
# ---- Base Node ----
FROM alpine:3.5 AS base
# install node
RUN apk add --no-cache nodejs-npm tini
# set working directory
WORKDIR /root/chat
# Set tini as entrypoint
ENTRYPOINT ["/sbin/tini", "--"]
# copy project file
COPY package.json .

#
# ---- Dependencies ----
FROM base AS dependencies
# install node packages
RUN npm set progress=false && npm config set depth 0
RUN npm install --only=production 
# copy production node_modules aside
RUN cp -R node_modules prod_node_modules
# install ALL node_modules, including 'devDependencies'
RUN npm install

#
# ---- Test ----
# run linters, setup and tests
FROM dependencies AS test
COPY . .
RUN  npm run lint && npm run setup && npm run test

#
# ---- Release ----
FROM base AS release
# copy production node_modules
COPY --from=dependencies /root/chat/prod_node_modules ./node_modules
# copy app sources
COPY . .
# expose port and define CMD
EXPOSE 5000
CMD npm run start
```

Almost all modern CI services and tools like Jenkins can do this. 

> But *Docker CI* is not a *Kubernetes CD*. 

After CI completes, you just have a new build artifact: a Docker image. Now you need somehow to deploy it to a desired environment and maybe also need to modify other Kubernetes resources: configurations, secrets, volumes, policies and etc. Or maybe you do not have a "pure" microservice architecture and some of your services still have some kind of inter-dependency and need to be released together. I know, this is not "by the book", but this is a very common use case: people are not perfect and not all architectures out there perfect too.

So, on one side you have one or more freshly backed Docker images. On the other side there are one or more environments where you want to deploy these images with corresponding configuration changes. And most likely, you would like to reduce required manual effort to the bare minimum or dismiss it completely.


## Kubernetes Continuous Delivery (CD)

Continuous Delivery is the next step we are taking. Most of CD tasks are automated, while there are still few tasks that should be done manually. The reason for having manual tasks can be different: either you cannot achieve full automation or you want to have a feeling of control (deciding when to release by pressing some "Release" button). 

For Kubernetes Continuous Delivery use case, it means that we manually update application Helm chart with appropriate image tags and others Kubernetes `YAML` template files. Once changes pushed to a git repository, an automated CD pipeline execution is triggered. 

![Kubernetes Continuous Delivery](/img/k8s_cd.png)

### Typical Kubernetes Continuous Delivery flow:

1. Define Docker CI for application services services
2. Branch Helm chart repository; use the same branch methodology as for services
2. Manually update `imageTag` for updated microservice
3. Manually update Helm chart version
4. Trigger CD pipeline on `push` event
   - validate Helm chart: use `helm lint`, `kubeval`, and similar tools
   - package and push to a Helm Chart Repository; *Tip:* create few chart repositories; I suggest to have a Chart Repository per environment: `production`, `staging`, `develop`
5. Manually (or automatically) execute `helm upgrade --install` from corresponding Chart repository

After CD completes, we have a new "artifact" - an updated package of our Kubernetes application with a new version number. Now, what remains is to run `help upgrade --install` command and create a new revision for the application release. If something goes wrong, we can always roll back to the previous revision. For the sake of safety, I suggest to run `helm diff` (using `diff` plugin) or at least use `--dry-run` flag for the first run, to see difference between the new Release version and already installed version. If you are ok with upcoming changes, accept them and run `helm upgrade --nstall` command for real.

## Kubernetes Continuous Deployment (CD)

Based on definition, *Continuous Deployment* means that there should be no manual steps, besides `git push` for code changes and configuration changes. All actions, running after `git push`, should be 100% automated and deliver a change to corresponding runtime environment. 

Lets take a look at manual steps from "Continuous Delivery" pipeline and think about *how can we automate them?* 

![Kubernetes Continuous Deployment](/img/k8s_cdd.png)

### updating imageTag after successful `docker push`

Here we have two (and maybe more) options:

1. Add a Docker Registry *webhook* handler (for example, using AWS Lambda). Take a new image tag from the `push` event payload and update corresponding `imageTag` in the application Helm Chart. For example, for GitHub you can use GitHub API to update a single file.
2. Add an additional step to every CI pipeline, after `docker push` step, to update a corresponding `imageTag` in a Helm Chart


### after creating a new Helm Chart package 

Deploy it automatically to a desired environment. Define and follow some kind of naming convention. For example, deploy `master` to `master/production`, `staging` to `staging`, `develop` to `develop` and similar (you get the idea).
Take this even further by running some tests inside a real Kubernetes cluster, validate test results and roll back on failures.

- just one more pre-step: update imageTag with GitHub API or similar (lambda or step)
- ... steps from prev, besides 1st and last
- automatic deploy to env
- in cluster testing
- rollback to previous revision if failed
