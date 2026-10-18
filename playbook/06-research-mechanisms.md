# 06 学术工作里可借用的机制

学术系统把各个环节拆得很细，也做了消融实验，所以哪些机制真正有效，能看得比较清楚。下表列出可以直接搬进 Claude Code 工作流的做法。

| 工作 | 机制 | 在这里怎么用 |
|---|---|---|
| [Code2Video](https://github.com/showlab/Code2Video)（ICML 2026，Manim） | **锚点网格**：右侧动画区划成 6×6 格，编号 A1–F6。代码只能用 `self.place_at_grid(obj,'B2')` 或 `place_in_area(obj,'A1','C3')` 放置元素，同时维护一张占用表（元素 → 锚点 → 代码行）。Critic 把渲染结果、网格参考图和占用表一起交给 VLM，VLM 只能输出"第 X 行改成 place_at_grid(...)"这种修改 | 在 STYLE.md 里定义网格和放置函数，禁止手写坐标。消融实验显示 6×6 效果最好。设计动机是：VLM 看得出哪里有问题，但说不准该往哪移、移多远，把定位变成离散选择就能绕开这个短板。本地源码：`references/repos/Code2Video/prompts/stage3.py` |
| 同上 | **ScopeRefine**：修 bug 时逐级扩大范围：先改报错行前后各 1 行，不行就改整个 lecture block，再不行就重写整个 section。另外有 dry-run：把 `construct` 的函数体换成 `self.wait(0.1)`，快速检查 import 和语法 | Manim 报错时按这个顺序修。本地源码：`references/repos/Code2Video/src/scope_refine.py` |
| 同上 | 各个 section 并行生成代码 | 按 chapter 派 subagent。论文里用 Claude Opus 4.1 每个主题 13.8 分钟、43K tokens；去掉并行要 86.6 分钟，再去掉 ScopeRefine 要 149.8 分钟 |
| [Paper2Video](https://github.com/showlab/Paper2Video) | **让 VLM 选，而不是让它调参**：幻灯片内容溢出时，按规则生成几个缩放和字号的变体，渲染后拼成一张图，让 VLM 从中挑一个 | 布局拿不准时，渲染 3–4 个变体拼图再选 |
| 同上 | 用 WhisperX 的词级时间戳决定光标何时出现、何时消失 | 按 cue 词触发画面 |
| [TheoremExplainAgent](https://github.com/TIGER-AI-Lab/TheoremExplainAgent) | 用 agentic RAG 检索 Manim 文档，分别服务于分镜、实现和纠错三个阶段；把报错回灌给模型重写，最多 5 次，成功率约 90% | 写 ManimGX 前先读相关文档页（https://manimgx.academa.ai/llms-full.txt 有全量 API 参考）；报错时把完整信息贴回去 |
| [SGA](https://arxiv.org/abs/2607.18116) | 部分执行代码，抽出符号化的场景图，不渲染就能检测几何遮挡，再做定向修复。人评中，65% 的对比里它优于 VLM critic | 渲染前加一步：打印所有对象的包围盒并检查重叠 |
| [ManimAgent](https://arxiv.org/abs/2606.30296) | 双通道经验记忆：M+ 存成功范例，M− 存已知的坑，跨任务积累，不更新模型权重 | 每个项目维护 `LESSONS.md`，通用的条目再提升到 `playbook/` |
| [ManimTrainer / RITL](https://arxiv.org/abs/2604.18364) | 推理时让渲染器参与循环，并把 API 文档放进上下文 | 同上：先查文档，渲染验证 |
| [综述：Agentic Visual Generation](https://arxiv.org/abs/2609.06758) | 按控制层级把这类系统分成 L0–L4。L3 是观察中间结果后调整后续操作，L4 是跨任务积累经验 | 我们的流程处在 L3；`LESSONS.md` 机制往 L4 走 |

## 需要注意

- Code2Video 的开源代码里没有配音，讲稿以文字形式显示在左侧，靠变色和动画同步。它固定使用 `manim==0.19.0`，而当前最新版是 0.21.0，存在版本差异。
- TheoremExplainAgent 的结论之一：即使渲染成功率很高，多数视频仍然有小的布局问题。所以只看"能渲染出来"是不够的，还要看图。
