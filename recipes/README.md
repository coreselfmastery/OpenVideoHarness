# 镜头配方库：一镜怎么动

一张配方写的是一个镜头（或一个接缝）的运动和节奏：分几段、每段多少帧、哪些参数不能降、在哪里容易翻车、做完看哪一帧。颜色、字体、质感、音色不在配方里，它们归风格预设（[`styles/`](../styles/README.md)）。风格给皮，配方给骨，所以同一张配方可以穿 31 个预设里的任何一张皮。

- **配方**：`<family>/<id>.md`，一张一个镜头或一个接缝，索引见下文；
- **骨架**：[`sequences/`](sequences/README.md)，整支片子的节奏语法：能量弧、先划走的 hold、按能量落差选接缝、全片限额；
- **工具**：`bin/vh recipes list` 按意图、能量、引擎等条件筛，`bin/vh recipes check` 校验 frontmatter 和索引。

分镜时每个镜头都要想"怎么动"；拿不准的时候，这里有现成的做法和数。它不替代类型文档和 playbook：类型文档说这类片子要什么，playbook 说通用的做法，配方说某一种镜头具体怎么做、做到什么数。

## 配方管什么，风格管什么

| 跟配方走（结构参数） | 跟风格走（皮肤参数） |
|---|---|
| 阶段和帧数、hold 的长短、切点间隔的规律 | 颜色、字体、字重、质感、圆角、阴影的颜色 |
| 缓动的形状（先慢后快、带过冲、线性） | 具体用哪条曲线，过冲允许多大 |
| 同时在动的层数，谁先停谁后停 | 纹理：纸、颗粒、扫描线、半调 |
| 全片最多用几次、和谁不能同片 | 音色：用哪一种 whoosh、impact |
| 验收帧：看哪一帧、看什么 | 量化：台阶缓动、一拍二（12 fps） |

**冲突时听谁的**：

1. 顺序和 CLAUDE.md 的"规则冲突时"一致：用户 > 底线（那里列的整一层）> 人批过的立意卡和项目 `STYLE.md`（和默认不一样的地方，先写理由、记进 `DECISIONS.md`；从风格预设借来的东西写进这里才算数）> 类型文档 > 配方的默认值 > `playbook/` 的通用数值。配方比 playbook 具体，所以同一件事两边都写了数，以配方为准。
2. CLAUDE.md 的硬规则和"任何档位都不降的底线"高于任何配方：每一帧是 t 的纯函数、全屏闪白每秒不超过 3 次、字号不低于下限、片中没有数字静音。
3. 参数表里标 ★ 的是命门：风格可以给它换皮，不能降它的档。例如风格要求一拍二（12 fps），hold 仍按秒数给足，切点取整到 2 帧，而不是把 hold 砍半。风格明确不用某种手法时（例如 `product-keynote` 不用 glitch），换一张配方，不要把这张做残。
4. 用了配方又有意偏离它（降档、改结构、换顺序），在 `DECISIONS.md` 写一句为什么。

改写外部配方时已经和本仓库的规则对齐过，下面几处和原文不同，每张配方的"来源"一节写了具体改了什么：

- **画面文字停到读完**：没人念的字从完整显示起，底线是够快读一遍（max(1.5 s, 汉字数 ÷ 7 + 其他字符数 ÷ 20 + 0.8 s)），舒服的时长按 BRIEF 的 Pace（TASTE_CHECKLIST #5，`bin/vh readcheck`）。配方里的例子按 normal 算；shotcraft 的字卡整张只有 1.8 s，停留那一截不够快读一遍，所以改写后的字卡、黑场字卡、字标开场都长一些。
- **要读的字不小于 44 px**（1080p 的辅助文字下限）：原文里 25–26 px 的副标、标语都提上来了。
- **片中没有数字静音**：原文让黑场和死寂段的声音同帧全静，改写后保留一层很低的底（CLAUDE.md 底线）。
- **强调词不用斜体**（`playbook/03-motion-design.md` §4），改用字重或强调色。
- **blur 只在 canvas 层动画**：playbook/03 §4 不让在 DOM 里动画 `blur`。配方里需要虚焦的地方，在 canvas 上用 `ctx.filter` 做，或者在 DOM 里用预先模糊好的副本做交叉淡入。
- **落地回弹不超过约 5%**，这是 playbook/03 §1 卡片档弹簧的上限。原配方里的过冲曲线实测在 1–5% 之间，都在这个范围内，配方里写了每条曲线的实际过冲。

