---
title: "Flink反压机制"
date: 2019-11-19T22:46:32+08:00
draft: false
tags: ["Flink", "反压"]
categories: ["分布式"]
author: ""
---

<!-- from evernote： Flink-反压 -->

### 反压产生的场景

短时负载高峰导致系统接收数据的速率远高于它处理数据的速率。许多日常问题都会导致反压，例如，垃圾回收停顿可能会导致流入的数据快速堆积，或者遇到大促或秒杀活动导致流量陡增。反压如果不能得到正确的处理，可能会导致资源耗尽甚至系统崩溃。

### Flink的反压机制

Flink无需使用复杂机制解决反压问题，而是利用自身作为纯数据流引擎的优势来优雅地响应反压问题。

Flink 在运行时主要由 operators 和 streams 两大组件构成。每个 operator 会消费中间态的流，并在流上进行转换，然后生成新的流。对于 Flink 的网络机制一种形象的类比是，Flink 使用了高效有界的分布式阻塞队列，就像 Java 通用的阻塞队列（BlockingQueue）一样。还记得经典的线程间通信案例：生产者消费者模型吗？使用 BlockingQueue 的话，一个较慢的接受者会降低发送者的发送速率，因为一旦队列满了（有界队列）发送者会被阻塞。Flink 解决反压的方案就是这种感觉。

在 Flink 中，这些分布式阻塞队列就是这些逻辑流，而队列容量是通过缓冲池（LocalBufferPool）来实现的。每个被生产和被消费的流都会被分配一个缓冲池。缓冲池管理着一组缓冲(Buffer)，缓冲在被消费后可以被回收循环利用。这很好理解：你从池子中拿走一个缓冲，填上数据，在数据消费完之后，又把缓冲还给池子，之后你可以再次使用它。

### 网络传输中的内存管理

如下图所示展示了 Flink 在网络传输场景下的内存管理。网络上传输的数据会写到 Task 的 InputGate（IG） 中，经过 Task 的处理后，再由 Task 写到 ResultPartition（RS） 中。每个 Task 都包括了输入和输入，输入和输出的数据存在 Buffer 中（都是字节数据）。Buffer 是 MemorySegment 的包装类。

![flink-backpressure](../../static/img/20210308/flink-backpressure.png)

1. TaskManager（TM）在启动时，会先初始化NetworkEnvironment对象，TM 中所有与网络相关的东西都由该类来管理（如 Netty 连接），其中就包括NetworkBufferPool。根据配置，Flink 会在 NetworkBufferPool 中生成一定数量（默认2048）的内存块 MemorySegment（关于 Flink 的内存管理，后续文章会详细谈到），内存块的总数量就代表了网络传输中所有可用的内存。NetworkEnvironment 和 NetworkBufferPool 是 Task 之间共享的，每个 TM 只会实例化一个。

2. Task 线程启动时，会向 NetworkEnvironment 注册，NetworkEnvironment 会为 Task 的 InputGate（IG）和 ResultPartition（RP） 分别创建一个 LocalBufferPool（缓冲池）并设置可申请的 MemorySegment（内存块）数量。IG 对应的缓冲池初始的内存块数量与 IG 中 InputChannel 数量一致，RP 对应的缓冲池初始的内存块数量与 RP 中的 ResultSubpartition 数量一致。不过，每当创建或销毁缓冲池时，NetworkBufferPool 会计算剩余空闲的内存块数量，并平均分配给已创建的缓冲池。注意，这个过程只是指定了缓冲池所能使用的内存块数量，并没有真正分配内存块，只有当需要时才分配。为什么要动态地为缓冲池扩容呢？因为内存越多，意味着系统可以更轻松地应对瞬时压力（如GC），不会频繁地进入反压状态，所以我们要利用起那部分闲置的内存块。

3. 在 Task 线程执行过程中，当 Netty 接收端收到数据时，为了将 Netty 中的数据拷贝到 Task 中，InputChannel（实际是 RemoteInputChannel）会向其对应的缓冲池申请内存块（上图中的①）。如果缓冲池中也没有可用的内存块且已申请的数量还没到池子上限，则会向 NetworkBufferPool 申请内存块（上图中的②）并交给 InputChannel 填上数据（上图中的③和④）。如果缓冲池已申请的数量达到上限了呢？或者 NetworkBufferPool 也没有可用内存块了呢？这时候，Task 的 Netty Channel 会暂停读取，上游的发送端会立即响应停止发送，拓扑会进入反压状态。当 Task 线程写数据到 ResultPartition 时，也会向缓冲池请求内存块，如果没有可用内存块时，会阻塞在请求内存块的地方，达到暂停写入的目的。

4. 当一个内存块被消费完成之后（在输入端是指内存块中的字节被反序列化成对象了，在输出端是指内存块中的字节写入到 Netty Channel 了），会调用 Buffer.recycle() 方法，会将内存块还给 LocalBufferPool （上图中的⑤）。如果LocalBufferPool中当前申请的数量超过了池子容量（由于上文提到的动态容量，由于新注册的 Task 导致该池子容量变小），则LocalBufferPool会将该内存块回收给 NetworkBufferPool（上图中的⑥）。如果没超过池子容量，则会继续留在池子中，减少反复申请的开销。


### 反压的过程

下面这张图简单展示了两个 Task 之间的数据传输以及 Flink 如何感知到反压的：

![flink-backpressure-2](../../static/img/20210308/flink-backpressure-2.png)

