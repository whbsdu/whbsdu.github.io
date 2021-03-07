---
title: "Flink作业并行度配置"
date: 2019-05-25T15:28:58+08:00
draft: false
tags: []
categories: []
author: ""
---
<!-- from evernote: Flink并行度和任务槽  —  Parallelism and Slot -->
### Flink程序的并行执行

Flink程序的执行是并发和分布式的，在执行期间，一个流（stream）会有一个或者多个流分片（stream partition），且每个算子都有一个或者多个算子子任务（operator subtask）。算子子任务彼此之间是相互独立的，运行在不同的线程里，也可能是在不同的机器或者容器（containers）里。算子子任务的数量就是这个特定算子的并行度。同一个程序的不同算子可以有不同的并行度。

![flink-parallelism](../../static/img/20210307/flink-parallelism.svg)

数据流可以通过两种方式在两个算子之间传递数据，一种是一对一（one-to-one）（或从头至尾(forwarding)）的方式，另一种是重分配(redistributing)的方式。
* 一对一方式：意味着在两个算子中保持元素的分片和顺序。比如map()算子的subtask[1]会看到souce算子的subtask[1]生产的元素，且顺序和后者生产的顺序保持一致。
* 重新分配方式：每个算子子任务发送数据到不同目标子任务。比如上面的map()算子和keyBy()/window()算子，keyBy()/window()算子和sink算子。常见的会重新分配的算子有：keyBy()（通过对key进行hash，实现re-partition），broadcast()，rebalance()（随机re-partition）。在重新分配后，只有在一对发送、接收子任务内的元素才是有序的（比如map()的subtask[1]和KeyBy()/window()的subtask[2]）。所以在这个例子中，并行机制保证每个key内部的顺序，但是不同key到达sink后聚合结果的顺序不能保证。

### Flink Parallelism设置

任务（task）的并发度有不同层级的设置。优先级： 算子设置并行度  > env设置并行度 > 客户端设置并行度 > 系统设置并行度 

1. 算子设置并行度

每个算子（operator）、data source、data sink的并发可以通过调用它的setParallelism() 方法进行设置。

```scala
val env = StreamExecutionEnvironment.getExecutionEnvironment

val text = [...]
val wordCounts = text
    .flatMap{ _.split(" ") map { (_, 1) } }
    .keyBy(0)
    .timeWindow(Time.seconds(5))
    .sum(1).setParallelism(5)
wordCounts.print()

env.execute("Word Count Example")
```

2. env(执行环境)设置并行度

Flink程序运行在一个执行环境（execution environment）的上下文（context）里，执行环境可以指定所有算子、data source、data sink的默认并发度。通过调用setParallelism()进行设置。

算子层级的并行度设置会压盖执行环境的并行度设置。

```scala
val env = StreamExecutionEnvironment.getExecutionEnvironment
env.setParallelism(3)

val text = [...]
val wordCounts = text
    .flatMap{ _.split(" ") map { (_, 1) } }
    .keyBy(0)
    .timeWindow(Time.seconds(5))
    .sum(1)
wordCounts.print()

env.execute("Word Count Example")
```

3. 客户端设置并行度

在提交Flink任务时，可以通过参数指定，通过-p参数设置。

```scala
./bin/flink run -p 10 ../examples/*WordCount-java*.jar
```

在Client程序中设置：

```scala
try {
    PackagedProgram program = new PackagedProgram(file, args)
    InetSocketAddress jobManagerAddress = RemoteExecutor.getInetFromHostport("localhost:6123")
    Configuration config = new Configuration()

    Client client = new Client(jobManagerAddress, new Configuration(), program.getUserCodeClassLoader())

    // set the parallelism to 10 here
    client.run(program, 10, true)

} catch {
    case e: Exception => e.printStackTrace
}
```

4. 系统设置并行度

修改./conf/flink-conf.yaml配置，配置项：parallelism.default， 默认是1。

### Flink Slots的配置

Flink通过把程序切分到不同的子任务（subtask），并把这些子任务调度到执行slots上，实现程序的并行执行。TaskManager提供多个slots，slots决定了TaskManager的并发能力。slots的数量取决于TaskManager上CPU cores的数量。taskmanager.numberOfTaskSlots的值建议设置为TaskManager的可用CPU核数。Yarn session模式下通过—container 参数设置TaskManager的数量。 —container   ： Number of YARN container to allocate (=Number of Task Managers) 。 

Yarn Single Job模式提交作业时并不像session模式能够指定拉起多少个TaskManager，TaskManager的数量是在提交作业时根据并发度动态计算。首先，根据设定的operator的最大并发度计算，例如，如果作业中operator的最大并发度为10，然后根据 Parallelism和numberOfTaskSlots为向YARN申请的TaskManager数。例如：如果算子中的最大Parallelism为10，numberOfTaskSlots为1，则TaskManager为10。如果算子中的最大Parallelism为10，numberOfTaskSlots为3，则TaskManager为4。

![flink-slots-1](../../static/img/20210307/flink-slots-1.png)
![flink-slots-2](../../static/img/20210307/flink-slots-2.png)
![flink-slots-3](../../static/img/20210307/flink-slots-3.png)

### Flink Parallelism和Slots的关系

Slots决定了TaskManager的并发能力，Parallelism决定了TaskManager实际使用的并发能力，程序的并发度（Parallelism）不能超过TaskManager能提供的最大slots数量。

结合官网的示例进行解释：

1. taskmanager.numberOfTaskSlots:3 ，每个TaskManager分配3个TaskSlot，3个TaskManager一共9个TaskSlot。

![flink-para-slots1](../../static/img/20210307/flink-para-slots1.png)

2. parallelism:1，运行程序默认的并行度是1，9个TaskSlot只用了1个，8个是空闲。设置合适的并行度才能提高效率。

![flink-para-slots2](../../static/img/20210307/flink-para-slots2.png)

3. 设置程序的并行度，parallelism:2

![flink-para-slots3](../../static/img/20210307/flink-para-slots3.png)

4. 设置每个算子的并行度，除了sink的并行度为1，其他的算子的并行度都是9。

![flink-para-slots4](../../static/img/20210307/flink-para-slots4.png)


### 参考
* [Flink JobManager, TaskManager, Client](http://www.hobbin.wang/post/flink%E4%BD%9C%E4%B8%9A%E7%AE%A1%E7%90%86%E6%A8%A1%E5%9D%97/)
* [Flink Parallelism 和 Slot介绍](http://www.54tianzhisheng.cn/2019/01/14/Flink-parallelism-slot/)
* [Flink Parallel DataFlows](https://ci.apache.org/projects/flink/flink-docs-release-1.8/concepts/programming-model.html#parallel-dataflows)
* [Flink Parallel Execution](https://ci.apache.org/projects/flink/flink-docs-release-1.8/dev/parallel.html)
* [Configuring TaskManager processing slots](https://ci.apache.org/projects/flink/flink-docs-release-1.8/ops/config.html#configuring-taskmanager-processing-slots)