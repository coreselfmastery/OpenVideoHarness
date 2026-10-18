# 档案推拉 · archival-pan-zoom

一句话：画面里只有静止的照片、信件和地图，镜头在上面极慢地推、拉、横移，去"发现"一张脸、一个签名、一行字；衬线字幕很克制，只写地点和日期。适合历史和人物传记、科学史、公司或项目的"来历"，以及需要庄重感的纪念内容。

样片：`media/swatch.mp4`（5 s，含 `score.json` 配乐）· 封面 `media/poster.jpg`（t = 3.0 s）

样片里：两张"照片"都在 setup 里用代码画出（没有下载任何图片）：一面木板墙上钉着手写大纲页（页脚有签名）、分镜纸和一张人像照片，另有一张风景照；统一调成暖色单色，墙面比纸更虚，带颗粒、划痕和轻微柔焦。第 0 帧镜头已经在动：2.3× 特写大纲页的笔迹和签名，0.05–0.35 s 拉焦。随后一路拉远，到 2.0 s 露出全板，人像照片在 2.0–2.6 s 随摇镜入画。2.8 s 褪色朱红圈画完，圈住人像的脸；3.2 s 小型大写那行换成"DRAFT · 初版 · FRAME 096"；之后推向人脸。4.0 s 在同向运动中叠化到风景照（已修右侧黑边）。字幕是 Baskerville 90 px 和宋体 60 px，下面垫一条压暗的底带。实际字体：Baskerville、Songti SC、American Typewriter（标签）。配乐是纪录片式的提琴哀歌，在 150 BPM 的网格上按半速写：独奏 `fiddle` 第 0 拍从下方滑进 A4，慢揉弦，经 D5 在 2.0 s 人像入画时升到最高的 F#5，再沿 B4–C#5（IV–V）落回 4.0 s 叠化时的长音 D5；第二条 `fiddle` 低 9 dB 拉空弦 D、A，和主旋律合成双音；毡锤 `piano` 在每个和弦上轻轻滚奏（D–G–Bm–G/A–D），最后一个和弦滚得最慢。不加鼓，几个长音比拍子晚 20–40 ms 进（rubato），`humanize` 0.3；小房间混响，声像几乎居中，像一次近距离录音，底下垫一层极轻的 `roomtone`。拟音只有三下：0.1 s 快门、2.45 s 画圈的笔声、4.0 s 叠化时的快门。拟音的落点写在 swatch.js 的 `FOLEY` 常量里，`events.json` 由它生成。

## 学习对象

| 作品 | 年份 · 作者 / 工作室 | 从它身上学什么 |
|---|---|---|
| 《黄金之城》*City of Gold*（中文为意译） | 1957 · Colin Low、Wolf Koenig（加拿大国家电影局 NFB）；制片 Tom Daly；旁白 Pierre Berton | 这一手法的源头：在淘金热时期的老照片上推、拉、摇，把照片当实景来"拍"，再配上旁白和音乐讲完一座城 |
| 《南北战争》*The Civil War*（9 集纪录片） | 1990 · Ken Burns，PBS；旁白 David McCullough；主题曲 Jay Ungar 的《Ashokan Farewell》（1982）。剪辑软件里的 pan-and-zoom 效果后来就以 Burns 命名 | 约 1.6 万张同时代的照片和绘画；镜头慢慢移向一张脸或一处细节；信件由不同的声音朗读；同一首提琴曲反复出现 |

核实：年份、署名、集数和照片数量来自 Wikipedia 与 NFB 页面；效果命名一事出自 Apple iMovie（见 Wikipedia 上以其命名的 effect 条目）。

**不照搬**：不用《Ashokan Farewell》或它的提琴旋律，不默认拿南北战争的照片当素材，不模仿原片旁白的嗓音和腔调；也不要做成幻灯片软件那种"每张照片随机缩放"的自动效果。

## 视觉语法

- **色板**：

  | token | hex | 语义 |
  |---|---|---|
  | bg 暗房黑 | `#121110` | 照片之间、画框之外 |
  | fg 象牙 | `#EDE6D6` | 字幕 |
  | accent 褪色朱 | `#9B2D20` | 全片只用来圈出、标出一处细节，或一个日期 |
  | extra 相纸棕 | `#C9B79C` | 照片高光的色调 |
  | extra 银灰 | `#7C7A74` | 次要字、分隔线 |
  | extra 蓝黑墨 | `#2E3440` | 手稿信件的墨色 |

  照片统一调成暖色单色：高光 `#E9DFC8`，暗部 `#2A241D`。彩色照片也降到饱和度 ≤ 20%，保证全片一个调子。