## 怎么挑：先定意图，再看能量

配方是参照，不是每个镜头的必经一步：先按立意和 reads 自己想镜头怎么动，拿不准、或者想要现成的节奏和数时再来挑。配方和骨架都是默认口味，立意需要时可以反着来（`playbook/12-ideation.md` 第 6 节）。

1. **先写 reads**（`playbook/01-pipeline.md`），然后给每个镜头定三样：它在片中的位置（`role`），要观众明白什么（`intent`），手上有什么素材（`needs`）。
2. **套骨架定能量**：从 [`sequences/`](sequences/README.md) 选一条骨架，得到每个位置的目标能量（0–5，和 `playbook/09-narrative.md` 节拍表的能量是同一把尺子）和 hold 预算。叙事的形状（起承转合、好奇缺口、转在哪里）先按 playbook/09 定，骨架管的是能量和停顿。
3. **筛**：条件之间是"并且"，同一个条件里用逗号写几个备选。

   ```bash
   bin/vh recipes list --intent abundance,process --energy 4 --engine hyperframes --have ui-page,ui-element
   bin/vh recipes list --family seam --jump rise          # 能量往上走的接缝
   bin/vh recipes list --role breath --seconds 3-4        # 3–4 秒的呼吸位
   ```
4. **排序，定首选和备选**：意图对得最准的排前面；能量离骨架在这个位置的目标值最近的排前面；一种手法全片只当一次主角，已经用过的往后放。
5. **查全片约束**：`max_per_film`、`conflicts`、整画面冲击不超过 3 处、呼吸位的数量（见骨架的"限额"）。
6. **写进分镜**：用了配方，STORYBOARD 的"配方"列写 `id`（多式配方写 `id · 变体`），"验收帧"列把配方的 `qa` 换算成片内帧号，"转场出"写接缝配方的 id。自己想的镜头空着就行，不用写理由。
7. **写代码前读全文**：读选中配方的全文，再读它"实现"一节指向的代码。只凭名字和印象去写，等于丢掉配方里的调校。

**按努力程度**：

| | `quick` | `standard` | `studio` |
|---|---|---|---|
| 配方 | 可选；只挑 `battle-tested` 和 `upstream-tested` 的，参数照抄 | 可选：拿不准的镜头再查；用了的写 id，读全文和实现 | 同左；hook 和高潮两个位置各做两个方案的小样对比（配方或自创都行） |
| 骨架 | 可选 | 可选：全片节奏没把握时先套骨架 | 同左；用了骨架就按它做 animatic |
| 验收帧（用了配方的镜头） | 每镜 1 帧（`peak`） | 每镜 2 帧（`peak`、`settle`） | 同左，外加每个接缝前后 0.5 s 的 strip |
| 回写 | 不回写 | 值得复用的自创手法记进 `LESSONS.md` | 值得复用的写成新配方，状态标 `draft` |

## 索引

状态的含义见下文"状态"。时长按 30 fps 换算；接缝的时长是它从两侧镜头里借走的帧，字卡和开场、收场的时长随文案变（停到读完）。这张表由 `bin/vh recipes list --md` 生成，`bin/vh recipes check` 会核对能量、时长和状态三列。

**全片骨架 `sequences/`**：[launch-15s](sequences/launch-15s.md)（15 s 发布 teaser）· [explainer-30s](sequences/explainer-30s.md)（30 s 有旁白的讲解）· [product-film-60s](sequences/product-film-60s.md)（60 s 产品发布片）；从立意出发的五条：[time-dilation-replay](sequences/time-dilation-replay.md)（时间放大镜）· [machine-eye-portrait](sequences/machine-eye-portrait.md)（机器视角的肖像）· [making-of-self](sequences/making-of-self.md)（用做法讲做法）· [mascot-style-tour](sequences/mascot-style-tour.md)（吉祥物穿越风格）· [workflow-as-story](sequences/workflow-as-story.md)（工作流即故事）。规则和接缝选型表见 [sequences/README.md](sequences/README.md)。

**接缝 `seam/`**

