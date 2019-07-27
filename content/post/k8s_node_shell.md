+++
date = "2019-07-27T10:00:00+02:00"
draft = true
title = "Get a Shell to a Kubernetes Node"
tags = ["Kubernetes", "DevOps", "root", "AWS", "SSH"]
categories = ["DevOps"]
+++

![Linux Shell](/img/linux_pinguin_terminal.jpg)

Throughout the lifecycle of your Kubernetes cluster, you may need to access a cluster worker node. This access could be for maintenance, configuration inspection, log collection, or other troubleshooting operations. More than that, it would be nice, if you could enable this access whenever it's needed and disable when you finish your task.

## SSH Approach

While it's possible to configure Kubernetes nodes with SSH access, this also makes worker nodes more vulnerable. Using SSH requires a network connection between the engineer’s machine and the EC2 instance, something you may want to avoid. Some users set up a jump server (also called bastion host) as a typical pattern to minimize the attack surface from the Internet. But this approach still requires from you to manage access to the bastion servers and protect SSH keys. IMHO, managing supporting SSH infrastructure, is a high price to pay, especially if you just wanted to get a shell access to a worker node or to run some commands.

## Kubernetes Approach

The Kubernetes command line tool, `kubectl`, allows you to run different commands against a Kubernetes cluster. You can manipulate Kubernetes API objects, manage worker nodes, inspect cluster, execute commands inside running container, and [get an interactive shell to a running container](https://kubernetes.io/docs/tasks/debug-application-cluster/get-shell-running-container/).

Suppose you have a `pod`, named `shell-demo`. To get a shell to the running container on this `pod`, just run:

```sh
kubectl exec -it shell-demo -- /bin/bash

# see shell prompt ...
root@shell-demo:/#
```

### How Does `exec` Work?

`kubectl exec` invokes Kubernetes API Server and it "asks" a `Kubelet` "node agent" to run an `exec` command against CRI (Container Runtime Interface), most frequently it is a Docker runtime.

The `docker exec` API/command creates a new process, sets its namespaces to a target container's namespaces and then executes the requested command, handling also input and output streams for created process.

### The Idea

> A Linux system starts out with a single namespace of each type (mount, process, ipc, network, UTS, and user), used by all processes.

So, we need to do is to run a new `pod`, and connect it to a worker node host namespaces.

### A Helper Program

It is possible to use any Docker image with shell on board as a "host shell" container. There is one limitation, you should be aware of - it's not possible to join `mount namespace` of target container (or host).

The [`nsenter`](http://man7.org/linux/man-pages/man1/nsenter.1.html) is a small program from `util-linux` package, that can run program with `namespaces` (and `cgroups`) of other processes. Exactly what we need!

Most Linux distros ship with an outdated version of `util-linux`. So, I prepared the [alexeiled/nsenter](https://hub.docker.com/r/alexeiled/nsenterr) Docker image with `nsenter` program on-board. This is a super small Docker image, of `900K` size, created from `scratch` image and a single statically linked `nsenter` binary (`v2.34`).

Use the helper script below, also available in [alexei-led/nsenter](https://github.com/alexei-led/nsenter) GitHub repository, to run a new `nsenter pod` on specified Kubernetes worker node. This helper script create a _privileged_ `nsenter pod` in a host's process and network namespaces, running `nsenter` with `--all` flag, joining all `namespaces` and `cgroups` and running a default shell as a _superuser_ (with `su -` command). 

The `nodeSelector` makes it possible to specify a target Kubernetes node to run `nsenter pod` on.
The `"tolerations": [{"operator": "Exists"}]` parameter helps to match any node `taint`, if specified.

#### Helper script

```sh
# get cluster nodes
kubectl get nodes

# output
NAME                                            STATUS   ROLES    AGE     VERSION
ip-192-168-151-104.us-west-2.compute.internal   Ready    <none>   8d      v1.13.7-eks-c57ff8
ip-192-168-171-140.us-west-2.compute.internal   Ready    <none>   7d11h   v1.13.7-eks-c57ff8

# open superuser shell on specified node
./nsenter-node.sh ip-192-168-151-104.us-west-2.compute.internal

# prompt
[root@ip-192-168-151-104 ~]#

# pod will be destroyed on exit
...
```

##### `nsenter-node.sh`

```sh
#!/bin/sh
set -x

node=${1}
nodeName=$(kubectl get node ${node} -o template --template='{{index .metadata.labels "kubernetes.io/hostname"}}') 
nodeSelector='"nodeSelector": { "kubernetes.io/hostname": "'${nodeName:?}'" },'
podName=${USER}-nsenter-${node}

kubectl run ${podName:?} --restart=Never -it --rm --image overriden --overrides '
{
  "spec": {
    "hostPID": true,
    "hostNetwork": true,
    '"${nodeSelector?}"'
    "tolerations": [{
        "operator": "Exists"
    }],
    "containers": [
      {
        "name": "nsenter",
        "image": "alexeiled/nsenter:2.34",
        "command": [
          "/nsenter", "--all", "--target=1", "--", "su", "-"
        ],
        "stdin": true,
        "tty": true,
        "securityContext": {
          "privileged": true
        }
      }
    ]
  }
}' --attach "$@"
```

### Management of Kubernetes worker nodes on AWS

When running a Kubernetes cluster on AWS, Amazon EKS or self-managed Kubernetes cluster, it is possible to manage Kubernetes nodes with [AWS Systems Manager]https://aws.amazon.com/systems-manager/). Using AWS Systems Manager (AWS SSM), you can automate multiple management tasks, apply patches and updates, run commands, and access shell on any managed node, without a need of maintaining SSH infrastructure.

In order to manage a Kubernetes node (AWS EC2 host), you need to install and start a SSM Agent daemon, see [AWS documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-install-ssm-agent.html) for more details.

But we are taking a Kubernetes approach, and this means we are going to run a SSM Agent as a `daemonset` on every Kubernetes node in a cluster. This approach allows you to run an updated version SSM Agent without a need to install it into a host machine and do it only when needed.

#### Pre-request

First, you need to attach the `AmazonEC2RoleforSSM` policy to Kubernetes worker nodes instance role. Without this policy, you wont be able to manage Kubernetes worker nodes with AWS SSM.

### Setup

Then, clone the [alexei-led/kube-ssm-agent](https://github.com/alexei-led/kube-ssm-agent) GitHub repository. It contains a properly configured SSM Agent `daemonset` file.

The `daemonset` uses the [`alexeiled/aws-ssm-agent:<ver>`](https://hub.docker.com/r/alexeiled/aws-ssm-agent) Docker image that contains:

1. AWS SSM Agent, the same version as Docker image tag
2. Docker CLI client
3. AWS CLI client
4. Vim and additional useful programs

Run to deploy a new SSM Agent daemonset:

```sh
kubectl create -f daemonset.yaml
```

Once SSM Agent daemonset is running you can run any `aws ssm` command.

Run to start a new SSM terminal session:

```sh
AWS_DEFAULT_REGION=us-west-2 aws ssm start-session --target <instance-id>

starting session with SessionId: ...

sh-4.2$ ls
sh-4.2$ pwd
/opt/amazon/ssm
sh-4.2$ bash -i
[ssm-user@ip-192-168-84-111 ssm]$

[ssm-user@ip-192-168-84-111 ssm]$ exit
sh-4.2$ exit

Exiting session with sessionId: ...
```

#### The `daemonset.yaml` file

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ssm-agent
  labels:
    k8s-app: ssm-agent
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: ssm-agent
  template:
    metadata:
      labels:
        name: ssm-agent
    spec:
      # join host network namespace
      hostNetwork: true
      # join host process namespace
      hostPID: true
      # join host IPC namespace
      hostIPC: true 
      # tolerations
      tolerations:
      - effect: NoExecute
        operator: Exists
      - effect: NoSchedule
        operator: Exists
      containers:
      - image: alexeiled/aws-ssm-agent:2.3.680
        imagePullPolicy: Always
        name: ssm-agent
        securityContext:
          runAsUser: 0
          privileged: true
        volumeMounts:
        # Allows systemctl to communicate with the systemd running on the host
        - name: dbus
          mountPath: /var/run/dbus
        - name: run-systemd
          mountPath: /run/systemd
        # Allows to peek into systemd units that are baked into the official EKS AMI
        - name: etc-systemd
          mountPath: /etc/systemd
        # This is needed in order to fetch logs NOT managed by journald
        # journallog is stored only in memory by default, so we need
        #
        # If all you need is access to persistent journals, /var/log/journal/* would be enough
        # FYI, the volatile log store /var/run/journal was empty on my nodes. Perhaps it isn't used in Amazon Linux 2 / EKS AMI?
        # See https://askubuntu.com/a/1082910 for more background
        - name: var-log
          mountPath: /var/log
        - name: var-run
          mountPath: /var/run
        - name: run
          mountPath: /run
        - name: usr-lib-systemd
          mountPath: /usr/lib/systemd
        - name: etc-machine-id
          mountPath: /etc/machine-id
        - name: etc-sudoers
          mountPath: /etc/sudoers.d
      volumes:
      # for systemctl to systemd access
      - name: dbus
        hostPath:
          path: /var/run/dbus
          type: Directory
      - name: run-systemd
        hostPath:
          path: /run/systemd
          type: Directory
      - name: etc-systemd
        hostPath:
          path: /etc/systemd
          type: Directory
      - name: var-log
        hostPath:
          path: /var/log
          type: Directory
      # mainly for dockerd access via /var/run/docker.sock
      - name: var-run
        hostPath:
          path: /var/run
          type: Directory
      # var-run implies you also need this, because
      # /var/run is a synmlink to /run
      # sh-4.2$ ls -lah /var/run
      # lrwxrwxrwx 1 root root 6 Nov 14 07:22 /var/run -> ../run
      - name: run
        hostPath:
          path: /run
          type: Directory
      - name: usr-lib-systemd
        hostPath:
          path: /usr/lib/systemd
          type: Directory
      # Required by journalctl to locate the current boot.
      # If omitted, journalctl is unable to locate host's current boot journal
      - name: etc-machine-id
        hostPath:
          path: /etc/machine-id
          type: File
      # Avoid this error > ERROR [MessageGatewayService] Failed to add ssm-user to sudoers file: open /etc/sudoers.d/ssm-agent-users: no such file or directory
      - name: etc-sudoers
        hostPath:
          path: /etc/sudoers.d
          type: Directory
```

## Summary

As you see, it's relatively easy to manage Kubernetes nodes in a pure Kubernetes way, without taking unnecessary risks and managing complex SSH infrastructure.

## Reference

- [`alexeiled/nsenter`](https://hub.docker.com/r/alexeiled/nsenter) Docker image
- [`alexei-led/nsenter`](https://github.com/alexei-led/nsenter) GitHub repository
- [`nsenter`](http://man7.org/linux/man-pages/man1/nsenter.1.html) man page
- [alexei-led/kube-ssm-agent](https://github.com/alexei-led/kube-ssm-agent) SSM Agent for Amazon EKS