- **字体**：
  - 字幕用 Baskerville Regular（fallback Georgia），44–52 px；地点用小型大写字母加 0.08em 字距，日期用旧式数字；
  - 字幕左下角左对齐（x 96，离底边 108 px），不加底框，只加 alpha 0.4 的柔和阴影；
  - 引文卡用 Baskerville，64–72 px，居中，一次一行；
  - 中文字幕用 Songti SC Regular，48 px。
- **构图**：按"要看的那一点"取景。推近时，目标细节落在三分点上；横移的方向，和照片里人的视线或行进方向一致。照片可以铺满全屏（满屏裁切），也可以放在暗房黑底上、四周留 6–10% 的边（当作"一件文物"来展示），全片选定一种为主。
- **质感**：grain，强度 0.12；极轻的相纸纹理（0.05）。照片自带的划痕、霉点保留，不修。不加假的"老电影"闪烁。

## 运动语法

帧数一律按 30 fps 计。

- **三种镜头动作**，每个都要说得出目的：
  - **发现**：推近到一处细节，8–12 s 内缩放 1.00 → 1.15–1.35；
  - **揭示**：从细节拉远到全景，缩放反过来，1.35 → 1.00；
  - **扫读**：沿一排人、一行字或一条路横移，速度不超过每秒画面宽度的 3%。
- **缓动**：`cubic-bezier(0.37,0,0.63,1)`（easeInOutSine），但**切入时镜头已经在动**：每段动作只取曲线中间的 70%，去掉起步和停止。这样两张照片衔接时，不会出现"从静止起步"。
- **时长**：一张照片 5–12 s；一行字幕停 ≥ 3 s；每 4–6 s 一个新 read（新照片、新字幕，或推近到新的细节）。
- **转场**（全片只用这 3 种）：
  - 切，切在运动中，前后两张的运动方向和速度一致；
  - 运动中的慢叠化，18–24 帧，只在前后两张照片同向、同速运动时使用。承载它的是持续的镜头运动，这是本风格对"禁止无承载 crossfade"的规定用法；
  - 章节之间切黑 1–1.5 s，由音乐或旁白的留白托住。
- **镜头**：pan 加 zoom 的组合。禁止旋转、3D 透视翻转和视差分层；"2.5D 抠图视差"会破坏档案感，项目明确要求时除外。
- **文字动画**：整行淡入 12 帧、淡出 10 帧，不移动；多行时逐行 stagger，间隔 150 ms（纪录片节奏）。

## 声音语法

- **配乐**：独奏提琴、钢琴或民谣吉他的慢曲，72 BPM，D 大调。旋律简单，可以反复；全片一个主题，最多两个变奏。`bin/vh music` 的做法（`parts`）：一个 `fiddle` 主奏，慢揉弦（`vib` [5, 16, 0.3]），`scoop` 让每个音从下方滑进，首音再加一个 `slide`；另一条低 9 dB 的 `fiddle` 拉空弦当双音；`piano`（`tone: felt`）在强拍上滚奏和弦，每个音比前一个晚 0.05 拍；`roomtone` 垫底，`space` 用 room。不加鼓，长音比拍子晚一点进，加一点 `humanize`，就有 rubato 的感觉。样片的 `score.json` 就是这么写的。合成的提琴凑近听仍是合成的，要真乐器的质感，建议用有授权的录音；历史题材可以用公版曲目，但录音本身的许可要单独确认。
- **旁白是主角**：音乐在旁白下面压低 12 dB。信件和日记由第二个声音朗读，和旁白分开。
- **音效**：极少。
  - `shutter`（相机快门）只在"这张照片被拍下"的叙事点用；
  - 翻纸声用短而轻的 `whoosh`（−18 dB），配文献之间的切换；
  - 照片下面可以轻轻垫一点环境声，比如风、远处的声响。
- **声画关系**：推近的高潮点（细节完整进入画面）对准旁白里的关键词。章节切黑时，音乐留一个长音，不静死。
- **样片的转场音效**：`air`：红圈画上、镜头摇向肖像时一口很轻的气（0.7 s），不用 whoosh。

