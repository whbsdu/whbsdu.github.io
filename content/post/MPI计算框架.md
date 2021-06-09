---
title: "MPI计算框架"
date: 2021-05-15T09:07:13+08:00
draft: false
tags: []
categories: []
author: ""
---

> MPI是一种基于消息传递的并行计算框架，可以理解是一种更原生的分布式模型，适用于各种复杂的并行计算。由于没有IO操作，性能优于MapReduce，但是开发复杂度高。MPI经常用来和Hadoop、Spark等计算框架进行比较，其实用的场景所有不同。

一张表对比Hadoop、Spark、Storm和MPI计算框架。

![hadoop-spark-mpi](../../static/img/20210609/hadoop-spark-mpi.png)

# 参考

* [大数据计算框架Hadoop, Spark和MPI](https://blog.csdn.net/claire7/article/details/46848757)