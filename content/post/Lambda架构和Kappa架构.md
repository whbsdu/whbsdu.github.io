---
title: "Lambda架构和Kappa架构"
date: 2021-04-22T17:35:03+08:00
draft: false
tags: []
categories: []
author: ""
---

# Lambda架构

> Lambda架构是由Storm的作者Nathan Marz根据多年分布式大数据系统的经验提炼的一个实时大数据处理框架。Lambda架构的目标是设计出一个能满足实时大数据系统关键特性的架构，包括：**高容错、低延迟和可扩展**等。Lambda架构通过对数据和查询的本质认识，整合离线计算和实时计算，融合不可变性（Immutability），读写分离和复杂性隔离等一系列架构原则，将大数据处理系统分为Batch Layer、Speed Layer和Serving Layer三层。Lambda架构作为一个通用的大数据处理框架，可集成Hadoop、Spark、Flink、Storm、Kafka、Hbase等各类大数据组件。

## 数据系统本质

为了能够设计出满足大数据关键特性的系统，需要对数据系统有一个本质的理解，我们可以将数据系统简化为：

**数据系统 = 数据 + 查询**

从数据和查询两个方面来认识大数据系统的本质。

1. 数据

**数据的本质**

数据是一个不可分割的单位，数据有两个关键特性：When和What。When是指数据与实践相关，数据一定是在某个时间发生的。数据的时间性质决定了数据的全局发生先后，也决定了数据的结果。What是指数据本身，由于数据跟某个时间点相关，所以数据本身是不可变的（Immutable），过往的数据已经成为事实（Fact），不可能回到过去的某个时间点改变数据事实，这就意味着对数据的操作其实只有两种：读取已经存在的数据和添加更多的新数据。采用数据库的记法，CRUD就编程了CR，Update和Delete本质上是新产生的数据信息，用C来记录。

**数据的存储**

Lambda架构中对数据存储采取的方式是：数据不可变，存储所有的数据。通过采用不可变方式存储所有数据，有如下好处：

* 简单。采用不可变的数据模型，存储数据时只需要简单的往主数据集后追加数据即可。相比于采用可变的数据模型，为了Update操作，数据通常需要被索引，从而能快速找到要更新的数据去做更新操作。

* 应对人为和机器的错误。前述中提到人和机器每天都可能会出错，如何应对人和机器的错误，让系统能够从错误中快速恢复极其重要。不可变性（Immutability）和重新计算（Recomputation）则是应对人为和机器错误的常用方法。采用可变数据模型，引发错误的数据有可能被覆盖而丢失。相比于采用不可变的数据模型，因为所有的数据都在，引发错误的数据也在。修复的方法就可以简单的是遍历数据集上存储的所有的数据，丢弃错误的数据，重新计算得到Views（View的概念参考4.1.2）。重新计算的关键点在于利用数据的时间特性决定的全局次序，依次顺序重新执行，必然能得到正确的结果。

当前业界有很多采用不可变数据模型来存储所有数据的例子。比如分布式消息中间件Kafka，基于Log日志，以追加append-only的方式来存储消息。

2. 查询

查询的本质：

**Query = Funtion(All Data)**

该等式的含义是：查询是应用于数据集上的函数。该定义看似简单，却几乎囊括了数据库和数据系统的所有领域：RDBMS、索引、OLAP、OLTP、MapReduce、EFL、分布式文件系统、NoSQL等都可以用这个等式来表示。

## Lambda架构

大数据系统的关键问题：如何实时地在任意大数据集上进行查询？
最简单的方法是，根据前面说的查询等式： Query = Function(All Data)，在全体数据集上在线运行查询函数得到结果。但是如果数据量很大，该方法计算成本太高，不现实。

Lambda架构通过三层架构来解决该问题：Batch Layer、Speed Layer和Serving Layer，完整的视图和流程如图所示。

![lambda](../../static/img/20210425/lambda_arch.png)

数据流进入系统后，同时发往Batch Layer和Speed Layer处理。Batch Layer以不可变模型离线存储所有数据集，通过在全体数据集上不断重新计算构建查询所对应的Batch Views。Speed Layer处理增量的实时数据流，不断更新查询所对应的Realtime Views。Serving Layer响应用户的查询请求，合并Batch View和Realtime View中的结果数据集到最终的数据集。

