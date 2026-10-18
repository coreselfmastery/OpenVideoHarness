# 02 知识 / 科普短视频（含竖屏）

**适用**：
- 30–90 秒的概念科普、冷知识、how-to、清单体；
- 抖音上 2–5 分钟的横屏知识中视频，见下文"变体：抖音横屏中视频"；
- 投抖音、B站、小红书、视频号、YouTube Shorts、TikTok；
- 没有真人出镜的 faceless 讲解。

**不适用**：
- 需要精确推导的数学，看 `01`；
- 论文，看 `06`，可以借本类的竖屏规格；
- 有真人口播素材要剪辑、加字幕和图解的，走 `09`（实验中）；只在已有口播上叠图解、不剪的，仍可走本类，再加 `playbook/05-hybrid-genvideo.md` 的 B 模式。

## 引擎

- **首选**：HyperFrames。`bin/vh new short <slug>` 会自动以竖屏初始化，不会往全局装 skill。
  - **短片或静音片**：读 `references/repos/hyperframes/skills/faceless-explainer/references/` 里的设计资料，手写一个 `index.html` 最快（最小写法见 `engines/README.md` 的"最小写法"）。showcase 02 就是这么做的。
  - **长片、有旁白、多场景**：可以走 HyperFrames 官方的 `/faceless-explainer` 工作流（每一帧派一个 subagent，带音频同步脚本）。它需要装插件或全局 skills（要用户同意），部分功能依赖 HeyGen 账号。
- **备选**：Remotion + `template-tiktok`（用 whisper.cpp 做字幕）。
- 穿插公式或几何片段时，用 ManimGX 单独渲染成片段，再嵌进来。

## 工作流

1. **定平台和画幅**：
   - 抖音、Shorts、TikTok、视频号用 1080×1920；
   - 抖音也可以做 16:9 横屏、2–5 分钟的中视频，见下文"变体：抖音横屏中视频"；
   - 小红书封面要 3:4；
   - B站知识区可以做 16:9 中长视频，信息密度可以更高；
   - 各平台的时长、封面和标题上限见下文"平台规格"。
2. **写 SCRIPT.md**：开头按钩子梯子写【综合】：
   - 0–1 s 让人停下：第 1 秒给出结论、反常识的数字或有冲突的画面，不放 logo，不说"大家好"；
   - 1–3 s 讲清看完能得到什么；
   - 3–6 s 给第一个小回报，证明承诺是真的。TikTok 官方说前 3–6 秒最关键，每个钩子都要兑现 [S2]；
   - 15 s 之前再给一个小问题或小回报【推测】，之后每 3–5 秒一个新的视觉回报；
   - 关卡 ① 给 2–3 张立意卡（`playbook/12-ideation.md`），每张带一个钩子、2 个标题和 1 个封面版式；人点名 `hook=own` 时，选定立意后再出 3 张不同类型的钩子卡（`playbook/10-hooks-and-packaging.md`）；
   - 字数按 `playbook/04-audio.md` 语速表的句内语速（知识科普 4.5–5.5 字/秒）乘 0.85 倒推，留出句间停顿：45 秒约 170–210 字。最终时长以 TTS 实测为准；
   - 长于 90 秒、要讲出起伏的，用 `playbook/09-narrative.md` 的节拍表。
3. **音频先行（有旁白时）**。静音版跳过这一步：时长由分镜的 reads 决定，字幕承载全部信息，而且必须静音可读。
   - 把旁白逐句写进 `audio/script.txt`，运行 `bin/vh tts <项目> <provider> [voice]` 生成 `voiceover.wav` 和 `timeline.json`。草稿用 `say`，正式版用 `gemini`、`minimax`、`dashscope` 或 `elevenlabs`（见 `playbook/04-audio.md`）；
   - 旁白要导演：整体语气用"像在跟朋友讲一个惊人的事实：好奇、有起伏，关键词重读"，每句再在 `[ ]` 里单独导演；有配乐时加 `--beats` 让每句从拍点起。细节见 04 篇"让声音有表情、有节奏"；
   - 要词级时间戳（逐字高亮的字幕）：生成时加 `--align gemini`，词级时间和对稿结果直接写进 `audio/timeline.json`（每句的 `words`，`bin/vh captions` 会用上）；需要 `GEMINI_API_KEY`，见 `playbook/04-audio.md` 的"词级时间和对稿检查"。要离线，用 whisper.cpp（`brew install whisper-cpp`），它没有封装，输出要自己整理进 timeline；
   - 删掉口水词，在 ≥250ms 的停顿处断句。
