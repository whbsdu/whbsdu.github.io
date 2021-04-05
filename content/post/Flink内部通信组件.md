---
title: "Flink内部通信组件"
date: 2021-03-23T09:49:16+08:00
draft: false
tags: []
categories: []
author: ""
---

> Flink内部节点之间的通信是用Akka，比如JobManager和TaskManager之间的通信。而operator之间的数据传输是利用Netty。（Spark的内部数据传输也是基于Nettty）。

# Flink内部通信组件 - Akka

Flink通过Akka实现分布式通信，Akka第一次是在Flink 0.9版本中出现，通过Akka所有的远程程序调用被封装为异步消息。它主要涉及到JobManager、TaskManager和JobClient三个组件。

Akka在Flink中用于三个分布式技术组件之间的通信，他们是JobClient，JobManager，TaskManager。Akka在Flink中主要的作用是用来充当一个coordinator的角色。JobClient获取用户提交的job，然后将其提交给JobManager。JobManager随后对提交的job进行执行的环境准备。首先，它会分配job的执行需要的大量资源，这些资源主要是在TaskManager上的execution slots。在资源分配完成之后，JobManager会部署不同的task到特定的TaskManager上。在接收到task之后，TaskManager会创建线程来执行。所有的状态改变，比如开始计算或者完成计算都将给发回给JobManager。基于这些状态的改变，JobManager将引导task的执行直到其完成。一旦job完成执行，其执行结果将会返回给JobClient，进而告知用户。它们之间的一些通信流程如下图所示：

![flink-manager](../../static/img/20210405/flink-manager.png)

上图中三个使用Akka通信的分布式组件都具有自己的actor系统。

## Akka与Actor模型

Akka是一个用来开发支持并发、容错、扩展性的应用程序框架，它是actor model的实现。在actor模型的上下文中，所有的活动实体都被认为是互不依赖的actor。actor之间的互相通信是通过彼此之间发送异步消息来实现的。每个actor都有一个邮箱来存储接收到的消息。因此每个actor都维护着自己独立的状态。

![flink-actor](../../static/img/20210405/flink-actor.png)

每个actor是一个单一的线程，它不断地从其邮箱中poll(拉取)消息，并且连续不断地处理。对于已经处理过的消息的结果，actor可以改变它自身的内部状态或者发送一个新消息或者孵化一个新的actor。尽管单个的actor是自然有序的，但一个包含若干个actor的系统却是高度并发的并且极具扩展性的。因为那些处理线程是所有actor之间共享的。这也是我们为什么不该在actor线程里调用可能导致阻塞的“调用”。因为这样的调用可能会阻塞该线程使得他们无法替其他actor处理消息。

## Actor系统
一个actor系统是所有actor存活的容器。它也提供一些共享的服务，比如调度，配置，日志记录等。一个actor系统也同时维护着一个为所有actor服务的线程池。多个actor系统可以在一台主机上共存。如果一个actor系统以RemoteActorRefProvider的身份启动，那么它可以被某个远程主机上的另一个actor系统访问。actor系统会自动得识别actor消息被路由到处于同一个actor系统内的某个actor还是处于一个远程actor系统内的actor。如果是本地通信的情况（同一个actor系统），那么消息的传输可以有效得利用共享内存的方式；如果是远程通信，那么消息将通过网络栈来传输。
actor基于层次化的组织形式（也就是说它基于树形结构）。每个新创建的actor都将以创建它的actor作为父节点。层次结构有利于监督、管理（父actor管理其子actor）。如果某个actor的子actor产生错误，该actor将会得到通知，如果它有能力处理这个错误，那么它会尝试处理否则它会负责重启该子actor。系统创建的首个actor将托管于系统提供的guardian actor/user。

## Flink为什么用Akka替代RPC

使用RPC服务存在的问题：

* 没有带回调的异步调用功能，这也是为什么Flink的多个运行时组件需要poll状态的原因，这导致了不必要的延时。
* 没有exception forwarding，产生的异常都只能简单地吞噬掉，这使得在运行时产生一些非常难调试的古怪问题
* 处理器的线程数受到限制，RPC只能处理一定量的并发请求，这迫使你不得不隔离线程池
* 参数不支持原始数据类型（或者原始数据类型的装箱类型），所有的一切都必须有一个特殊的序列化类
* 棘手的线程模型，RPC会持续的产生或终止线程

采用Akka的actor模型带来的好处：