记录"A"进入了 Flink 并且被 Task 1 处理（这里省略了 Netty 接收、反序列化等过程）。记录被序列化到 buffer 中。该 buffer 被发送到 Task 2，然后 Task 2 从这个 buffer 中读出记录。不要忘了：记录能被 Flink 处理的前提是，必须有空闲可用的 Buffer。

结合上面两张图看：Task 1 在输出端有一个相关联的 LocalBufferPool（称缓冲池1），Task 2 在输入端也有一个相关联的 LocalBufferPool（称缓冲池2）。如果缓冲池1中有空闲可用的 buffer 来序列化记录 “A”，我们就序列化并发送该 buffer。

这里我们需要注意两个场景：

1. 本地传输：如果 Task 1 和 Task 2 运行在同一个 worker 节点（TaskManager），该 buffer 可以直接交给下一个 Task。一旦 Task 2 消费了该 buffer，则该 buffer 会被缓冲池1回收。如果 Task 2 的速度比 1 慢，那么 buffer 回收的速度就会赶不上 Task 1 取 buffer 的速度，导致缓冲池1无可用的 buffer，Task 1 等待在可用的 buffer 上。最终形成 Task 1 的降速。

2. 远程传输：如果 Task 1 和 Task 2 运行在不同的 worker 节点上，那么 buffer 会在发送到网络（TCP Channel）后被回收。在接收端，会从 LocalBufferPool 中申请 buffer，然后拷贝网络中的数据到 buffer 中。如果没有可用的 buffer，会停止从 TCP 连接中读取数据。在输出端，通过 Netty 的水位值机制来保证不往网络中写入太多数据（后面会说）。如果网络中的数据（Netty输出缓冲中的字节数）超过了高水位值，我们会等到其降到低水位值以下才继续写入数据。这保证了网络中不会有太多的数据。如果接收端停止消费网络中的数据（由于接收端缓冲池没有可用 buffer），网络中的缓冲数据就会堆积，那么发送端也会暂停发送。另外，这会使得发送端的缓冲池得不到回收，writer 阻塞在向 LocalBufferPool 请求 buffer，阻塞了 writer 往 ResultSubPartition 写数据。

这种固定大小缓冲池就像阻塞队列一样，保证了 Flink 有一套健壮的反压机制，使得 Task 生产数据的速度不会快于消费的速度。我们上面描述的这个方案可以从两个 Task 之间的数据传输自然地扩展到更复杂的 pipeline 中，保证反压机制可以扩散到整个 pipeline。

### Netty水位线机制

下方的代码是初始化 NettyServer 时配置的水位值参数。

```java
// 默认高水位值为2个buffer大小, 当接收端消费速度跟不上，发送端会立即感知到
bootstrap.childOption(ChannelOption.WRITE_BUFFER_LOW_WATER_MARK, config.getMemorySegmentSize() + 1);
bootstrap.childOption(ChannelOption.WRITE_BUFFER_HIGH_WATER_MARK, 2 * config.getMemorySegmentSize());
```

当输出缓冲中的字节数超过了高水位值, 则 Channel.isWritable() 会返回false。当输出缓存中的字节数又掉到了低水位值以下, 则 Channel.isWritable() 会重新返回true。Flink 中发送数据的核心代码在 PartitionRequestQueue 中，该类是 server channel pipeline 的最后一层。发送数据关键代码如下所示。

```java 
private void writeAndFlushNextMessageIfPossible(final Channel channel) throws IOException {

if (fatalError) {

    return;

}

Buffer buffer = null;

try {

    // channel.isWritable() 配合 WRITE_BUFFER_LOW_WATER_MARK

    // 和 WRITE_BUFFER_HIGH_WATER_MARK 实现发送端的流量控制

        if (channel.isWritable()) {

            // 注意: 一个while循环也就最多只发送一个BufferResponse, 连续发送BufferResponse是通过writeListener回调实现的

            while (true) {

                if (currentPartitionQueue == null && (currentPartitionQueue = queue.poll()) == null) {

                return;

            }

            buffer = currentPartitionQueue.getNextBuffer();

            if (buffer == null) {

                // 跳过这部分代码

                ...

            }

            else {

                // 构造一个response返回给客户端

                BufferResponse resp = new BufferResponse(buffer, currentPartitionQueue.getSequenceNumber(), currentPartitionQueue.getReceiverId());

                if (!buffer.isBuffer() &&

                EventSerializer.fromBuffer(buffer, getClass().getClassLoader()).getClass() == EndOfPartitionEvent.class) {

                // 跳过这部分代码。batch 模式中 subpartition 的数据准备就绪，通知下游消费者。

                ...

                }

                // 将该response发到netty channel, 当写成功后,

                // 通过注册的writeListener又会回调进来, 从而不断地消费 queue 中的请求

                channel.writeAndFlush(resp).addListener(writeListener);

                return;

            }

        }

    }

} catch (Throwable t) {

    if (buffer != null) {

        buffer.recycle();

    }

    throw new IOException(t.getMessage(), t);

    }

}

// 当水位值降下来后（channel 再次可写），会重新触发发送函数

@Override

public void channelWritabilityChanged(ChannelHandlerContext ctx) throws Exception {

    writeAndFlushNextMessageIfPossible(ctx.channel());

}
```

核心发送方法中如果channel不可写，则会跳过发送。当channel再次可写后，Netty 会调用该Handle的 channelWritabilityChanged 方法，从而重新触发发送函数。


### 参考

* [Flink原理与实现：如何处理反压问题](https://blog.csdn.net/u013343882/article/details/82454408)