4. **分镜**：
   - 一镜一个观点，切点放在旁白短语的边界上；
   - 刀速由 reads 决定，不定目标刀数。电视研究里，剪辑引发定向反应，是因为它向观众引入了新信息 [S19d]；好莱坞电影里相邻镜头的长度越来越相关 [S20]。由此推出两条【综合】：每一刀都要带新信息（新构图、新事实、新视角）；成簇地快、成簇地慢，不用恒定的刀速；
   - 起点：钩子段 1.5–3 s，中段 3–5 s，"转"之前放慢，形状是"快 → 中 → 停 → 快 → 停"【综合】。流传的"TikTok 1.5–3 s、Reels 2.5–4 s、Shorts 教程类 3–5 s"是第三方统计，找不到原始数据【推测】。
5. **字幕**：
   - 单行，字号 72–90px，字重 800（macOS 的 PingFang SC 最粗只有 600，写 800 实测等于 600，要真 800 得自带字体，见 `engines/README.md`）。竖屏安全框只有 810px 宽，所以 72px 时每行最多 11 个汉字，90px 时最多 9 个。横屏 16:9 才能用到每行 16 字；
   - 只用一个强调色，每句最多强调 1–2 个关键词；
   - 不要永远固定在下三分之一，每 30 秒打破一次节奏；
   - 强调的分布大致是：70% 平常，20% 轻强调，8% 完全强调，2% 高潮；
   - 选一种主风格【综合】：逐句（讲解的默认）；关键词强调（大多数知识片）；逐词高亮（只给高潮段，约 2% 的时长）；大字报（1–3 个词占满画面，只给钩子和转折，130–170 px）；对话条（问答）；双语（主语言大、副语言小，适合横屏，竖屏宽度不够）；
   - **术语卡**（可选）：默认不上专业词；人想保留真实的术语时（一位用户的原话："信道编码、调制 这几个基础的通信概念是可以保留的"），每到一个环节，先亮一张小卡写这一关的名字（"信道编码"），紧跟一句大白话字幕解释它（"再添上一些多出来的 0 和 1：路上丢几个，也补得回来"）。术语卡是独立的一层，字号按"在哪看"的次要文字下限，整层去掉也不影响字幕；英文缩写（QAM、LDPC）默认也不上屏，人要了再加。写在 SCRIPT 字幕表的"术语"列；
   - 静音可读，有声更好。信息流里静音观看是常态：Meta 测过，加字幕的视频广告平均多看 12% [S16a]；美国的调查里 69% 的人在公共场合静音看视频，英国 18–24 岁的人有 80% 看电视时部分或全部时间开着字幕【二手】[S17a][S17b]；
   - 但无声观看更累：一项 161 人的眼动实验里，认知负荷明显升高、沉浸和愉悦下降，理解只略低（81% 对 78%）[S17c]；TikTok 也说自己是开声音的平台 [S2]。所以静音交付时同屏信息量减少，画面文字在 `playbook/03-motion-design.md` §2 的 Pace 目标上再留 0.5–1 s（或者 BRIEF 的 Pace 直接写 relaxed）（加多少没有数据【推测】）；
   - 竖屏短视频多数人静音看，旁白照常逐句上字幕。只有学习目标强、以有声观看为主的讲解（横屏的课程、B站长讲解），字幕才可以只留关键词和短句（Mayer 的冗余原则，见 `playbook/09-narrative.md` 第 4.2 节）【综合】；
   - 横屏字幕按 Netflix 的规范：中文每行 ≤ 16 字、≤ 9 字/秒、最多 2 行，不用逗号句号，用空格代替，问号、感叹号保留 [S18b]；英文每行 ≤ 42 字符、≤ 20 字符/秒、最多 2 行 [S18a]。
