---
title: "常用OLAP引擎分析"
date: 2021-04-02T13:15:26+08:00
draft: false
tags: []
categories: []
author: ""
---

> Druid、ClickHouse、Presto、Impala、Kudu等常用OLAP引擎分析。

# Druid 
这里的Druid并不是阿里巴巴的数据库连接池，而是用于大数据OLAP场景的Druid。Druid是为需要快速查询和摄入数据的工作流程设计的，在即时数据可见性、即席查询、运营分析和高并发等方面表现出色。Druid创新地在架构设计上吸收和结合了数据仓库、时序数据库和检索系统的优势，表现出的性能远远超过传统解决方案。在很多数仓解决方案中，可以考虑使用Druid作为一种开源的替代解决方案。

## Druid核心特性

Druid的核心特性有以下10条。

* 列式存储。列式存储的好处主要有两个，一是在查询的时候可以避免扫描整行数据，并只返回指定列的数据；二是存储的时候压缩效果会更好。

* 可扩展的分布式架构。

* 并行计算。

* 数据的摄入支持实时和批量，即典型的lambda架构。Druid原生支持从Kafka、Amazon Kinesis等消息总线中流式消费数据，也同时支持从HDFS、Amazon S3等存储服务中批量的加载数据文件。通过实时处理保证实时性，通过批量处理保证数据完整性和准确性。

* 运维友好。

* 云原生架构，高容错性。

* 支持索引，便于快速查询。

* 基于时间的分区。

* 自动预聚合。

## Druid架构

Druid有6个不同的组件。

* Coordinator： 协调器，主要负责segment的分发，管理集群中数据的可用性。比如只保存30天的数据，这个规则就是由Coordinator来定时执行的。

* Overlord：控制数据摄取负载的分配。处理数据摄入的task，将task提交到MiddleManager。 

* Broker：处理来自外部客户端的请求，并对结果进行汇总。

* Router：可以将请求路由到Brokers、Coordinators和Overlords，不是必须的。

* Historical：存储可查询的数据。Historycal可以理解为将segment存储到本地，相当于cache。如果本地没有数据，则查询是无法查询的。

* MiddleManager：负责摄取数据。可以认为是一个任务调度进程，主要用来处理Overload提交过来的task，每个task会以一个JVM进程启动。

各个组件之间的交互如下：

![druid-arch](../../static/img/20210405/druid-arch.png)

* Queries: Routers 将请求路由到 Broker，Broker 向 MiddleManager 和 Historical 进行数据查询。这里 MiddleManager 主要负责查询正在进行摄入的数据查询，比如现在正在摄入 12:00 ~ 13:00 的数据，那么我们要查询就去查询 MiddleManager，MiddleManager 再将请求分发到具体的 peon，也就是 task 的运行实体上。而历史数据的查询是通过 Historical 查询的，然后数据返回到 Broker 进行汇总。这里需要注意的时候数据查询并不会落到 Deep Storage 上去，也就是查询的数据一定是 cache 到本地磁盘的。很多人一个直观理解查询的过程应该是先查询 Historical，Historical 没有这部分数据则去查 Deep Storage。Druid 并不是这么设计的。

* Data/Segment: 这里包括两个部分，MiddleManager 的 task 在结束的时候会将数据写入到 Deep Storage，这个过程一般称作 Segment Handoff。然后 Historical 定期的去下载 Deep Storage 中的 segment 数据到本地。

* Metadata: Druid 的元数据主要存储到两个部分，一个是 Metadata Storage，这个一般是 MySQL 等关系型数据库；另一个是 Zookeeper。zk 的作用主要是用来给各个组件进行解耦。

## 数据存储

* DataSource： Druid的数据被存储在datasources中，类似于传统RDBMS中的表。每一个数据源可以根据时间进行分区，可选地还可以进一步根据其他属性进行分区。每一个时间范围称为一个"块（chunk）"(例如，如果数据源按天分区，则为一天)。在一个块中，数据被分为一个或者多个"段（segments）"。每个段是一个单独的文件，一般情况下由数百万条数据组成。由于段被组织成时间块，因此有时将段视为存在于如下时间线上是有帮助的。

![druid-data-source](../../static/img/20210405/druid-timeline.png)

* Segment： Druid数据存储的单位是segment，segment按照时间粒度（可以通过segmentGranularity指定）划分。一个数据源可能有几个段到几十万甚至几百万个段。每个段都是在MiddleManager上创建的。每个Segment会被存储到Deep Storage和Historical进程所在的节点上。当然segment可以多备份，这样查询就能并行进行，并不是为了高可用，高可用可以通过Deep Storage来保证。 

Druid的数据格式如下，包括TimeStamp（时间戳）、Dimension（维度信息）、Metircs（指标信息）。

![druid-data-format](../../static/img/20210405/druid-data-format.png)

Druid会自动对数据进行Rollup，也就是聚合。如果时间粒度是一小时，那么在这一个小时内维度相同的数据会被合并为一条，Timestamp 都变成整点，metrics 会根据聚合函数进行聚合，比如 sum, max, min 等，注意是没有平均 avg 的。Timestamp 和 Metrics 直接压缩存储即可，比较简单。

Druid 的一大亮点就是支持多维度实时聚合查询，简单来说就是 filter 和 group。而实现这个特性的关键技术主要两点：bitmap（位图） + 倒排。


## Druid适合的场景

Druid为点击流、APM、供应链、网络检测、市场营销以及其他事件驱动类型的数据分析解锁了一种新型的查询和工作流程。Druid专为实时和历史数据高效快速的即席查询而设计。

# ClickHouse

## ClickHouse核心特性

## ClickHouse架构

## ClickHouse适合的场景

# Presto

## Presto核心特性

## Presto架构

## Presto适合的场景

# Impala

## Impala核心特性

## Impala架构

## Impala适合的场景

# Kudu

## Kudu核心特性

## Kudu架构

## Kudu适合的场景


# 参考

* [Druid官方文档](https://druid.apache.org/docs/latest/design/)
* [Druid中文文档](http://www.apache-druid.cn/) 
* [实时OLAP系统Druid](https://zhuanlan.zhihu.com/p/79719233)
* [一文读懂Kudu](https://www.jianshu.com/p/83290cd817ac)