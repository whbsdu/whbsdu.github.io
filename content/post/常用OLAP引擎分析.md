---
title: "常用OLAP引擎分析"
date: 2021-04-02T13:15:26+08:00
draft: false
tags: []
categories: []
author: ""
---

> Druid、ClickHouse、Presto、Impala、Kudu等常用OLAP引擎分析。

# OLAP场景的特点

* 读多于写，不同于OLTP场景。

* 大宽表，读大量行但是少量列，结果集较小。

* 数据批量写入，且数据不更新或者少更新。

* 无需事务，数据一致性要求低。

* 灵活多变，不适合预先建模。

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

ClickHouse是一个用于OLAP场景的列式数据库管理系统。ClickHouse最初是为 YandexMetrica（世界第二大Web分析平台）而开发的。多年来一直作为该系统的核心组件被该系统持续使用着。

## ClickHouse核心特性

* **真正的列式数据库管理系统**
相比其他列式存储，如HBase、BigTable、Cassandra只能得到每秒几十万的吞吐量，而ClickHouse可以得到每秒几亿的吞吐能力。ClickHouse不单单是一个数据库，它是一个数据库管理系统，允许在运行时创建表和数据库、加载数据和运行查询，而无需重新配置或重启服务。

![clickhouse-column-based](../../static/img/20210405/clickhouse-column-based.png)

* **数据压缩**

* **数据的磁盘存储**
ClickHouse被设计用于工作在传统磁盘上，它提供每GB更低的存储成本，但是如果有可使用的SSD和内存，它也是会合理的使用这些资源。

* **多核心并行处理**
ClickHouse会使用服务器上一切可使用的资源，从而以最为自然的方式并行处理大型查询。

* **多服务器分布式处理**
上面提到的列式数据库管理系统中，几乎没有一个支持分布式的查询处理。在ClickHouse中，数据可以保存在不同的shard上，每个shard都由一组用于容错的replica组成，查询可以并行地在所有的shard上进行处理，这对于用户来说是透明的。

* **支持SQL**
支持基于SQL的声明式查询语言。支持的查询包括GROUP BY，ORDER BY，IN，JOIN以及非相关子查询。不支持窗口函数和相关子查询。

* **向量引擎**
为了更高效使用CPU，数据不仅按列存储，同时还按向量（列的一部分）进行处理，这样可以更加高效地使用CPU。

* **实时的数据更新**
ClickHouse支持在表中定义主键。为了使查询能够快速在主键中进行范围查找，数据总是以增量方式有序存储在MergeTree中。因此，数据可以持续不断高效的写入表中，并且写入过程不会存在任何的加锁行为。

* **索引**
按照主键对数据进行排序，这将帮助ClickHouse在几十毫秒内完成对数据特定值或者范围的查找。

* **适合在线查询**
在线查询意味着在没有对数据做任何预处理的情况下，以极低的延迟处理查询并将结果加载到用户页面中。

* **支持近似计算**
ClickHouse提供各种各样在允许牺牲数据精度的情况下对查询进行加速的方法:
    * 用于近似计算的各类聚合函数，如:distinct values, medians, quantiles
    * 基于数据的部分样本进行近似查询。这时，仅会从磁盘检索少部分比例的数据。
    * 不使用全部的聚合条件，通过随机选择有限个数据聚合条件进行聚合。这在数据聚合条件满足某些分布条件下，在提供相当准确的聚合结果的同时降低了计算资源的使用。

* **支持数据复制和数据完整性**
ClickHouse使用异步的多主复制技术。当数据被写入任何一个可用副本后，系统会在后台将数据分发给其他副本，以保证系统在不同副本上保持相同的数据。在大多数情况下ClickHouse能在故障后自动恢复，在一些少数的复杂情况下需要手动恢复。