6. **安全框**：关键内容放在 x 90–900、y 330–1520 之内，背景可以铺满。UI 遮挡多少像素，官方没有固定值：TikTok 只说遮挡随比例、文案长度和格式变化，给的是可下载的模板 [S3]；第三方给的 TikTok 下沿从 324 到 640 px 不等【二手】[S23]。有长文案、带话题标签的平台（抖音、小红书），把字幕带放在 y ≤ 1440 以内，发布前拿真机截图叠在联系表上校准【推测】。
7. **交付**：
   - 视频在第 1 秒静音状态下就能看懂；
   - 另外出一张封面图：1080×1440（3:4）主图，关键元素放进中心 1080×1080，3:4、6:7、1:1 的裁切就都不丢字【综合】。标题、封面、前 6 秒承诺同一件事，版式见 `playbook/10-hooks-and-packaging.md`；
   - 可选导出 SRT 字幕。要交给人工精修，**不要承诺一键导出剪映草稿**：剪映 6.0 起本地草稿是加密的，`pyJianYingDraft` 只在 5.9 和 6.8 上测过导出，新版（10.x）有草稿被判损坏的报告。稳妥的做法是 `final.mp4` 加 `captions.srt` 加分层素材包，或者走 CapCut 国际版（明文草稿）、FCPXML、OTIO，做法和各自的限制见 `engines/editing.md` 的"导出"一节。

## 平台规格（2026-10-01 核对）

发布前以创作者后台为准。中文平台的官方规格页要登录或由 JS 渲染，读不到正文；标【二手】的是几个第三方页面说法一致、没有官方佐证 [S23]。来源编号和 `playbook/10-hooks-and-packaging.md` 一致。

| 平台 | 画幅与分辨率 | 时长上限 | 封面 | 标题 / 文案 |
|---|---|---|---|---|
| YouTube Shorts | 竖屏或方形，上传上限 1080p [S5] | 3 分钟：2024-10-15 起上传的方形或竖屏、不超过 3 分钟的视频归为 Shorts [S4] | 在 Shorts feed 里作用弱 [S9] | 标题 ≤ 100 字符，描述 ≤ 5000 字符 [S10] |
| TikTok | 9:16 全屏，不低于 720P [S2]；广告建议 ≥ 540×960 [S3] | 自然内容 2021-07-01 起可到 3 分钟 [S1b]；10 分钟、60 分钟的测试只见媒体报道 | — | 文案 4000 字符【二手】 |
| 抖音 | 1080×1920 是行业默认；横屏 16:9 也有（10-04 补：案例里的 10 支抖音 AI 动画，赞数最高的四支都是横屏，`cases/douyin-vibe-knowledge.md`） | 和账号权限有关，说法不一 | 主页按 3:4（1080×1440）展示，9:16 封面上下被裁【二手】 | 没核实 |
| B站 | 竖屏 9:16、横屏 16:9 都可投 | 没核实；中长视频是主场 | 上传推荐 1146×717（16:10）【二手】；网页信息流按 16:9 显示，底部一条是播放、弹幕数和右下角的时长（2026-10-01 网页实测，`playbook/10` [S25]；`bin/vh cover-preview` 按这些格子出图） | 标题 ≤ 80 字【二手】 |
| 小红书 | 竖屏 9:16 或 3:4 | 15 分钟（2020-08 媒体报道）[S15a]；2026 年媒体报道平台在推 2 分钟以上的中长视频、4K 和横屏播放器 [S15b] | 4:3、3:4、1:1 三选一，3:4 展示面积最大【二手】 | 标题 ≤ 20 字【二手】 |
| 视频号 | 从竖屏 6:7（1080×1260）到横屏 16:9，9:16 只保证中间 6:7 完整【二手】 | 30 分钟【二手】 | 信息流 6:7【二手】 | 没核实 |

时长上限对本类的竖屏主线（30–90 s）影响不大，但要知道 Shorts 已经到 3 分钟，小红书在往 2 分钟以上推。长度由信息量和 reads 定，不为凑平台惯例加减内容；第三方的"平均时长"统计只当背景【推测】。

