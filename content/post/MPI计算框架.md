---
title: "MPI计算框架"
date: 2021-05-15T09:07:13+08:00
draft: false
tags: []
categories: []
author: ""
---

> MPI（Massage Passing Interface）是一种基于消息传递的并行计算框架，可以理解是一种更原生的分布式模型，适用于各种复杂的并行计算。由于没有IO操作，性能优于MapReduce，但是开发复杂度高。MPI经常用来和Hadoop、Spark等计算框架进行比较，其使用的场景所有不同。

# 对比Hadoop、Spark、Storm和MPI计算框架

![hadoop-spark-mpi](../../static/img/20210609/hadoop-spark-mpi.png)

# 什么是MPI

Massage Passing Interface:是消息传递函数库的标准规范，由MPI论坛开发。

* 一种新的库描述，不是一种语言。共有上百个函数调用接口，提供与C和Fortran语言的绑定

* MPI是一种标准或规范的代表，而不是特指某一个对它的具体实现

* MPI是一种消息传递编程模型，并成为这种编程模型的代表和事实上的标准

# MPI的特点

* 消息传递式并行程序设计
指用户必须通过显式地发送和接收消息来实现处理机间的数据交换。
在这种并行编程中，每个并行进程均有自己独立的地址空间，相互之间访问不能直接进行，必须通过显式的消息传递来实现。
这种编程方式是大规模并行处理机（MPP）和机群（Cluster）采用的主要编程方式。

* 并行计算粒度大，特别适合于大规模可扩展并行算法
用户决定问题分解策略、进程间的数据交换策略，在挖掘潜在并行性方面更主动,并行计算粒度大,特别适合于大规模可扩展并行算法

* 消息传递是当前并行计算领域的一个非常重要的并行程序设计方式

# 常用MPI函数

* MPI_Init(…);

* MPI_Comm_size(…);

* MPI_Comm_rank(…);

* MPI_Send(…);

* MPI_Recv(…);

* MPI_Finalize();

# MPI消息传递过程

![mpi](../../static/img/20210609/mpi.png)

# 参考

* [并行计算：MPI总结](https://blog.csdn.net/qq_40765537/article/details/106425355)

* [大数据计算框架Hadoop, Spark和MPI](https://blog.csdn.net/claire7/article/details/46848757)