## 适合与不适合

- **适合**：06 论文讲解里的"研究史 / 背景"段；05 数据故事里的历史对照；02 历史和人物类知识短片；公司或项目的起源故事、纪念片、致敬片。
- **不适合**：没有真实素材的主题（这个风格靠素材，不能编造档案）；快节奏的竖屏 hook；产品功能演示。
- **容易被误用成**：每张照片都套同一个随机缩放；在照片上堆满标注框和箭头；用 AI 生成"老照片"冒充档案（违反 CLAUDE.md 硬规则 5，事实纪律）。

## 禁止项

1. 生成或伪造"历史照片"当作真实档案；素材的来源和许可没有记进 NOTES 素材台账。
2. 镜头运动没有目的：推近的终点不是一张脸、一个字或一处细节。
3. 从静止起步的推拉；前后两张照片运动方向相反的切。
4. 字幕加底框、加粗，或居中堆叠三行以上。
5. 旋转、3D 翻页、抠图视差、老电影闪烁滤镜。
6. 旁白和音乐一样响；片中出现数字静音。

## Prompt 块

```text
Visual style: archival documentary built only from still photographs, letters and maps. Every still is graded to one warm monochrome (highlights #E9DFC8, shadows #2A241D) and filmed with slow, purposeful camera moves: a push-in that discovers a face or a signature (1.00 → 1.25 over 8–12 s), a pull-back that reveals context, or a pan along a row of people or a line of handwriting (under 3% of frame width per second). Moves follow easeInOutSine but are already in motion at every cut; consecutive stills move in the same direction at the same speed and are joined by straight cuts or 18–24 frame in-motion dissolves; chapters end with a 1-second cut to black. Captions are a restrained serif (Baskerville): place in small caps, date in old-style figures, ivory #EDE6D6, lower left, no box, held for at least 3 s. One faded red #9B2D20 mark is kept for the single detail that matters. Film grain; no flicker, no rotation, no parallax. Sound: narration first, a slow 72 BPM D-major solo-instrument theme under it, and letters read by a second voice.
```

## 引擎做法

- 首选 HyperFrames：`<img>` 加 GSAP，对 transform 按 t seek。也可以用 Remotion，或 ManimGX 的 `ImageMobject`。纯函数的写法：`camera(t)` 返回 `{scale, x, y}`，照片的 transform 取它的逆。
- **取景**：给每张照片写一条 `{src, from: {cx, cy, z}, to: {cx, cy, z}, dur}`，坐标用照片的归一化坐标（0–1）。先在一张标注图上把目标细节框出来，再写数值。
- **"切入时已经在动"**：`p = 0.15 + 0.7 * easeInOutSine(u)`，u 是本段进度。
- **放大上限**：照片原始分辨率 ÷ 画面分辨率 ≥ 最终缩放倍数，否则会糊。建素材表时就把这个算好。
- **素材**：Library of Congress、各国国家档案馆、Wikimedia Commons 里的公有领域图片，逐张在 NOTES 里记下来源和许可。swatch 用程序生成的"照片"或公有领域图片，不用有版权的历史照片。
- **调色**：CSS `filter: grayscale(1) sepia(.35) contrast(1.05)`，或 WebGL 里一张 LUT。颗粒交给 ffmpeg。

## 自查重点

- 每次推拉的终点帧单独 crop：目标细节清楚、落在三分点上、没有因为放大而糊。
- 切点 strip：前后两张照片的运动方向和速度一致；叠化只出现在同向运动的两张之间。
- 字幕：地点和日期都来自素材台账，拼写和日期照抄出处。
- 1 fps 联系表：全片一个调色；褪色朱只出现在一处。
- 音频：旁白段落里，音乐比人声低至少 12 dB。

## 相关资源

- lemo-opuscar 里最接近的是 `halftone-dossier`（逐件出示证物的案卷叙事）和 `silent-film`（用字幕卡代替对白），见 `references/repos/lemo-opuscar/styles/<slug>/STYLE.md`（LemoLab，CC BY 4.0）。两者都偏印刷和胶片质感，本风格要的是更克制的纪录片。
- `video-types/06-paper-explainer.md`、`video-types/05-data-story.md`、`playbook/04-audio.md`（旁白、混音时压低音乐）、CLAUDE.md 硬规则 5（事实纪律）。