## 变体：抖音横屏中视频（2–5 分钟）

案例里的 10 支抖音 AI 动画（9 支发于 2026 年 9 月底，多数挂 #vibe知识大赏 话题），赞数最高的四支（15 万到 67 万赞）都是 16:9 横屏、2.5–5 分钟（`cases/douyin-vibe-knowledge.md`）。要讲一个有名的概念，又需要一点故事和推导时，可以不压进 90 秒的竖屏，直接做横屏中视频。

- **建项目**：`bin/vh new short <slug> --aspect 16:9`。画幅 1920×1080，`Watch on` 默认是 `desktop`（电脑，或手机转成横屏全屏）。BRIEF 末尾会多一行提示：Prompt 增量块里按竖屏算的尺寸（安全框、每行字数、字号）都按横屏重算；取用 Prompt 增量块时，这几行换成下面的横屏版（TYPE、Captions、Safe box、Cover 各一行，Hook text 并进 Captions）：

  ```text
  + TYPE: landscape knowledge film for 抖音. 1920x1080 30fps {120–300}s, zh-CN narration + burned-in captions. Watch on: desktop.
  Captions: <=16 CJK chars per line, <=2 lines, 56–64px (desktop floor 48), weight 800 (or the heaviest weight the local font has), #F5EFE6 with 3px dark stroke; an English line one size smaller. Hook text >=150px so the hook reads in the feed.
  Safe box x 96–1824, y 54–1026 (EBU 90% graphics-safe); the bottom ~17% is the caption band.
  Cover: 1920x1080 (16:9) master; how the 抖音 profile grid (3:4) crops a landscape cover is unverified, so keep the title in the centre.
  ```

  用 `--watch feed` 建项目时，把 TYPE 行末尾的 desktop 改成 feed，Captions 改到 ≥ 115px（每行字数跟着减）。

- **按哪一档的字号**：`playbook/01-pipeline.md` 把"横屏片发抖音"归到 `feed` 档（字幕 ≥ 115）。这个变体默认按 `desktop` 档（字幕 ≥ 48），是有意不同：案例里量的两支，字幕按 1080p 换算约 42–56 px，在 `desktop` 档附近，一支略低，看起来是按"点开全屏、横过来看"做的；观众是不是多半会点开全屏，抖音没有公开数据【推测】。片子主要会被竖着刷过、不会被点开的，建项目时加 `--watch feed`。
- **钩子的字**：观众决定点不点开，是在竖着拿的信息流里，那时画面只有约 360 px 宽。想让钩子在信息流里也读得出，可以把那几秒的字做到 `feed` 档（主标题 ≥ 150）。案例里开场的字都比正文大得多，但不一定到这一档：一支第一帧满屏一个"37%"，大约占画面高度的一半；另一支开场那行诗目测约 100 px。做完把前 2 s 的 strip 缩到 360 px 宽再看一次（`playbook/02-verification.md` 的手机测试；`desktop` 档的联系表只缩到 640）。
- **字幕**：照第 5 步的横屏规范（每行 ≤ 16 字，最多 2 行）。可以加英文，英文那行小一号。
- **时长和结构**：
  - 2–5 分钟，超过 90 秒，用 `playbook/09-narrative.md` 的节拍表排起伏；第 2 步的钩子梯子照用。
  - 这批里赞数最高的几支，有几处排法相似：开场用一个具体的场景，中段用一串带年份的人和事讲机制，最后收在一句话上。这只是一种排法，立意需要的话可以完全不同（`playbook/12-ideation.md`）。
  - 同一个题目也可以换载体和落点，例如案例里的两支 37% 法则：一支跟着开普勒的 11 次相亲走，一支用抽象模型配一句人生感悟。
- **文案和系列**：
  - 抖音简介可以写成一段短文：复述论点，带年份、人名和出处，改编过的地方注明；
  - 标题用固定格式，方便做成系列，例如"话题｜《题目》——副标题"。
- **没核实**：抖音信息流里横屏视频怎么显示、多少人点开全屏、横屏封面怎么裁，都没有官方数据。发布前用真机看一眼信息流里的样子。