| 配方 | 一句话 | 能量 | 时长 | 状态 |
|---|---|---|---|---|
| [black-card](seam/black-card.md) | 前镜淡进暗场，一句短话逐词压印上屏，停到读完，再淡入后镜：换章节和喘口气一起做 | 1–2 | 3.2–5.4 s | tuned |
| [cut-the-curve](seam/cut-the-curve.md) | 前景加速着朝一个方向走出一小段，切点落在运动正快的时候，后景从反方向以同样的速度接着走、减速落定 | 2–4 | 0.53–0.73 s | tuned |
| [dark-tunnel](seam/dark-tunnel.md) | 前景顺着运动方向推出画面，穿过几帧有尘点的暗场，后景从景深里迎面放大、收焦 | 4–5 | 0.73–1.1 s | tuned |
| [flash-cut](seam/flash-cut.md) | 前镜推近到切点，硬切处骑一层 10 帧的暖白光，盖住换页 | 2–4 | 0.33 s | upstream-tested |
| [flash-stitch](seam/flash-stitch.md) | 两种画面媒介之间的硬切上插 1 帧（60 fps 是 2 帧）高反差的"底片"：二值、双色或负片，读不出内容，却把两边焊在一起 | 4–5 | 0.03–0.07 s | draft |
| [focus-handoff](seam/focus-handoff.md) | 前景失焦、淡出、略向一侧滑走，后景错开 2 帧反向收焦进来，焦点本身就是剪辑点 | 2–3 | 0.4–0.67 s | tuned |
| [gate-as-door](seam/gate-as-door.md) | 世界里立着一扇形状对应下一章的门（画框、竖屏、节点），镜头朝门心加速穿过去，门框掠出画面，门里的世界接管 | 3–5 | 0.8–1.6 s | tuned |
| [portal-wipe](seam/portal-wipe.md) | 页面上的一张卡放大成全屏窗口，被点开的那个世界从窗里长出来接管画面 | 3–4 | 1.3–1.6 s | tuned |
| [whip-pan](seam/whip-pan.md) | 相机一拍横甩到下一景，中段糊到认不出，借糊帧换景；两款：直接落位、急刹长尾 | 3–5 | 0.27–2 s | tuned |
| [zoom-through](seam/zoom-through.md) | 沿镜头纵深方向切：推进款里旧字冲向镜头、新字从远处继续长大；拉回款里旧的退远、新的从镜头背后缩回来落定 | 2–4 | 0.6–0.8 s | tuned |

**节奏 `rhythm/`**

| 配方 | 一句话 | 能量 | 时长 | 状态 |
|---|---|---|---|---|
| [accelerando-cuts](rhythm/accelerando-cuts.md) | 同一产品的 6 个构图硬切，切点间隔每两刀减半，越切越快地逼近，最后一刀定格回全景慢推 | 5 | 4.3–4.8 s | tuned |
| [drop-blackout-slam](rhythm/drop-blackout-slam.md) | 正常播放中一帧切进 12 帧的黑，画面里什么都没有，然后主视觉带着震屏和一圈亮环砸进来：全片最高潮的前一拍 | 5 | 3.7–4.7 s | tuned |
| [paparazzi-flash](rhythm/paparazzi-flash.md) | 三次快门白闪，每闪硬切同一素材的一个更近的裁切（全景 → 卡片 → 数字），最后停在那个数字上 | 4–5 | 4.2–4.5 s | tuned |

**文字 `type/`**

| 配方 | 一句话 | 能量 | 时长 | 状态 |
|---|---|---|---|---|
| [brand-imprint-open](type/brand-imprint-open.md) | 一个小记号先画出来，字标逐字压印，副标打出，整组停到读完再上浮离场，交给产品画面 | 1–2 | 3–5 s | upstream-tested |
| [breath-title-card](type/breath-title-card.md) | 一句话逐词压印上屏，只有一个强调词，短横线收住，停到读完：两段高能镜头之间的喘息和路标 | 1–2 | 3.2–5.5 s | upstream-tested |
| [decode-type](type/decode-type.md) | 字像被程序一点点解出来：乱码按 2 帧一换，每个字在 0.3 s 内依次锁定，锁定之后才开始算读的时间 | 2–4 | 0.2–1 s | tuned |

**开场 `open/`、界面 `ui/`、交互 `interaction/`、运镜 `camera/`、收尾 `outro/`**

