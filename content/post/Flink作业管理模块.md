---
title: "Flink作业管理"
date: 2020-05-20T15:23:04+08:00
draft: false
tags: []
categories: []
author: ""
---
<!-- from evernote: Flink 任务管理相关概念 — JobManager, TaskManager, Client -->
### Flink集群架构  
Flink运行时包含两类进程：JobManager和TaskManager。其中JobManager负责协调分布式计算，包括调度Task，协调checkpoint，协调故障恢复；TaskManager负责执行数据流中的任务，并缓冲、交换数据流。Flink作业提交流程如下图所示。
![flink-cluster](../../static/img/20210307/flink-cluster.svg)

### 资源管理  
每一个worker是一个JVM进程，可以在多个分开的线程中执行一个或多个子任务集合。为了控制一个worker上可以执行多少个任务，worker里引入了task slots这个概念。Flink通过把程序分解成子任务，并把子任务分到slots中，实现并行化。一般slots的数量和每个TaskManager可以获取的CPU cores数量是成比例的，对应配置项是：taskmanager.numberOfTaskSlots。

每一个task slot代表TaskManager里面一组固定大小的资源。切换资源（slotting the resource）意味着子任务不会与来自其他作业的子任务竞争托管内存，而是具有一定数量的保留托管内存。请注意，此处不会发生CPU隔离，当前slot只分离任务的托管内存。

通过调整任务槽的数量，用户可以定义子任务如何相互隔离。每个TaskManager有一个slot意味着每个任务组在一个单独的JVM中运行（例如，可以在一个单独的容器中启动）。拥有多个slot意味着更多子任务共享同一个JVM。同一JVM中的任务共享TCP连接（通过多路复用）和心跳消息。它们还可以共享数据集和数据结构，从而减少每任务开销。

![flink-taskmanager](../../static/img/20210307/flink-taskmanager.png)

默认情况下，Flink允许子任务共享slot，即使它们是不同任务的子任务，只要它们来自同一个作业。结果是一个slot可以保存作业的整个管道。允许slot共享有两个主要好处：
* Flink集群需要与作业中使用的最高并行度一样多的任务槽。无需计算程序总共包含多少任务（具有不同的并行性）。
* 更容易获得更好的资源利用率。如果没有slot共享，非密集源/ map()子任务将阻止与资源密集型窗口子任务一样多的资源。通过slot共享，将示例中的基本并行性从2增加到6可以充分利用时隙资源，同时确保繁重的子任务在TaskManagers之间公平分配。

![flink-taskmanager-share](../../static/img/20210307/flink-taskmanager-share.png)

### 参考

* [flink architecture](https://ci.apache.org/projects/flink/flink-docs-release-1.12/concepts/flink-architecture.html)