## 推荐与留存：各平台公开说了什么

| 平台 | 公开说法 | 对创作的含义 |
|---|---|---|
| TikTok | For You 的因素分三类：用户互动、视频信息（文案、声音、话题）、设备与账号设置；"是否从头到尾看完一个较长的视频"这类强信号，权重大于弱信号（2020-06-18）[S1] | 较长视频的"看完"更值钱，不为完播把该讲的砍掉 |
| YouTube Shorts | 2025-03-31 起，view 是 Short 开始播放或重播的次数，没有最短观看时长；旧口径改叫 engaged views，在 Analytics 里并列 [S6]。Studio 里有 Viewed vs swiped away（在信息流里停下来看的比例）【二手】[S8]。留存曲线整体缓降，下凹是被跳过或离开，尖峰是被重看或分享 [S7] | 重播会涨 view；开头 1 秒决定划不划走 |
| 抖音 | 预估点赞、完播、评论、分享、关注、长期消费等行为的概率，乘各自的价值权重排序；完播率是 15 秒时代的核心目标之一，视频变长后改成多目标，例如用收藏率把知识类内容推给有需要的人（2025-04-15 官方公开活动，媒体转述）[S11] | 别只为完播剪；知识类的收藏被官方点名 |
| 视频号 | 主要靠社交关系推荐，多位朋友推荐的内容排序更靠前（2025-04，媒体转述）[S12]；官方文本是否点名完播率，来源不一致【推测】 | 做"愿意转给朋友"的东西 |
| B站 | 公示的正向信号有播放、点赞、投币、收藏、关注、分享，负向有点踩、不感兴趣；排序后还要去重、打散（2023-05，媒体转述）[S13] | 官方没点名完播率，"完播率权重最高"是流传说法【推测】 |
| 小红书 | 没找到官方公式，流传的 CES 加权（点赞 1、收藏 1、评论 4、转发 4、关注 8）出自二手文章【推测】[S15c]；2026 年媒体报道 2 分钟以上视频的推荐周期延长到 90 天 [S15b] | 知识类靠收藏；2 分钟以上也值得做 |

- 共同点：强信号是用户的主动行为加"看完"，没有谁说完播率是唯一指标。所以不做"为完播而缩水"，做"每 3–5 秒一个新回报、结尾有回报"；钩子之后、中段、结尾各一次小回报，比一个靠前的大钩子更稳【综合】。
- 网上流传的目标值（"3 秒留存 ≥ 60%""15 秒视频完播 ≥ 50%""互动率 ≥ 3%"之类）没有官方出处，只见于二手文章【推测】[S24]。不写进 BRIEF 当验收项；验收用能自查的条目，例如"静音第 1 秒看得懂""承诺在 6 s 内兑现"。

## 审美要点

- **"Kurzgesagt meets Fireship"**（扁平矢量图形、一个强调色、冷幽默、100 秒讲清一件事，按 what / why / how / when 组织）是这一类常见的做法之一【综合】。没有立意时可以从它起步；想立意时，它就是"同题的视频都长什么样"的答案之一（`playbook/12-ideation.md` 第 3 节）。
- **中文圈可点名的参考**：
  - 回形针 PaperClip：高信息密度的可视化；
  - 小 Lin 说：口播加图解；
  - 小红书封面：大字、高对比、系列化模板。
- **结尾**：落在回报画面上，不放"关注我"卡片。回环按长度选【综合】：
  - ≤ 30 s 的奇观、解压、测验：硬回环，末帧等于首帧，第 0 帧本身就是完整画面（文末 claude-faceless-shorts-creator 的做法），做循环接缝检查（`playbook/02-verification.md`）；
  - 45–90 s 的讲解：软回环，回扣开头的画面或句子，带一处变化，比如开头问"为什么……"，结尾接"所以……"；
  - 2 分钟以上或系列：软回环，或者留一个指向下一期的小缺口，前提是真的有下一期；
  - 有配乐时，音乐在小节线处回到起点。

  YouTube Shorts 的重播也计 view [S6]，其他平台对重播的权重没有官方说法【推测】。不要为了能循环砍掉结论，也不要切到一张静态的结束卡。