* **限制**
    * 没有完整的事务支持
    * 缺少高频率，低延迟的修改或删除已存在数据的能力。仅能用于批量删除或修改数据，但这符合[GDPR](https://gdpr-info.eu/)。
    * 稀疏索引使得ClickHouse不适合通过其键检索单行的点查询。

## ClickHouse架构

![clickhouse-arch](../../static/img/20210405/clickhouse-arch-01.png)

ClickHouse的公开资料比较少，架构设计层面很难找到完整的资料，甚至没有一张整体的架构图。下面是摘自《ClickHouse原理解析与应用实践》的ClickHouse核心架构模块。

![clickhouse-arch](../../static/img/20210405/clickhouse-arch.png)

* Column 和 Field

ClickHouse按列存储数据，内存中的一列数据由一个Column对象表示。如果需要操作单个具体的数值（也就是单列中的一行数据），则需要使用Field对象，Field对象代表一个单值。

* DataType

数据的序列化和反序列化工作由DataType负责。但是并不直接负责数据的读取，而是转由从Column或者Field对象读取。

* Block与Block流

ClickHouse内部的数据操作是面向Block对象进行的，并采用了流的形式。Block对象可以看作是数据表的子集，Block对象的本质是由数据对象、数据类型和列名组成的三元组，即Column、DataType及列名称字符串。

* Table

直接使用Storage接口指代数据表，不同的表引擎由不同子类实现，IStorage接口中定义了DDL（Alter、Rename、Optimize和OROP等）、read和write方法，分别负责数据的定义、查询和写入。

* Parser与Interpreter

Parser分析器负责创建AST对象，Interpreter解释器负责解释AST，并进一步创建查询的执行管道。他们与Storage一起，串联起整个数据查询过程。
Interpreter解释器的作用就像Service服务层一样，起到串联整个查询过程的作用，它会根据解释器的类型，聚合它所需要的资源。

* Functions与Aggrefate Functions

ClickHouse主要提供两类函数：普通函数和聚合函数。普通函数由IFunction接口定义，拥有数十种函数实现，除了一些常见函数（如四则运算、日期转换等）之外，也不乏一些实用的函数，如网址提取函数、IP地址脱敏函数等。聚合函数由IAggregateFunction接口定义，聚合函数是有状态的。

* Cluster与Replication

ClickHouse的集群由分片（Shard）组成，而每个分片又通过副本（replica）组成。这种分层的概念，在一些流行的分布式系统中比较常见，如ElasticSearch。

但是，ClickHouse的1个节点只能拥有1个分片，也就是说如果要实现1分片、1副本，则至少需要部署2个服务节点。

分片只是一个逻辑概念，其无力承载还是由副本承担的。

![clickhouse-shard](../../static/img/20210405/clickhouse-shard.png)

## ClickHouse为什么这么快

* 着眼硬件，先想后做

首先从硬件层面着手，设计之初就想清楚下面几个问题：
    * 将要使用的硬件水平怎么样？ 包括CPU、内存、硬盘、网络等
    * 需要达成怎样的性能？ 包括延迟、吞吐量等
    * 准备使用什么数据结构？ 包括String、HashTable、Vector等，以及选择这些数据结构，在硬件上会如何工作

![cpu](../../static/img/20210405/cpu.png)

如果能想清楚上面这些问题，那么在动手实现功能之前，就已经能够计算出粗略的性能了。所以，基于将硬件功效最大化的目的，ClickHouse会在内存中进行GROUP BY，并且使用HashTable装载数据。与此同时，他们非常在意CPU L3级别的缓存，因为一次L3的缓存失效会带来70～100ns的延迟。这意味着在单核CPU上，它会浪费4000万次/秒的运算；而在一个32线程的CPU上，则可能会浪费5亿次/秒的运算。所以别小看这些细节，一点一滴地将它们累加起来，数据是非常可观的。正因为注意了这些细节，所以ClickHouse在基准查询中能做到1.75亿次/秒的数据扫描性能。

* 算法在前，抽象在后

在ClickHouse的底层实现中，经常会面对一些重复的场景，例如字符串子串查询、数组排序、使用HashTable等。如何才能实现性能的最大化呢？算法的选择是重中之重。以字符串为例，有一本专门讲解字符串搜索的书，名为'Handbook of Exact String Matching Algorithms'，列举了35种常见的字符串搜索算法。各位猜一猜ClickHouse使用了其中的哪一种？答案是一种都没有。这是为什么呢？因为性能不够快。在字符串搜索方面，针对不同的场景，ClickHouse最终选择了这些算法：对于常量，使用Volnitsky算法；对于非常量，使用CPU的向量化执行SIMD，暴力优化；正则匹配使用re2和hyperscan算法。性能是算法选择的首要考量指标。

* 特定场景，特殊优化

针对同一个场景的不同状况，选择使用不同的实现方式，尽可能将性能最大化。关于这一点，其实在前面介绍字符串查询时，针对不同场景选择不同算法的思路就有体现了。类似的例子还有很多，例如去重计数uniqCombined函数，会根据数据量的不同选择不同的算法：当数据量较小的时候，会选择Array保存；当数据量中等的时候，会选择HashSet；而当数据量很大的时候，则使用HyperLogLog算法。

对于数据结构比较清晰的场景，会通过代码生成技术实现循环展开，以减少循环次数。接着就是大家熟知的大杀器—向量化执行了。SIMD被广泛地应用于文本转换、数据过滤、数据解压和JSON转换等场景。相较于单纯地使用CPU，利用寄存器暴力优化也算是一种降维打击了。

## ClickHouse适合的场景

使用ClickHouse作为OLAP引擎的场景有： 监控系统、ABTest、用户行为分析、BI报表、特征分析等。

* 用户行为分析系统

行为分析系统的表可以打成一个大的宽表形式，join 的形式相对少一点，可以实现路径分析、漏斗分析、路径转化等功能

* BI报表

结合clickhouse的实时查询功能，可以实时的做一些需要及时产出的灵活BI报表需求，包括并成功应用于留存分析、用户增长、广告营销等

* 监控系统

视频播放质量、CDN质量，系统服务报错信息等指标，也可以接入ClickHouse，结合Kibana实现监控大盘功能

* ABtest

其高效的存储性能以及丰富的数据聚合函数成为实验效果分析的不二选择。离线和实时整合后的用户命中的实验分组对应的行为日志数据最终都导入了clickhouse，用于计算用户对应实验的一些埋点指标数据（主要包括pv、uv）。


* 特征分析

使用Clickhouse针对大数据量的数据进行聚合计算来提取特征
场景举例：用户行为实时分析OLAP应用场景

## ClickHouse的缺点

* 不支持Transaction：想快就别想Transaction

* 聚合结果必须小于一台机器的内存大小：不是大问题

* 缺少完整的Update/Delete操作

# Presto

Presto是Facebook推出的一个基于Java开发的大数据分布式SQL查询引擎，可以对从数GB到数PB级的数据进行交互式查询，该引擎的性能是Hive的10倍以上。

Presto 可以查询包括 Hive、HDFS、Cassandra 甚至是一些商业的数据存储产品，单个 Presto 查询可合并来自多个数据源的数据进行统一分析。Presto 的目标是在可期望的响应时间内返回查询结果。

## Presto核心特性

## Presto架构

![presto-arch](../../static/img/20210405/presto-arch.png)

Presto查询引擎是一个Master-Slave架构，由以下三部分组成：
* 一个Coordinator节点

负责解析SQL语句，生成执行计划，分发执行任务给Worker节点。Coordinator将一个完整的Query，拆分成了多个Stage，每个Stage拆分出多个可以并行的Task。

* 多个Worker节点

Worker节点负责实际执行查询任务，负责从HDFS读取数据。Worker节点启动后，向Discovery Server注册服务，Coordinator从Discovery Server获得可以正常工作的worker节点，如果配置了Hive Connector，需要配置一个Hive MetaStore服务为Presto提供Hive元信息。

* 一个Discovery Server节点

presto 使用服务发现来查找集群中所有的节点，每个注册到 Discovery Service 的节点周期性发送心跳信号，这可以使 coordinator 获取最新的可用 worker 节点列表，worker 发送心跳失败，Discovery Service 会触发失败检测，worker 将不会被分配任务。Discovery Service 是内置在 coordinator 节点中。

更形象的架构图如图所示：

![presto-arch-01](../../static/img/20210405/presto-arch-01.png)


## Presto中一个查询的执行过程

一个SQL Query进入到Presto系统中，分别完成了以下几个关键步骤，最终将结果输出：

![presto-plan-01](../../static/img/20210405/presto-plan-01.png)

1. 接收Presto Cli提交的SQL Query请求
2. SQL解析、语义分析（生成AST）
3. 生成执行计划、优化执行计划
4. 划分Stage、生成和调度Task
5. 在Presto Worker上执行Task（有从数据源拉取数据的Task，也有计算为主的Task），生成结果
6. 分批返回Query结果给客户端

![presto-plan](../../static/img/20210405/presto-plan.png)

Presto的SQL运行过程与MapReduce执行过程的对比：

![presto-plan-02](../../static/img/20210405/presto-plan-02.png)

Presto使用内存进行计算，减少与硬盘的交互。Presto的执行模型是纯内存MPP模型，比Hive使用的磁盘Shuffle的MapReduce模型快至少5倍。

## Presto低延迟的原理

* 完全基于内存的并行计算

Presto是一种MPP（Massively Parallel Processing）模型。虽然能够处理PB级别的海量数据分析，但不是代表Presto把PB级别都放在内存中计算的。而是根据场景，如count，avg等聚合运算，是边读数据边计算，再清内存，再读数据再计算，这种耗的内存并不高。

* 流水线式计算作业

所有stage都流水线化执行。

* 本地化计算

Presto在选择任务计算节点时，有限选择同一个Host的worker节点，如果节点不够再选择统一Rack的worker节点，如果还不够则随机选择其他Rack的节点。

* 动态编译执行计划

* GC控制

## 优点

* 基于内存计算，速度快

* 支持连接多个数据源，跨数据源连表查询等

* 部署相对简单

## 缺点

* coordinator 和 discovery service存在单点问题

* 连表查询，可能产生大量的临时数据，查询速度会变慢

## Presto适合的场景

Presto是定位在数据仓库和数据分析业务的分布式SQL引擎，比较适合如下几个应用场景：

* **加速Hive查询**：

* **统一SQL执行引擎**： Presto兼容ANSI SQL标准，能够连接多个RDBMS和数据仓库的数据源，在这些数据源上使用相同的SQL语法和SQL Functions。

* **为那些不具备SQL执行功能的存储系统带来SQL执行能力**。例如Presto可以为HBase、Elasticsearch、Kafka带来SQL执行能力，甚至是本地文件、内存、JMX、HTTP接口，Presto也可以做到。

* **构建虚拟的统一数据仓库，实现多数据源联邦查询**。如果需要计算的数据源分散在不同的RDBMS，数据仓库，甚至其他RPC系统中，Presto可以直接把这些数据源关联在一起分析（SQL Join），而不需要从数据源复制数据，统一集中到一起。

* **数据迁移和ETL工具**。Presto可以连接多个数据源，再加上它有丰富的SQL Functions和UDF，可以方便的帮助数据工程师完成从一个数据源拉取(E)、转换(T)、装载(L)数据到另一个数据源。

# Impala

Impala是Cloudera公司推出，提供对HDFS、HBase数据的高性能、低延迟的交互式SQL查询功能。

## Impala核心特性

* 完全在内存中计算，能够对PB级数据进行交互式实时查询、分析

* 无需转换为MR，直接读取HDFS及HBase数据，从而大大降低延迟

* C++编写，LLVM统一编译运行

* 兼容Hive SQL，但是一些复杂结构不支持

* 支持Data Local，无需数据移动，减少数据传输

* 支持列式存储

* 支持JDBC/ODBC远程访问

## Impala缺点

* 对内存依赖大，官方建议128G

* 实际使用中，分区超过1w，性能下降严重。因此需要定期删除没有必要的分区，保证分区的个数不要太大

* 稳定性不如Hive，因为完全在内存中计算，内存不够会出问题

* Impala不提供任何对序列化和反序列化的支持。Impala只能读取文本文件，而不能读取自定义二进制文件

* 每当新的记录/文件被添加到HDFS中的数据目录时，该表需要被刷新

## Impala架构

![impala-arch](../../static/img/20210405/impala-arch.png)

* Statestore Daemon

    * 负责收集分布在集群中各个impalad进程的资源信息、各节点健康状况，同步节点信息
    
    * 负责query的调度

* Catalog Daemon

    * 从Hive元数据库中同步元数据，分发表的元数据信息到各个impalad中

    * 接收来自statestore的所有请求

* Impala Daemon(impalad)

    * 接收client、hue、jdbc或者odbc请求、Query执行并返回给中心协调节点

    * 子节点上的守护进程，负责向statestore保持通信，汇报工作

## Impala与Hive的异同

![impala-mr](../../static/img/20210405/impala-mr.png)

* 数据存储

使用相同的存储数据池都支持把数据存储于HDFS, HBase。

* 元数据

    * 两者使用相同的元数据

* SQL解释处理

    * 比较相似,都是通过词法分析生成执行计划。

* 执行计划

    * Hive: 依赖于MapReduce执行框架，执行计划分成 map->shuffle->reduce->map->shuffle->reduce…的模型。如果一个Query会 被编译成多轮MapReduce，则会有更多的写中间结果。由于MapReduce执行框架本身的特点，过多的中间过程会增加整个Query的执行时间。

    * Impala: 把执行计划表现为一棵完整的执行计划树，可以更自然地分发执行计划到各个Impalad执行查询，而不用像Hive那样把它组合成管道型的 map->reduce模式，以此保证Impala有更好的并发性和避免不必要的中间sort与shuffle。

* 数据流

    * Hive: 采用推的方式，每一个计算节点计算完成后将数据主动推给后续节点。

    * Impala: 采用拉的方式，后续节点通过getNext主动向前面节点要数据，以此方式数据可以流式的返回给客户端，且只要有1条数据被处理完，就可以立即展现出来，而不用等到全部处理完成，更符合SQL交互式查询使用。

* 内存使用

    * Hive: 在执行过程中如果内存放不下所有数据，则会使用外存，以保证Query能顺序执行完。每一轮MapReduce结束，中间结果也会写入HDFS中，同样由于MapReduce执行架构的特性，shuffle过程也会有写本地磁盘的操作。

    * Impala: 在遇到内存放不下数据时，当前版本1.0.1是直接返回错误，而不会利用外存，以后版本应该会进行改进。这使用得Impala目前处理Query会受到一 定的限制，最好还是与Hive配合使用。Impala在多个阶段之间利用网络传输数据，在执行过程不会有写磁盘的操作（insert除外）

* 调度

    * Hive任务的调度依赖于Hadoop的调度策略。

    * Impala的调度由自己完成，目前的调度算法会尽量满足数据的局部性，即扫描数据的进程应尽量靠近数据本身所在的物理机器。但目前调度暂时还没有考虑负载均衡的问题。从Cloudera的资料看，Impala程序的瓶颈是网络IO，目前Impala中已经存在对Impalad机器网络吞吐进行统计，但目前还没有利用统计结果进行调度。

* 容错

    * Hive任务依赖于Hadoop框架的容错能力，可以做到很好的failover

    * Impala中不存在任何容错逻辑，如果执行过程中发生故障，则直接返回错误。当一个Impalad失败时，在这个Impalad上正在运行的所有query都将失败。但由于Impalad是对等的，用户可以向其他Impalad提交query，不影响服务。当StateStore失败时，也不会影响服务，但由于Impalad已经不能再更新集群状态，如果此时有其他Impalad失败，则无法及时发现。这样调度时，如果谓一个已经失效的Impalad调度了一个任务，则整个query无法执行。

## Impala适合的场景

参考Presto。

# Kudu

Kudu的定位是"Fast Analysis on Fast Data"，是一个既支持随机读写、又支持 OLAP 分析的大数据存储引擎。

![kudu-loc](../../static/img/20210405/kudu-loc.png)

从上图可以看出，KUDU 是一个「折中」的产品，在 HDFS 和 HBase 这两个偏科生中平衡了随机读写和批量分析的性能。

## Kudu核心特性

## Kudu架构

![kudu-arch](../../static/img/20210405/kudu-arch.png)

KUDU 中存在两个角色

* Mater Server：负责集群管理、元数据管理等功能

* Tablet Server：负责数据存储，并提供数据读写服务
为了实现分区容错性，跟其他大数据产品一样，对于每个角色，在 KUDU 中都可以设置特定数量（一般是 3 或 5）的副本。各副本间通过 Raft 协议来保证数据一致性。

KUDU Client 在与服务端交互时，先从 Master Server 获取元数据信息，然后去 Tablet Server 读写数据。

## Kudu适合的场景

* **Streaming Input with Near Real Time Availability（具有近实时可用性的流输入）**

数据分析中的一个共同挑战就是新数据快速而不断地到达，同样的数据需要靠近实时的读取，扫描和更新。Kudu 通过高效的列式扫描提供了快速插入和更新的强大组合，从而在单个存储层上实现了实时分析用例。

* **Time-series application with widely varying access patterns（具有广泛变化的访问模式的时间序列应用）**

time-series（时间序列）模式是根据其发生时间组织和键入数据点的模式。这可以用于随着时间的推移调查指标的性能，或者根据过去的数据尝试预测未来的行为。例如，时间序列的客户数据可以用于存储购买点击流历史并预测未来的购买，或由客户支持代表使用。虽然这些不同类型的分析正在发生，插入和更换也可能单独和批量地发生，并且立即可用于读取工作负载。Kudu 可以用 scalable （可扩展）和 efficient （高效的）方式同时处理所有这些访问模式。由于一些原因，Kudu 非常适合时间序列的工作负载。随着 Kudu 对基于 hash 的分区的支持，结合其对复合 row keys（行键）的本地支持，将许多服务器上的表设置成很简单，而不会在使用范围分区时通常观察到“hotspotting（热点）”的风险。Kudu 的列式存储引擎在这种情况下也是有益的，因为许多时间序列工作负载只读取了几列，而不是整行。 过去，您可能需要使用多个数据存储来处理不同的数据访问模式。这种做法增加了应用程序和操作的复杂性，并重复了数据，使所需存储量增加了一倍（或更糟）。Kudu 可以本地和高效地处理所有这些访问模式，而无需将工作卸载到其他数据存储。

* **Predictive Modeling（预测建模）**

数据科学家经常从大量数据中开发预测学习模型。模型和数据可能需要在学习发生时或随着建模情况的变化而经常更新或修改。此外，科学家可能想改变模型中的一个或多个因素，看看随着时间的推移会发生什么。在 HDFS 中更新存储在文件中的大量数据是资源密集型的，因为每个文件需要被完全重写。在 Kudu，更新发生在近乎实时。科学家可以调整值，重新运行查询，并以秒或分钟而不是几小时或几天刷新图形。此外，批处理或增量算法可以随时在数据上运行，具有接近实时的结果。

* **Combining Data In Kudu With Legacy Systems（结合 Kudu 与遗留系统的数据）**

公司从多个来源生成数据并将其存储在各种系统和格式中。例如，您的一些数据可能存储在 Kudu，一些在传统的 RDBMS 中，一些在 HDFS 中的文件中。您可以使用 Impala 访问和查询所有这些源和格式，而无需更改旧版系统。

# 参考

* [Druid官方文档](https://druid.apache.org/docs/latest/design/)
* [Druid中文文档](http://www.apache-druid.cn/) 
* [实时OLAP系统Druid](https://zhuanlan.zhihu.com/p/79719233)
* [System Properties Comparison Apache Druid vs. ClickHouse vs. Greenplum](https://db-engines.com/en/system/Apache+Druid%3BClickHouse%3BGreenplum)
* [ClickHouse深度揭秘](https://zhuanlan.zhihu.com/p/98135840)
* [ClickHouse原理解析与实践](http://www.360doc.com/content/20/0719/08/22849536_925250448.shtml)
* [ClickHouse适用场景](https://zhuanlan.zhihu.com/p/117326011)
* [一文读懂Kudu](https://www.jianshu.com/p/83290cd817ac)
* [presto架构和原理](https://www.cnblogs.com/GO-NO-1/p/12156153.html)
* [Presto的应用场景与案例](https://zhuanlan.zhihu.com/p/260653669)
*[kudu介绍](https://www.jianshu.com/p/93c602b637a4)