# BRIEF

<!-- 由 agent 根据用户需求填写。standard / studio 在关卡 ① 给人看；quick 不停，人点名要定的事除外（CLAUDE.md"导演模式"）。花括号里的都要替换。 -->

## Spec
- Effort: standard  <!-- quick | standard | studio：做多认真，规则见 CLAUDE.md "努力程度"。用户在对话里说的优先 -->
- Director: default  <!-- 谁拍板：default = 按 Effort 的默认；人点名的写成 hook=own, character=own, packaging=own, rest=delegate（own 人选 / review 人过目 / delegate agent 定），stop=E3 加一个检查点。规则见 CLAUDE.md "导演模式"，对话里说的优先 -->
- Output: {W}x{H}, {fps} fps, exactly {N}s ({frames} frames)  <!-- 合成尺寸（代码按它写，4K 也照写 1080p 的尺寸）、帧率、时长；时长没定时写范围 {60–90}s。bin/vh check 拿成片对这一行和 Resolution 一行，对不上就失败（playbook/01 "规格"） -->
- Watch on: {watch}  <!-- 主要在哪看，定字号下限和可读性检查缩到多宽（playbook/03 §4）：phone 手机竖屏；feed 横屏片放在手机信息流里，竖着拿、不转屏；desktop 电脑，或手机转成横屏全屏。bin/vh new 按画幅填了默认值，人说了发在哪就照着改 -->
- Pace: normal  <!-- relaxed | normal | brisk：画面文字读得多从容，定 bin/vh readcheck 的目标（playbook/03 §2）。relaxed 讲解、论文、书信体，观众边读边想；normal 大多数片子；brisk 快剪、梗、卡点 MV。bin/vh new 给 math、paper 写 relaxed，meme 写 brisk，其余 normal。底线（够快读一遍）不随它变；某一段要换挡，在合成里标 data-pace -->
- Resolution: {res}  <!-- 交付哪几种，可以写多个：1080p、4k、1080p, 4k；4k 就是合成尺寸的 2 倍。默认 1080p。4k：照常按 1080p 写合成和字号，出片时渲成 4K（HyperFrames `render --resolution 4k`，竖屏 `portrait-4k`，方形 `square-4k`，4:5 没有 4K 预设；ManimGX `-r 3840x2160 --fps 30`；Remotion `--scale=2`）；canvas、Three.js 要按像素密度开大，否则会糊（engines/README.md"出 4K"）；手绘引擎暂不支持 4K；draft 用 1080p，出 4K 前先渲 4K draft 跑 bin/vh check --against <1080p 成片>，再裁帧看锐度 -->
- Review language: zh  <!-- zh | en：审阅页和审阅台的界面语言，按用户第一句话的语言定（bin/vh new --lang）；字幕和项目文档照旧用项目自己的语言 -->
- Engine: {HyperFrames | Remotion | ManimGX | ClaudeAnimationBase (p5.brush) | other}
- Platform / audience: {where it plays, who watches, sound-on or muted}
- Language: {zh-CN | en}, narration: {TTS voice | user recording | song | none}
- Deliverables: {final.mp4 (+ 9:16 / 3:4 cuts?), cover image?, SRT?}

## Content
- Concept (one line): {the device that makes the form tell the content, e.g. "the 3 seconds after Enter, slowed to 2 minutes, a clock always on screen". Chosen at gate ① from 2–3 concept cards (playbook/12-ideation.md); everything below follows from it}
- Specifics: {the 3–5 items from NOTES.md 素材清单 the film is built on: numbers, verbatim quotes, artifacts, each with its source}
- Spine (one line): {the story in one sentence: X wants/asks ___, but ___, so ___}
- Recurring motif: {one object/visual that evolves and pays off}
- What the viewer should know/feel at the end: {…}
- Source material: {paper path / product URL / data.csv / song path / script}

## Outline
<!-- 关卡 ① 的 3–7 段大纲（playbook/09-narrative.md 第 3 节）。段名按内容或阶段起，看名字就知道这段讲什么，例如"按下发送 / 信道编码与调制 / 基站接住"；起承转合、幕这类结构标签最多写进"标签"列，可以不写。
     审阅台按这张表画时间条（列名的约定见 tools/desk/README.md）；时间写"0–10 s"，有配乐时也可以加"小节"列。 -->
| # | 段落 | 标签 | 时间 | 观众看完知道 / 感到 | 关键画面 |
|---|---|---|---|---|---|
| 1 | {按内容起的段名} | {可不写：起 / 承 / 转 / 合} | {0–10 s} | {…} | {…} |

## Style
- Style refs (repo presets): {none}  <!-- styles/ 里拿来参考的预设，bin/vh new --style a,b 或 bin/vh style apply 会填；参考，不是规定：借了什么记进 DECISIONS.md，和它们不一样不用解释 -->
- Refs (2–3 named works): {…}
- Explicitly NOT: {what this film won't look like, and why, from the concept}
- Palette: bg {hex}, fg {hex}, accent {hex}  <!-- 默认一个饱和强调色；立意要几个颜色时，在 STYLE.md 写明每个颜色的意思 -->
- Type: {display} + {mono | serif}
- Motion: {从立意推出：缓动的语域、快慢、2–3 种转场、主方向；没想法时从 playbook/03 §1、§2、§6 的默认值起步。卡通、手绘照 ANIMATION_GUIDE.md}

## Text rules
- On screen at once: <= {8} words or {16} CJK chars per line; min sizes and the safe box follow Watch on (playbook/03 §4, §5): {numbers for this film}
- Reading time: the floor and the Pace target are TASTE_CHECKLIST #5 (`bin/vh readcheck`); exceptions in this film: {none}
- Navigation and pause pages: {none}  <!-- 章节进度条里不是当前一章的块、片尾的参考页：不按限时阅读算、字号低于下限，都要人本人同意，在提出它的那一站就问（playbook/03 §4"导航和暂停页"），同意了写成"进度条 6 块，当前块 44 px，其余 32 px；片尾参考页 32 px，停 4 s（REVIEW.md 关卡 ②）" -->

## Determinism
Every frame is a pure function of t (CLAUDE.md hard rule 1).

## Process
<!-- 流程见 CLAUDE.md 和 playbook/01-pipeline.md，这里不重抄；只记本片和默认流程不一样的地方，例如跳过的关卡（用户原话在 REVIEW.md）、多加的检查点。 -->
{none}

## Acceptance
- [ ] {e.g. hook readable within 1s with sound off}
- [ ] {e.g. every number matches source}
- [ ] {e.g. 45s ±0.5s, 1080x1920, loudness -14 LUFS}

## TYPE
- Type doc: {type doc}  <!-- 这类片子的默认做法在类型文档的"Prompt 增量块"里，立意定了再读：画幅、字幕规格、平台安全区这类类型参数照用，抄进上面各节；语域、配色、节拍顺序是默认口味，和立意冲突时以立意为准（playbook/12-ideation.md 第 6 节）。 -->