* Akka解决上述的所有问题，并对外透明
* supervisor模型允许你对actor做失效检测，它提供一个统一的方式来检测与处理失败（比如心跳丢失、调用失败…）
* Akka有工具来持久化有状态的actor，一旦失败可以在其他机器上重启他们。这个机制在master fail-over的场景下将会变得非常有用并且很重要。
* 你可以定义许多call target（actor），在TaskManager上的任务可以直接在JobManager上调用它们的ExecutionVertex，而不是调用JobManager，让其产生一个线程来查看执行状态。
* actor模型接近于在actor上采用队列模型一个接一个的运行，这使得状态机的并发模型变得简单而又健壮

# Flink内部通信组件 - Netty

## Netty简介

Netty是一个NIO客户端-服务器框架，（Java NIO是在jdk1.4开始使用的，它既可以说成“新IO”，也可以说成非堵塞式IO，[参考](https://blog.csdn.net/charjay_lin/article/details/81810922) ）。Netty支持快速、简单地开发网络应用程序，如协议服务器和客户机，大大简化了网络编程，如TCP和UDP套接字服务器。Netty经过精心设计，并积累了许多协议（如ftp、smtp、http）的实施经验，以及各种二进制基于文本的遗留协议。因此，Netty成功找到了一种方法，可以在不妥协的情况下实现轻松的开发、性能、稳定性和灵活性。

Netty架构图：

![flink-netty](../../static/img/20210405/flink-netty.png)

主要特点：
* 设计
    * 各种传输类型统一API - 阻塞和非阻塞套接字
    * 基于一个灵活的可扩展事件模型，该模型允许清晰的关注分离点
    * 高度可定制的线程模型 - 单线程、一个或者多个线程池（如SEDA）
    * 真正的无连接数据报套接字支持（从3.1开始）
* 易用
    * 很好的javadoc，官网demo
    * 没有其他的依赖
* 性能
    * 高吞吐，低延迟
    * 更少的资源消耗
    * 较少非必须的内存拷贝
* 安全性
    * 完整的SSL/TLS和StartTLS支持

## Reactor模型

Netty是典型的Reactor模型结构，[Reactor模型](evernote:///view/13528561/s60/df49ba62-dfd9-41be-98ce-b141c1dee325/df49ba62-dfd9-41be-98ce-b141c1dee325/)就是将消息放到一个队列中，通过异步线程池对其进行消费。

## Netty的模块组件

* Bootstrap、ServerBootStrap
一个Netty应用通常从BootStrap开始，主要作用是配置整个Netty程序，串联各个组件。Netty中的BootStrap类是客户端程序的启动引导类，ServerBootStrap是服务端启动引导类。

* Future、ChannelFutrure
Netty中所有的IO操作都是异步的，不能立刻得知消息是否被正确处理。但可以过一会等它执行完成或者直接注册一个监听，具体的实现是通过Future和ChannelFutures，他们可以注册一个监听，当操作执行成功或失败时，监听会自动触发注册的监听事件。

* Channel
Netty网络通信的组件，能够用于执行网络I/O操作。Channel为用户提供：
    * 当前网络连接的通道的状态（例如是否打开？是否已连接？）
    * 网络连接的配置参数 （例如接收缓冲区大小）
    * 提供异步的网络 I/O 操作(如建立连接，读写，绑定端口)，异步调用意味着任何 I/O 调用都将立即返回，并且不保证在调用结束时所请求的 I/O 操作已完成。
    * 调用立即返回一个 ChannelFuture 实例，通过注册监听器到 ChannelFuture 上，可以 I/O 操作成功、失败或取消时回调通知调用方。
    * 支持关联 I/O 操作与对应的处理程序。
不同协议、不同的阻塞类型的连接都有不同的 Channel 类型与之对应。

下面是一些常用的 Channel 类型：

    * NioSocketChannel，异步的客户端 TCP Socket 连接。
    * NioServerSocketChannel，异步的服务器端 TCP Socket 连接。
    * NioDatagramChannel，异步的 UDP 连接。
    * NioSctpChannel，异步的客户端 Sctp 连接。
    * NioSctpServerChannel，异步的 Sctp 服务器端连接，这些通道涵盖了 UDP 和 TCP 网络 IO 以及文件 IO。

* Selector
Netty 基于 Selector 对象实现 I/O 多路复用，通过 Selector 一个线程可以监听多个连接的 Channel 事件。
当向一个 Selector 中注册 Channel 后，Selector 内部的机制就可以自动不断地查询(Select) 这些注册的 Channel 是否有已就绪的 I/O 事件（例如可读，可写，网络连接完成等），这样程序就可以很简单地使用一个线程高效地管理多个 Channel 。

* NioEventLoop
NioEventLoop中维护了一个线程和任务队列，支持异步提交执行任务，线程启动时会调用NioEventLoop的run方法，执行I/O任务和非I/O任务。
    * I/O 任务，即 selectionKey 中 ready 的事件，如 accept、connect、read、write 等，由processSelectedKeys 方法触发。
    * 非 IO 任务，添加到 taskQueue 中的任务，如 register0、bind0 等任务，由 runAllTasks 方法触发。
两种任务的执行时间比由变量 ioRatio 控制，默认为 50，则表示允许非 IO 任务执行的时间与 IO 任务的执行时间相等。

* NioEventLoopGroup
NioEventLoopGroup主要管理eventLoop的生命周期，可以理解为一个线程池，内部维护了一组线程，每个线程（NioEventLoop）负责处理多个Channel上的事件，而一个Channel只对应于一个线程。

* ChannelHandler
ChannelHandler 是一个接口，处理 I/O 事件或拦截 I/O 操作，并将其转发到其 ChannelPipeline(业务处理链)中的下一个处理程序。

ChannelHandler 本身并没有提供很多方法，因为这个接口有许多的方法需要实现，方便使用期间，可以继承它的子类：

    * ChannelInboundHandler 用于处理入站 I/O 事件。
    * ChannelOutboundHandler 用于处理出站 I/O 操作。

或者使用以下适配器类：

    * ChannelInboundHandlerAdapter 用于处理入站 I/O 事件。
    * ChannelOutboundHandlerAdapter 用于处理出站 I/O 操作。
    * ChannelDuplexHandler 用于处理入站和出站事件。
* ChannelHandlerContext
保存Channel相关的所有上下文信息，同事关联一个ChannelHandler对象。

* ChannelPipline
保存 ChannelHandler 的 List，用于处理或拦截 Channel 的入站事件和出站操作。
ChannelPipeline 实现了一种高级形式的拦截过滤器模式，使用户可以完全控制事件的处理方式，以及 Channel 中各个的 ChannelHandler 如何相互交互。

在Netty中，每个Channel都有且只有一个ChannelPipeline与之对应，它们的组成关系如下：

![flink-netty-channel](../../static/img/20210405/flink-netty-channel.png)

一个 Channel 包含了一个 ChannelPipeline，而 ChannelPipeline 中又维护了一个由 ChannelHandlerContext 组成的双向链表，并且每个 ChannelHandlerContext 中又关联着一个 ChannelHandler。

入站事件和出站事件在一个双向链表中，入站事件会从链表 head 往后传递到最后一个入站的 handler，出站事件会从链表 tail 往前传递到最前一个出站的 handler，两种类型的 handler 互不干扰。

## Netty服务端工作架构图

![flink-netty-server](../../static/img/20210405/flink-netty-server.png)

Server 端包含 1 个 Boss NioEventLoopGroup 和 1 个 Worker NioEventLoopGroup。

NioEventLoopGroup 相当于 1 个事件循环组，这个组里包含多个事件循环 NioEventLoop，每个 NioEventLoop 包含 1 个 Selector 和 1 个事件循环线程。

每个 Boss NioEventLoop 循环执行的任务包含 3 步：

1. 轮询 Accept 事件；
2. 处理 Accept I/O 事件，与 Client 建立连接，生成 NioSocketChannel，并将 NioSocketChannel 注册到某个 Worker NioEventLoop 的 Selector 上；
3. 处理任务队列中的任务，runAllTasks。任务队列中的任务包括用户调用 eventloop.execute 或 schedule 执行的任务，或者其他线程提交到该 eventloop 的任务。

每个 Worker NioEventLoop 循环执行的任务包含 3 步：

1. 轮询 Read、Write 事件；
2. 处理 I/O 事件，即 Read、Write 事件，在 NioSocketChannel 可读、可写事件发生时进行处理；
3. 处理任务队列中的任务，runAllTasks。

# 参考

* [Akka在Flink中的应用](https://www.jianshu.com/p/e48d83e39a2f)
* [Akka and Actors](https://cwiki.apache.org/confluence/display/FLINK/Akka+and+Actors  https://blog.csdn.net/hxcaifly/article/details/84998240)
* [Akka在Flink中的使用剖析](https://yq.aliyun.com/articles/259163/)
* [Netty原理总结](https://blog.csdn.net/hxcaifly/article/details/85336795)