- **平台差异**（官方说法和经验说法分开写）：小红书的知识类靠收藏，封面和标题同时承担搜索和点击，适合系列化模板；B站知识区是中长视频，封面在网页信息流里按 16:9 显示，标题可以长一点；视频号为"愿意转给朋友"设计；YouTube Shorts 的缩略图作用弱，力气花在第 0 帧 [S9]。

## 禁止

- 每个字都上色、描边、放大的"全程 Hormozi 体"；
- 字幕落进平台 UI 遮挡区；
- 蓝紫科技渐变配粒子背景；
- 图库图标；
- 不留停顿的 TTS；
- 超过 3 秒画面没有任何变化；
- 钩子里承诺的东西，片子里没有；
- 标题或封面与内容严重不符（`playbook/10-hooks-and-packaging.md` 的红线）；
- 为了能循环砍掉结论；
- 封面上的关键文字落在中心 1:1 方块之外。

## Prompt 增量块

```text
+ TYPE: vertical knowledge short. 1080x1920 30fps {30–60}s, {zh-CN narration + burned-in captions | SILENT: captions and visuals carry everything, timing from storyboard reads}. Platform: {抖音 | 小红书 | 视频号 | B站 | Shorts}.
Style: {follows from the concept (playbook/12-ideation.md) | default: "Kurzgesagt meets Fireship": flat vector shapes, one accent, dry humor}. NOT (defaults; a concept may override any of them, one line each in DECISIONS.md): blue-purple tech gradients, particle backgrounds, stock icons.
0–1s: the counterintuitive claim/number as a full-bleed visual (no logo, no greeting). By 3s: what the viewer will learn; by 6s: a first payoff that proves it.
Hook (gate 1): each concept card carries one hook, typed from {question | counterintuitive | result-first | conflict | curiosity-gap}, optionally with a pattern interrupt: its first frame, first caption (<=11 CJK chars/line), the promise, the payoff time (first micro-payoff <=6s), and the fact source in NOTES.md. Three hook cards of different types only when hook=own, after the concept is picked.
A new visual payoff every 3–5s; one idea per shot; cut on narration phrase boundaries.
Captions: one line, <=11 CJK chars at 72px (<=9 at 90px; the vertical safe box is 810px wide), 72–90px, weight 800 (or the heaviest weight the local font has, e.g. PingFang SC 600), #F5EFE6 with 3px dark stroke; accent on 1–2 key words max; split at pauses >=250ms; drop filler words. Hook text 140px.
Caption style: {sentence | keyword emphasis | word highlight (<=2% of runtime) | big-type for the hook}; silent-readable, sound-on better.
Safe box x 90–900, y 330–1520 (platform UI zones stay clear). End on the payoff visual, not a subscribe card.
Loop: {soft callback (default for explainers) | hard loop: last frame == first frame | none}.
Cover: 1080x1440 (3:4) master with all key elements inside the central 1080x1080; title, cover and the first 6s make the same promise.
```

## 自查重点

- 静音观看时，第 1 秒能看懂在讲什么吗？
- 字幕有没有进入遮挡区？
- 有没有超过 3 秒的死画面？
- 数字和事实在 `NOTES.md` 里有出处吗？
- 最好拿一张平台截图叠在联系表上，检查 UI 遮挡。
- 三张钩子卡是不是不同类型，并且由人选定了？承诺和兑现的时间点写进 `NOTES.md` 了吗？
- 标题、封面、前 6 秒的承诺一致吗？标题里的数字有出处吗？
- 封面缩到约 200 px 宽还读得出吗？关键字在中心 1:1 内吗？
- 选了硬回环的，做过循环接缝检查吗？

## 可参考的案例与源码

