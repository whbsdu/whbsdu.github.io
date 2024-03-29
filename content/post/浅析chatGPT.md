---
title: "浅析ChatGPT"
date: 2023-02-07T14:31:00+08:00
draft: false
tags: ["技术"]
categories: ["技术"]
author: "Hobbin"
---

> 自去年12月OpenAI发布ChatGPT以来，热度与日俱增，一周超百万用户，两个月超2亿用户，成为颠覆性的技术和产品。微软也在今年2月份推出了集成ChatGPT的Bing搜索引擎，新版发布后下载量增加10倍，可见其火热程度。本文对ChatGPT技术进行初步学习，并对其可能带来的变化进行分析。

### ChatGPT是什么
ChatGPT是OpenAI公司推出的一种优化的对话语言模型，是在GPT基础上进一步开发的自然语言处理模型。对话的方式使得ChatGPT能够回答后续问题、承认自身错误、挑战不正确的假设和咀嚼不合理的请求。ChatGPT是InstructGPT的兄弟模型，后者经过训练，可以遵循提示中的指令并提供详细的响应。
ChatGPT所能理解的人类意图，来源于机器学习、神经网络以及Transformer模型的多种技术模型积累。Transformer建模方法成熟以后，使用一套统一的工具来开发各种模态的基础模型，随后GPT-1、GPT-2、GPT-3模型持续演化升级，最终孵化出ChatGPT文本对话应用。

### ChatGPT的原理
ChatGPT和InstructGPT一样，使用人工反馈增强学习（RLHF）方法训练模型，与后者相比在数据集的创建上略有不同。ChatGPT使用监督微调训练了一个初始模型：人类AI训练员提供对话，他们在对话中扮演双方——用户和AI助手。让培训师可以访问模型编写的建议，以帮助他们撰写回复。将这个新的对话数据集与InstructGPT数据集混合，再将其转换为对话格式。

为了创建强化学习的奖励模型，需要收集比较数据，其中包含两个或多个按质量排序的模型响应。为了收集这些数据，收集了 AI 培训师与聊天机器人的对话，随机选择了一条模型编写的消息，抽取了几个备选的完成方式，并让 AI 培训师对它们进行排名。使用这些奖励模型，可以使用近端策略优化来微调模型，对这个过程进行了几次迭代。

![method](../../static/img/20230207/ChatGPT_Diagram.jpg)

ChatGPT是基于Transformer架构的语言模型，它在以往语言模型（如ELMo和GPT-2）的基础上有了诸多性能提升。

* 更大的语料库。ChatGPT使用更大语料库，以便捕捉人类语言复杂性
* 更加通用的预训练，以便更好的适应不同任务
* 更高的计算能力、更高的准确性、更高的适应性、更强的自我学习能力

转移学习（Transfer Learning）使得基础模型成为可能，大规模化（scale）使得基础模型更加强大，因而GPT模型得以形成。大规模化的三个要素：

* 计算机硬件的改进。例如，GPU吞吐量和内存在过去四年增加了10倍
* Transformer模型框架的开发 （Vaswani et aI.2017），该架构利用硬件的并行性来训练比以前更具表现力的模型
* 更多训练数据的可用性

2017年，在Ashish Vaswani et.aI的论文《Attention Is All You Need》中提出，性能最好的模型被证明还是通过注意力机制（attention mechanism）连接编码器和解码器，并提出一种新的简单架构 - Transformer，它完全基于注意力机制，完全不用重复和卷积，因此在质量上更优，更易于并行化，所需训练时间明显更少。Transformer模型奠定了AIGC领域的游戏规则，他摆脱了人工标注数据集的缺陷。Transformer出现后，迅速取代了RNN系列变种，跻身主流模型架构（RNN缺陷在于流水线式顺序计算）。


### ChatGPT的局限

* ChatGPT 有时会写出看似合理但不正确或荒谬的答案。解决这个问题具有挑战性，因为：（1）在 RL 训练期间，目前没有真实来源； (2) 训练模型更加谨慎导致它拒绝可以正确回答的问题； (3) 监督训练会误导模型，因为理想的答案取决于模型知道什么，而不是人类演示者知道什么。

* ChatGPT 对输入措辞的调整或多次尝试相同的提示很敏感。例如，给定一个问题的措辞，模型可以声称不知道答案，但只要稍作改写，就可以正确回答。

* 该模型通常过于冗长并过度使用某些短语，例如重申它是 OpenAI 训练的语言模型。这些问题源于训练数据的偏差（训练者更喜欢看起来更全面的更长答案）和众所周知的过度优化问题。 

* 理想情况下，当用户提供模棱两可的查询时，模型会提出澄清问题。相反，当前的模型通常会猜测用户的意图。

* 虽然我们已努力使模型拒绝不当请求，但它有时会响应有害指令或表现出有偏见的行为。当前正在使用 Moderation API 来警告或阻止某些类型的不安全内容，但预计目前它会有一些漏报。

### ChatGPT的应用和可能带来的变化

OpenAI的ChatGPT是生成式人工智能技术（AIGC）浪潮的一部分。AIGC跨模态产业生态逐步成熟，AIGC当前在文本、音频、视频等多模态交互功能上持续演化升级。随着ChatGPT Plus的发布，商业化序幕已经拉开，ChatGPT在传媒、影视、营销、娱乐以及数实共生领域均可产生极大收益，助力生产，赋能虚拟经济和实体经济。

由于ChatGPT包含了更多主题的数据，能够处理更多小众主题。ChatGPT能力范围可以覆盖回答问题、撰写文章、文本摘要、语言翻译和生成计算机代码等任务。


### 参考

* [官网](https://openai.com/blog/chatgpt/)
* [ChatGPT研究框架](https://mp.weixin.qq.com/s/Ef9Wlz5jBnF9IwYb_nO3HQ)