**Batch Layer**

Batch Layer的功能主要有两点：
* 存储数据集

根据前述对数据When&What特性的讨论，Batch Layer采用不可变模型存储所有的数据。因为数据量比较大，可以采用HDFS之类的大数据储存方案。如果需要按照数据产生的时间先后顺序存放数据，可以考虑如InfluxDB之类的时间序列数据库（TSDB）存储方案。

* 在数据集上预先计算查询函数，构建查询所对应的View

上面说到根据等式Query = Function(All Data)，在全体数据集上在线运行查询函数得到结果的代价太大。但如果我们预先在数据集上计算并保存查询函数的结果，查询的时候就可以直接返回结果（或通过简单的加工运算就可得到结果）而无需重新进行完整费时的计算了。这儿可以把Batch Layer看成是一个数据预处理的过程。我们把针对查询预先计算并保存的结果称为View，View是Lamba架构的一个核心概念，它是针对查询的优化，通过View即可以快速得到查询结果。 

![lambda](../../static/img/20210425/lambda_batch_layer.png)

View是一个和业务关联性比较大的概念，View的创建需要从业务自身的需求出发。一个通用的数据库查询系统，查询对应的函数千变万化，不可能穷举。但是如果从业务自身的需求出发，可以发现业务所需要的查询常常是有限的。Batch Layer需要做的一件重要的工作就是根据业务的需求，考察可能需要的各种查询，根据查询定义其在数据集上对应的Views。

**Speed Layer**

Batch Layer可以很好的处理离线数据，但有很多场景数据不断实时生成，并且需要实时查询处理。Speed Layer正是用来处理增量的实时数据。

Speed Layer和Batch Layer比较类似，对数据进行计算并生成Realtime View，其主要区别在于：

* Speed Layer处理的数据是最近的增量数据流，Batch Layer处理的全体数据集

* Speed Layer为了效率，接收到新数据时不断更新Realtime View，而Batch Layer根据全体离线数据集直接得到Batch View。

Lambda架构将数据处理分解为Batch Layer和Speed Layer有如下优点：

![lambda](../../static/img/20210425/lambda_batch_speed.png)

* 容错性。Speed Layer中处理的数据也不断写入Batch Layer，当Batch Layer中重新计算的数据集包含Speed Layer处理的数据集后，当前的Realtime View就可以丢弃，这也就意味着Speed Layer处理中引入的错误，在Batch Layer重新计算时都可以得到修正。这点也可以看成是CAP理论中的最终一致性（Eventual Consistency）的体现。 

* 复杂性隔离。Batch Layer处理的是离线数据，可以很好的掌控。Speed Layer采用增量算法处理实时数据，复杂性比Batch Layer要高很多。通过分开Batch Layer和Speed Layer，把复杂性隔离到Speed Layer，可以很好的提高整个系统的鲁棒性和可靠性。

**Serving Layer**

Lambda架构的Serving Layer用于响应用户的查询请求，合并Batch View和Realtime View中的结果数据集到最终的数据集。

![lambda](../../static/img/20210425/lambda_serving_layer.png)

## Lambda架构选型

**选型原则**

Lambda架构是个通用框架，各个层选型时不要局限时上面给出的组件，特别是对于View的选型。从我对Lambda架构的实践来看，因为View是个和业务关联性非常大的概念，View选择组件时关键是要根据业务的需求，来选择最适合查询的组件。不同的View组件的选择要深入挖掘数据和计算自身的特点，从而选择出最适合数据和计算自身特点的组件，同时不同的View可以选择不同的组件。

**组件选型**

下图给出了Lambda架构中各个层常用的组件。数据流存储可选用基于不可变日志的分布式消息系统Kafka；Batch Layer数据集的存储可选用Hadoop的HDFS，或者是阿里云的ODPS；Batch View的预计算可以选用MapReduce或Spark；Batch View自身结果数据的存储可使用MySQL（查询少量的最近结果数据），或HBase（查询大量的历史结果数据）。Speed Layer增量数据的处理可选用Storm或Spark Streaming；Realtime View增量结果数据集为了满足实时更新的效率，可选用Redis等内存NoSQL。 

