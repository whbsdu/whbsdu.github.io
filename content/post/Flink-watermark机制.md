---
title: "Flink Watermark机制"
date: 2019-10-16T22:21:18+08:00
draft: false
tags: ["flink", "watermark"]
categories: ["分布式"]
author: ""
---
<!-- from evernote: Flink中的waterMark -->

> WaterMark, latency, checkpoint 这三者实现方式都是上游节点逐步广播消息给下游节点来处理的行为（都是在流中插入一种特殊的数据结构来处理）。

### 时间语义

Flink有三种时间语义（event time, ingestion time和process time）。

对于eventtime和ingestion time两种语义到达的数据有可能乱序的。从事件产生（例如日志采集数据中的乱序日志），到流经source，再到operator，中间是有一个过程时间的。虽然大部分情况下，流到operator的数据都是按照事件产生的时间顺序来的，但是也不排除由于网络、背压等原因，导致乱序的产生（out-of-order或者说late element）。

但是对于late element，我们又不能无限期的等下去，必须要有个机制来保证一个特定的时间后，必须触发window去进行计算了。这个特别的机制，就是watermark，它告诉了算子时间不大于 WaterMark 的消息不应该再被接收【如果出现意味着延迟到达】。也就是说水位线以下的数据均已经到达。WaterMark 从源算子开始 emit，并逐级向下游算子传递。当源算子关闭时，会发射一个携带 Long.MAX_VALUE 值时间戳的 WaterMark，下游算子接收到之后便知道不会再有消息到达。

![flink-watermark-2](../../static/img/20210308/flink-watermark-2.png)

![flink-watermark](../../static/img/20210308/flink-watermark.webp)

### WaterMark的生成方式

有两种方式生成watermark和timestamp，分别是：

1. 在数据源处直接进行 assign timestamp 和 generate watermark

2. 通过timestamp和watermark generate operator来产生，如果使用了该方式，在source处产生的timestamp和watermark会被覆盖。

```scala
override def getCurrentWatermark(): Watermark = { 
    new Watermark(System.currentTimeMillis - 5000)
}
```

### watermark示例demo

[Java Code Examples for WaterMark](https://www.programcreek.com/java-api-examples/?api=org.apache.flink.streaming.api.watermark.Watermark)

### Allow Latency

默认情况下当watermark涨过了window的endtime之后，再有属于该窗口的数据到来的时候该数据会被丢弃，设置了allowLatency这个值之后，也就是定义了数据在watermark涨过window.endtime但是又在allowlatency之前到达的话仍旧会被加到对应的窗口去。会使得窗口再次被触发。Flink会保存窗口的状态直到allow latenness 超期。

### Flink 处理乱序

1. Flink如何处理乱序？
watermark+window机制。window中可以对input进行按照Event Time排序，使得完全按照Event Time发生的顺序去处理数据，以达到处理乱序数据的目的。

2. Flink何时触发window？
对于late element太多的数据而言

Event Time < watermark时间
对于out-of-order以及正常的数据而言

watermark时间 >= window_end_time
在[window_start_time,window_end_time)中有数据存在

### 参考

* [Flink Event Time Processing and Watermarks](http://vishnuviswanath.com/flink_eventtime.html)
* [Flink WaterMark 详解](https://www.jianshu.com/p/9db56f81fa2a)