| 配方 | 一句话 | 能量 | 时长 | 状态 |
|---|---|---|---|---|
| [spotlight-hero](open/spotlight-hero.md) | 光在整页上找一圈、停在一张卡上，镜头从左侧斜着推近；卡抬起悬停，边框上跑两圈光，再落回自己的格子 | 3 | 4.8–5.3 s | upstream-tested |
| [deal-to-grid](ui/deal-to-grid.md) | 一摞卡像发牌一样飞进网格的真实槽位，出牌越来越快，相机追着往下滚，满板后停半秒 | 4–5 | 2.9–3.8 s | upstream-tested |
| [doc-self-writing](ui/doc-self-writing.md) | 一整页真排版的文档在光标后面一块块"写"出来，侧栏随后铺开，历史条目一条条落进侧栏 | 2 | 3.3–4 s | upstream-tested |
| [row-embed](ui/row-embed.md) | 数据行一条条从上方落下，从斜的俯仰角放平，卡进页面里自己的行位，卡进去的那一帧底边闪一道强调色的缝 | 3 | 2.3–3.3 s | upstream-tested |
| [oversized-cursor](interaction/oversized-cursor.md) | 一只画面宽度 7% 的光标从画外进来，把视线带到下一个目标，点一下让下一件事发生，然后离开或带进下一镜 | 2–3 | 1–3 s | tuned |
| [type-and-filter](interaction/type-and-filter.md) | 在真实界面上按人手的速度打字搜索，网格自己收敛成一张卡，点击它，镜头推进交给详情 | 3 | 2.3–2.7 s | upstream-tested |
| [one-take-world-travel](camera/one-take-world-travel.md) | 一台镜头在同一个 3D 世界里从一个站点飞到下一个：甩过去、到站减速成慢推、停站时保留低幅漂移，字在读的时候骑在镜头前 | 2–5 | 3–8 s | tuned |
| [group-photo-launch](outro/group-photo-launch.md) | 每个展示过的功能派一个代表元素，从四面八方飞来围成合影，字标最后压印落款，全片能量最高 | 5 | 5–6 s | upstream-tested |