- `showcase/02-short-leo-doppler/`：本仓库的竖屏样板，BRIEF、STORYBOARD、NOTES、源码和旁白 + 字幕 + 混音的 `tools/build_audio.sh` 都在。
- `cases/explainer-interstellar-blackhole.md`：一个着色器贯穿全片的长讲解，拉片拆解。
- `cases/community-prompts.md`：@AxtonLiu 的口播图解做法、@dotey 的中文讲解 prompt。
- `cases/douyin-vibe-knowledge.md`：10 支抖音 AI 动画（9 支发于 2026-09 底）。赞数最高的四支都是横屏，长 2.5–5 分钟；案例记了它们的几处相似、实测的字幕大小、一个号连发 15 支的赞数分布，以及同一个题目（37% 法则）的两种做法。
- `references/repos/hyperframes/skills/faceless-explainer/`：
  - `SKILL.md`：完整流程，包括 BRIEF → frame.md → STORYBOARD → 音频 → 线框草图 → 每个 frame 派一个 subagent；
  - `references/` 下的 `story-design.md`、`visual-design.md`、`motion-language.md`、`cut-catalog.md`。
- `references/repos/hyperframes/skills/embedded-captions/references/`：`aesthetic-principles.md`、`anti-patterns.md`、`caption-grouping.md`、`layout-heuristics.md`，这些是字幕设计最全的资料。
- `references/repos/remotion-skills/skills/remotion-captions/`：Remotion 路线的字幕做法。

## 社区 skill 参考

以下条目选自 183 个社区视频 skill，完整对照和许可证说明见 `references/community-skills.md`。只读参考；复用代码前，先确认它的许可证。

- **claude-faceless-shorts-creator**（MIT）：节拍语法 HOOK → SETUP → QUIZ → REVEAL → TWIST → LOOP；第 0 帧就是完整画面，末帧等于首帧，可以无缝循环；不放"评论区告诉我"式的 CTA。见 `references/repos/faceless-shorts-creator/_upstream_claude/skills/make-short/SKILL.md`。
- **procedural-film**（MIT，不在 183 个 skill 的清单里）：零媒体素材的 30 秒竖屏短片，一个镜头一个 agent；六项关卡 `check.cjs` 从桩场景那一步起就必须全绿，确定性检查把首、中、尾帧按正序、倒序、冷启动分别画出来比哈希；竖屏底部 380px 留给平台 UI。见 `references/repos/procedural-film/skills/procedural-film/SKILL.md`。
- **gbro-collage-info**（MIT）：竖屏半调纸拼贴信息动画，纯 HTML/GSAP，不用图像模型；信息只放在上 2/3，底部 640px 留给字幕。见 `references/repos/gbro-collage-info/SKILL.md`。纸拼贴 / Vox 风的三种做法对比见 `references/community-skills.md` 第 4 节。

## 来源

调研日期 2026-10-01，编号和 `playbook/10-hooks-and-packaging.md` 的来源表一致。括号里是等级和读取情况：官 = 平台或机构的官方页面，论 = 论文，媒 = 新闻、行业媒体或二手转述，搜 = 只读到搜索摘要；读 = 读了原页。