![lambda](../../static/img/20210425/lambda_component.png)

# Kappa架构

> Kappa架构是由LinkedIn的前首席工程师Jay Kreps提出的一种架构思想，Kreps也是Apache Kafka和Apache Samza的作者之一。Kreps对Lambda架构进行了改进，通过改进 Lambda 架构中的Speed Layer，使它既能够进行实时数据处理，同时也有能力在业务逻辑更新的情况下重新处理以前处理过的历史数据。不同于 Lambda 同时计算流计算和批计算并合并视图，Kappa 只会通过流计算一条的数据链路计算并产生视图。Kappa 同样采用了重新处理事件的原则，对于历史数据分析类的需求，Kappa 要求数据的长期存储能够以有序 log 流的方式重新流入流计算引擎，重新产生历史数据的视图。

## 架构

![lambda](../../static/img/20210425/kappa_arch.png)

Kappa架构的原理就是：在Lambda 的基础上进行了优化，删除了 Batch Layer 的架构，将数据通道以消息队列进行替代。因此对于Kappa架构来说，依旧以流处理为主，但是数据却在数据湖层面进行了存储，当需要进行离线分析或者再次计算的时候，则将数据湖的数据再次经过消息队列重播一次则可。

以Kafka为例讲述Kappa的全过程如下：

![lambda](../../static/img/20210425/kappa_kafka.png)

* 部署 Apache Kafka，并设置数据日志的保留期（Retention Period），这里的保留期指的是希望能够重新处理的历史数据的时间区间

    * 例如，如果希望重新处理最多一年的历史数据，那就可以把 Apache Kafka 中的保留期设置为 365 天

    * 如果希望能够处理所有的历史数据，那就可以把 Apache Kafka 中的保留期设置为 "永久（Forever）"

* 如果我们需要改进现有的逻辑算法，那就表示我们需要对历史数据进行重新处理

    * 我们需要做的就是重新启动一个 Apache Kafka 作业实例（Instance）。这个作业实例将从头开始，重新计算保留好的历史数据，并将结果输出到一个新的数据视图中

    * 我们知道 Apache Kafka 的底层是使用 Log Offset 来判断现在已经处理到哪个数据块了，所以只需要将 Log Offset 设置为 0，新的作业实例就会从头开始处理历史数据。

* 当这个新的数据视图处理过的数据进度赶上了旧的数据视图时，我们的应用便可以切换到从新的数据视图中读取

* 停止旧版本的作业实例，并删除旧的数据视图。


# Lambda 和 Kappa 的场景区别

* Kappa 不是 Lambda 的替代架构，而是其简化版本，Kappa 放弃了对批处理的支持，更擅长业务本身为 append-only 数据写入场景的分析需求，例如各种时序数据场景，天然存在时间窗口的概念，流式计算直接满足其实时计算和历史补偿任务需求

* Lambda 直接支持批处理，因此更适合对历史数据有很多 ad hoc 查询的需求的场景，比如数据分析师需要按任意条件组合对历史数据进行探索性的分析，并且有一定的实时性需求，期望尽快得到分析结果，批处理可以更直接高效地满足这些需求

![lambda](../../static/img/20210425/lambda_kappa_compare.png)

# 参考

* [How to beat the cap theorem](http://nathanmarz.com/blog/how-to-beat-the-cap-theorem.html)
* [Questioning the Lambda Architecture - Kappa Architecture](https://www.oreilly.com/radar/questioning-the-lambda-architecture/)
* [Lambda架构详解](https://www.cnblogs.com/lenmom/p/9104541.html)
* [Lambda architecture](http://lambda-architecture.net/)
* [Kappa architecture](http://milinda.pathirage.org/kappa-architecture.com/)
* [CAP理论及历史质疑](https://blog.csdn.net/chen77716/article/details/30635543)
* [大数据架构如何做到流批一体](https://www.infoq.cn/article/uo4pfswlmzbvhq*y2tb9)