本库只收了一部分。shotcraft 的其余卡片（共 157 张）可以在它的[在线 Gallery](https://vincentwei1021.github.io/video-shotcraft/) 看样片，源码在 `references/repos/video-shotcraft/references/shots/`（Apache-2.0，只读）；借用时按下文"写一张新配方"改写进来。

## frontmatter

frontmatter 是 YAML 的一个严格子集：一行一个 `key: value`；值是普通或加引号的标量、`[列表]` 或 `{映射}`；没有值的键下面跟 `  - 项` 的块列表。不用锚点，不写多行标量。各家 YAML 解析器读法不一的写法，`bin/vh recipes check` 一律报错、不去猜：`yes`/`no`/`on`/`off`；带前导零、下划线、指数或冒号的数（`1:30` 在 YAML 1.1 里是 90）；日期；`{key:value}` 冒号后不空格；`[ ]`、`{ }` 里没加引号的 `?`；双引号里的反斜杠；既没有值也没有列表项的键。能通过校验的，PyYAML 读出来是同一个结果。`check` 还会逐项校验字段，并在词表和本文不一致时报错。

| 字段 | 必填 | 写法 | 说明 |
|---|---|---|---|
| `id` | 是 | `flash-cut` | 小写、连字符；和文件名一致；发布后不改 |
| `name` | 是 | `推进流白` | 中文名 |
| `one_liner` | 是 | 一句话 | 这一镜做了什么 |
| `family` | 是 | 词表 | 手法的类别，也是所在的目录 |
| `role` | 是 | `[feature, climax]` | 在片中的位置，词表 |
| `intent` | 是 | `[accelerate]` | 要观众明白什么，词表 |
| `energy` | 是 | `4` 或 `[3, 5]` | 0 最静，5 最响（六档的含义见 `sequences/README.md`）；接缝写它适用的能量范围 |
| `duration_f` | 是 | `[120, 135]` | 30 fps 下的帧数范围；接缝写它从两侧借走的帧 |
| `types` | 是 | `[promo, short]` | 适合的视频类型，和 `bin/vh new` 的类型名一致 |
| `engines` | 是 | `[canvas, hyperframes]` | 能做的引擎，词表 |
| `aspect` | 是 | `[landscape, portrait]` | 适合的画幅 |
| `needs` | 是 | `[ui-page]` | 需要的素材，词表；不需要素材写 `[none]` |
| `sound` | 是 | `required` | 声音依赖度 |
| `pitfalls` | 是 | `[too-fast, no-hold]` | 容易犯的错，词表；正文"已知坑"逐条展开 |
| `qa` | 是 | `{peak: 44, settle: 78}` | 验收帧：从配方第 0 帧起算（30 fps），键见词表 |
| `status` | 是 | `tuned` | 验证到什么程度，见"状态" |
| `derived_from` | 是 | 块列表 | 每项 `{repo, commit, path, license}`，可加 `note`。`repo` 写仓库地址（如 `github.com/Vincentwei1021/video-shotcraft`），`commit` 是借用时上游的提交（加引号的 7–40 位十六进制），`path` 是上游仓库里的路径；只来自拆解、`license: none` 的来源可以不写 `commit`。原创的写 `[]` |
| `jump` | 接缝必填 | `[level, rise]` | 这个接缝适合哪种能量变化 |
| `max_per_film` | 否 | `1` | 全片最多用几次 |
| `conflicts` | 否 | `[paparazzi-flash]` | 不能同片出现的配方；两边都要写 |
| `pairs_with` | 否 | `[breath-title-card]` | 常和它搭配的配方 |
| `impl` | 否 | `[showcase/04-intro-film/js/fx.js]` | 本仓库里已有的实现；`check` 会确认文件存在 |

骨架（`sequences/*.md`）用同一种格式，字段是 `id`、`kind: sequence`、`name`、`one_liner`、`duration_f`、`types`、`aspect`、`arc`（每一段的能量，如 `[1, 3, 4, 2, 5]`）、`uses`（用到的配方 id）、`status`、`derived_from`。`kind` 的取值是 `recipe`（缺省）或 `sequence`。

## 词表

词表只追加，不改名、不重排：已经发布的词不换含义。

**family**（手法的类别）：`open` 开场与品牌 · `type` 文字与字卡 · `ui` 界面登场与陈列 · `interaction` 交互演示 · `data` 数据与指标 · `camera` 运镜与空间 · `rhythm` 切点与节奏 · `fx` 光效与强调 · `seam` 接缝（转场） · `outro` 收尾

**role**（在片中的位置）：`hook` 前 3 秒的钩子 · `open` 开场 · `hero` 单主角立传 · `feature` 功能镜头 · `breath` 呼吸位 · `proof` 证据（数字、案例） · `climax` 高潮 · `outro` 收尾 · `seam` 接缝

**intent**（要观众明白什么），按组：

| 组 | 词 |
|---|---|
| 开场 | `hook` 抓住注意 · `promise` 承诺一个结果 · `brand-imprint` 记住名字 |
| 展示 | `hero` 这就是主角 · `abundance` 东西很多、源源不断 · `process` 一步步怎么做 · `compare` 前后或两者对比 · `transform` 从一样变成另一样 · `detail` 看清细节 · `locate` 它在哪里 · `connect` 它们之间的关系 · `count` 有多少 · `timeline` 随时间怎样 |
| 交互 | `interact` 跟着操作一遍 · `search` 找到它 · `generate` 它自己生成出来 |
| 节奏 | `breath` 喘口气 · `accelerate` 越来越快 · `punctuate` 重重一击 · `hush` 屏息 · `payoff` 兑现前面的铺垫 |
| 接缝 | `carry` 带着动量过去 · `enter` 钻进去看详情 · `chapter` 换章节 · `refocus` 同一空间里转移注意 |
| 收尾 | `sign-off` 落款 · `cta` 行动号召 |

**types**：`math` · `short` · `promo` · `mv` · `data` · `paper` · `handdrawn` · `meme`（即 `bin/vh types` 里除 `edit` 以外的 8 类；`edit`（09）剪用户自己的素材，暂无配方）

**engines**：`hyperframes` HTML/DOM + GSAP 的 composition · `canvas` 2D canvas 的 `renderAt(t)`（草图就是这种，在 HyperFrames 里跑） · `three` HyperFrames 里的 Three.js 层 · `p5` ClaudeAnimationBase · `manimgx` ManimGX · `remotion`（来源的参考实现，本仓库不首选）

**aspect**：`landscape` 16:9 · `portrait` 9:16 · `square` 1:1

**needs**（需要的素材）：`ui-page` 整页截图 · `ui-element` 元素级截图或组件 · `text` 文案 · `number` 数字 · `series` 数据序列 · `photo` 照片 · `footage` 视频素材 · `logo` 标志或字标 · `3d` 三维模型或场景 · `none` 不需要素材

**sound**：`required` 没有声音就不成立 · `recommended` 有声音明显更好 · `optional` 静音也成立

**jump**（接缝两侧的能量变化）：`rise` 往上走 · `level` 持平 · `drop` 往下落

**qa**（验收帧的种类）：`read` 第一条必读信息完整显示 · `peak` 动作最快、最满的一帧 · `seam` 转场正中 · `settle` 落定之后、hold 之中 · `last` 切走前的最后一帧

**status**：`battle-tested` · `upstream-tested` · `tuned` · `draft`（见下一节）

**license**（`derived_from` 里的许可）：`Apache-2.0` · `MIT` · `CC0-1.0` · `CC-BY-4.0` · `none`（只来自拆解分析，没有复制任何文字或代码）。`Apache-2.0`、`MIT`、`CC-BY-4.0` 的来源要带许可原文和 NOTICE 行，见"写一张新配方"。

**pitfalls**（容易犯的错）：

| 词 | 含义 |
|---|---|
| `too-fast` | 初版几乎总是偏快：动作弧、打字、hold 被压短 |
| `no-hold` | 落定之后没有静止就切走了 |
| `uniform-timing` | 等距、匀速、同时入场，读作机械 |
| `sub-threshold` | 预备动作、光效、位移的幅度低于肉眼能察觉的阈值，做了等于没做 |
| `float-not-land` | 飞入的元素悬在页面上方，没有落进真实的槽位 |
| `text-blur` | 推近或透视下字发糊（纹理分辨率不够），或者必读字压在运动模糊下面 |
| `dead-frame` | 纯黑、纯白或空的帧，读作断片或播放卡住 |
| `seam-mismatch` | 接缝两侧的方向、速度、轴线接不上 |
| `flash-rate` | 全屏闪有超过每秒 3 次的风险 |
| `glow-spill` | 光效溢出圆角、烧掉字，或者给每个元素都发一次光 |
| `overuse` | 用多了就失效，配合 `max_per_film` |
| `sound-dependent` | 没有声音就读不出节奏 |
| `mechanical-stop` | 所有层在同一帧停住，缺少先后 |
| `fake-ui` | 用手搓的仿真界面代替真实截图 |
| `off-axis-read` | 机位倾斜，信息密集的画面读不清 |
| `motion-sickness` | 连续甩镜或大幅旋转，看着晕 |
| `state-leak` | 状态依赖上一帧，乱序渲染的结果不一样 |
| `copy-drift` | 文案抽象、重复，或和画面对不上 |

## 状态

- `battle-tested`：本仓库做过的片子里用过，而且有人看过、给了判定，判定记在"已知坑"里。独立 reviewer 的打分不算判定。
- `upstream-tested`：来源项目的成片里用过，有用户判例，参数是判例定下来的；本仓库还没用过。
- `tuned`：实现过、调过，但还没有人给过判定：在灰盒或占位素材上调的（来源自己这样说明），或者用在本仓库还没有人看过的片子里（只过了独立 reviewer 的也在这一档）。
- `draft`：只来自拆解或描述，还没有人实现过。

`quick` 档只用前两种。一张配方在本仓库的片子里用过、有了人的判定，就升到 `battle-tested`，在"已知坑"里记下判例。showcase 00、04 用过的六张在"已知坑"里写了还差什么。

## 草图怎么跑

每张配方的"实现"一节给一段草图，写法是风格样片的场景接口（`styles/_swatch/README.md`）：一个 ES module，导出 `renderAt(t, ctx, tokens, lib)`，画在 1920×1080 的 canvas 上，`lib` 是 `styles/_swatch/lib.js`（缓动、`seg`、`hash`、`drawGlyphs`、`motionBlur` 等）。草图只读 `tokens` 里的 `bg`、`fg`、`accent` 三个颜色和 `display`、`body`、`zh`、`mono` 几个字体角色。大多数预设都有这些键；缺的时候 `lib.js` 的 `color()` 回退到前景色（`fg`、`ink`、`text` 依次找），字体角色回退到安全字体。

试一张草图，并且换一张皮：

```bash
mkdir -p /tmp/try && cp styles/swiss-grid-type/tokens.json /tmp/try/     # 皮：任选一个预设
# 把配方"实现"一节的代码块存成 /tmp/try/swatch.js
styles/_swatch/render.sh /tmp/try --draft --hud                         # → /tmp/try/media/swatch.mp4，联系表在 styles/_swatch/out/try/sheet.png
```

草图是 5 秒、30 fps（样片渲染器的固定长度），只为说明时序和结构，素材用灰盒代替。放进真实项目时，把灰盒换成截图，把时间换成分镜里的片内时间。

## 写一张新配方

1. 复制 [`_TEMPLATE.md`](_TEMPLATE.md) 到 `<family>/<id>.md`，按模板的节写，全文控制在 150 行左右。
2. 时间一律写 30 fps 的帧数，必要时附拍数；参数表标出 ★；验收帧写进 `qa`。
3. 从别处学来的，用自己的话重写，不整段搬原文和代码；只学时序、编排、缓动这类手法，不复刻具体的画面、文案和品牌。在 `derived_from` 写明仓库、commit、上游路径和许可，正文"来源"一节写清改了什么。来源是 `Apache-2.0`、`MIT` 或 `CC-BY-4.0` 的，还要做三件事（`check` 会查）：把它的许可原文逐字放进 `LICENSES/<许可>-<仓库名>.txt`；在"来源"一节末尾加一段"**许可**：本文件修改自 …"，写出上游文件、commit 和许可原文的链接（照现有配方的写法）；在 [`NOTICE.md`](NOTICE.md) 的表里加一行。
4. 在上面的索引里加一行，然后跑 `bin/vh recipes check`。

## 来源与许可

本仓库是 MIT 许可，但下面这些文件改编自 Apache-2.0 的项目，按 Apache-2.0 第 4 条处理。逐文件的清单在 [`NOTICE.md`](NOTICE.md)。

- **哪些文件**：17 张配方、3 条骨架和 `sequences/README.md` 修改自 [video-shotcraft](https://github.com/Vincentwei1021/video-shotcraft)（Copyright 2026 Wei Yihao）的镜头卡、demo 和全片骨架；`cut-the-curve`、`zoom-through`、`oversized-cursor` 三张修改自 [HyperFrames](https://github.com/heygen-com/hyperframes)（Copyright 2026 HeyGen, Inc.）的 skill。
- **许可怎么算**：来自上游的部分仍按 Apache-2.0，两个上游的许可原文连同版权行逐字放在 [`LICENSES/`](LICENSES/)；本仓库的改动按 MIT。把这些文件拿到别处用，要连同它的"许可"一段、对应的许可原文和 `NOTICE.md` 一起带走。
- **每个文件怎么标**：frontmatter 的 `derived_from` 写上游仓库、commit 和路径；正文"来源"一节先写改了什么（文字重写，参数按本仓库的规则改过，见上文"和原文不同"的几处），末尾一段"**许可**"写明本文件修改自哪些上游文件、在哪个 commit，并链接许可原文。
- **NOTICE 和署名**：两个上游在所用的 commit 都没有 NOTICE 文件，所以没有要转载的 NOTICE 文字；用到的上游文件里也没有单独的版权头，要保留的是两份 LICENSE 里的版权行。shotcraft 注明它的 B、C 两式转场来自对 Linear 发布片的抽帧逆向，这句话在 `dark-tunnel`、`focus-handoff` 的"来源"里保留了。
- **其余都是本仓库的**：原创的配方（`decode-type`、`gate-as-door`、`one-take-world-travel`，以及只来自拆解、没有复制任何内容的 `flash-stitch`）、本文、`_TEMPLATE.md` 和 `tools/recipes.py` 按 MIT。

shotcraft 的卡片本身研究自公开的商业片和个人作品，作者声明只取手法、全部重写；我们守同一条边界。拆解和取舍的全过程见 [`cases/promo-video-shotcraft.md`](../cases/promo-video-shotcraft.md)。同作者的 video-talkcraft、anything2explainer 是 PolyForm Noncommercial：`needs`（按输入素材筛）这个思路受 talkcraft 的输入类型索引启发，没有用它的文字和代码。