- [S1] TikTok Newsroom, "How TikTok recommends videos #ForYou", 2020-06-18: https://newsroom.tiktok.com/en-us/how-tiktok-recommends-videos-for-you （官 / 读）
- [S1b] TikTok Newsroom, "More Tok on the Clock: Introducing longer videos on TikTok", 2021-07-01: https://newsroom.tiktok.com/longer-videos?lang=en （官 / 读）
- [S2] TikTok, "TikTok Creative Made Simple"（官方 PDF）: https://ads.tiktok.com/business/library/SMB_Creative_Playbook_External.pdf （官 / 读，文本抽取）
- [S3] TikTok Ads Help, "Video ad specifications": https://ads.tiktok.com/help/article/video-ads-specifications?lang=en （官 / 读）
- [S4] YouTube Help, "Understand three-minute YouTube Shorts": https://support.google.com/youtube/answer/15424877 （官 / 读）
- [S5] YouTube Help, "Get started creating YouTube Shorts": https://support.google.com/youtube/answer/10059070 （官 / 读）
- [S6] YouTube Help, "What's new in Studio Content Manager"（Shorts 播放量口径）: https://support.google.com/youtube/answer/9082582 （官 / 读）
- [S7] YouTube Help, "Audience retention report": https://support.google.com/youtube/answer/9314415 （官 / 读）
- [S8] YouTube Community, "New YouTube Shorts Metric – Viewed vs Swiped Away"（正文没读到，定义取自二手描述）: https://support.google.com/youtube/community-video/273390203
- [S9] YouTube Blog, "YouTube Shorts deep dive: a conversation with Todd Sherman and Jenny Hoyos": https://blog.youtube/creator-and-artist-stories/youtube-shorts-deep-dive/ （官 / 读）
- [S10] YouTube Help, 标题与描述的字数上限: https://support.google.com/youtube/answer/57404 （官 / 读）
- [S11] 抖音公开推荐算法原理的媒体报道：新浪财经 2025-04-02 https://finance.sina.com.cn/wm/2025-04-02/doc-inertmqz3816189.shtml ；新浪财经 2025-04-16 https://finance.sina.com.cn/roll/2025-04-16/doc-inetirww6989013.shtml ；财联社 https://www.cls.cn/detail/2007317 （媒，转述官方 / 读）
- [S12] 新榜《微信视频号公开算法推荐原理》: https://newrank.cn/article/detail/30829 （媒，转述"微信珊瑚安全" / 读）
- [S13] 人人都是产品经理《B站的推荐算法机制大揭秘》: https://www.woshipm.com/ai/5851759.html （媒 / 读）
- [S15a] 网易科技《小红书上线视频号，支持 15 分钟时长视频发布》，2020-08-17: https://www.163.com/tech/article/FK7RC3T200097U7R.html （媒 / 读）
- [S15b] 虎嗅《小红书获 2026 世界杯转播权…全面押注中长视频》: https://www.huxiu.com/article/4861801.html （媒 / 读）
- [S15c] CES 加权的流传说法（搜索结果，没有官方原文）: https://www.woshipm.com/operate/3463792.html
- [S16a] Meta, "Capture Attention with Updated Features for Video Ads"（页面无日期）: https://www.facebook.com/business/news/updated-features-for-video-ads （官 / 读）
- [S17a] Verizon Media 与 Publicis Media 2019 年调查，经 Forbes 转述（只读到搜索摘要）: https://www.forbes.com/sites/tjmccue/2019/07/31/verizon-media-says-69-percent-of-consumers-watching-video-with-sound-off/
- [S17b] Stagetext 2021 年调查（只读到搜索摘要）: https://www.stagetext.org/news/yougov-survey-supports-stagetexts-findings/
- [S17c] Szarkowska et al., "Watching subtitled videos with the sound off affects viewers' comprehension, cognitive load, immersion, enjoyment, and gaze patterns", PLoS ONE, 2024: https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0306251 （论 / 读）
- [S18a] Netflix, English Timed Text Style Guide: https://partnerhelp.netflixstudios.com/hc/en-us/articles/217350977-English-Timed-Text-Style-Guide （官 / 读）
- [S18b] Netflix, Chinese (Simplified) Timed Text Style Guide: https://partnerhelp.netflixstudios.com/hc/en-us/articles/215986007-Chinese-Simplified-Timed-Text-Style-Guide （官 / 读）
- [S19d] Lang, Zhou, Schwartz, Bolls, Potter, "The effects of edits on arousal, attention, and memory for television messages", J. Broadcasting & Electronic Media 44(1), 2000（只读到搜索摘要：39 名大学生，唤起和记忆随剪辑频率增加而增加）；Potter, Bolls, Lang, Zhou et al., "What is it? Orienting to structural features of radio messages", 1997: https://files.eric.ed.gov/fulltext/ED415554.pdf （论 / Lang 2000 搜，ERIC 读）
- [S20] Cutting, DeLong, Nothelfer, "Attention and the evolution of Hollywood film", Psychological Science 21(3), 2010: https://journals.sagepub.com/doi/10.1177/0956797610361679 （论 / 读摘要）
- [S23] 第三方的规格和安全区数字（只读到搜索摘要，没有官方佐证），具体网站列在 `playbook/10-hooks-and-packaging.md` 的来源表
- [S24] 中文短视频"黄金 3 秒"的二手总结: https://www.woshipm.com/operate/6181785.html 、https://www.ixunke.com/article/562 （搜）
