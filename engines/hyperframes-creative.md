# HyperFrames 创意层（转场、特效、动态字、粒子、标记、配色）

速度层（[`remotion-speed.md`](remotion-speed.md)）管的是**多快出画面**；本页管的是**画面本身有多厚**：`styles/_swatch/lib.js` 在原有 12 件工具（纹理、四种转场、着色器原语）之上加了一整套创意包——4 种 2D 转场、7 种 GLSL 像素级转场、4 种后期特效、逐字编排、种子化粒子、文字标记、配色推导——全部是 t 的纯函数、全部带种子、全部在交付渲染器上逐字节确定。样片测试卡 `catalog-fx`（一格一个效果）和一条命令 `tools/hf_creative.sh` 是这层的入口。

> **实测口径（2026-10-19，Linux 沙箱 headless，2 核 CPU、无 GPU，SwiftShader 软件渲染）**：本页标【实测】的是在沙箱里真渲过的——`catalog-fx` 草稿渲染（150 帧 1920×1080，2 worker，18–19 s，无错误卡）、确定性检验（1 worker 对 3 worker，PNG 序列逐帧比对：**150/150 逐像素相同，含全部 7 个 GLSL 转场**）、回归（`demo`、`catalog` 两张既有测试卡在新 lib.js 下照常渲染）、视觉核对（VLM 逐格检查 24 格全部有内容、无错误卡）、`hyperframes catalog --query "shader transition"`（121/447 条命中，词匹配模式）。标【源码】的是读 `lib.js` 的行为。沙箱里 `hyperframes browser ensure` 的下载器曾停在 0 %——直连 `storage.googleapis.com/chrome-for-testing-public/<版本>/linux64/chrome-headless-shell-linux64.zip` 手动解压到 `~/.cache/hyperframes/chrome/chrome-headless-shell/` 并写 `.version` 即可，是环境问题不是引擎问题。

## 要点

| | |
|---|---|
| 库 | `styles/_swatch/lib.js`（场景 `import * as lib` 后即得；harmony/ramp 这类纯函数在 Node 里也能跑） |
| 测试卡 | `styles/_swatch/render.sh catalog-fx`：24 格一格一个效果 + 2.4–5.0 s 三个 GLSL 转场全屏 |
| 一条命令 | `tools/hf_creative.sh --fx`（清单）· `--palette <hex> --scheme triad`（配色，直接跑 lib.js 的函数）· `--blocks "<描述>"`（HyperFrames 注册表）· `--add <block> <项目>` · `--demo`（渲测试卡） |
| 2D 转场 | `dissolve`（种子块溶解）、`push`（推挤）、`blinds`（百叶窗）、`zoomDip`（黑场推拉切）——签名和 `wipe/iris/whip` 一致：`(ctx, u, drawA, drawB, opts)`【源码】 |
| GLSL 转场 | `shaderTransition("dissolve", …)` 一行一个：dissolve / glitch / zoomBlur / kaleido / shockwave / lightLeak / warpMorph；`fx.render(u, canvasA, canvasB)` 返回画布【实测】 |
| 后期 | `glow`（半分辨率 bloom）、`duotone`（SVG 滤镜双色映射）、`lightLeak`（漏光）、`shimmer`（扫光，按周期循环） |
| 逐字编排 | `drawKinetic(ctx, lay, t, { mode: rise\|pop\|wave\|cascade\|jitter })`；底层原语 `glyphAnim(i, n, t, opts)` |
| 粒子 | `particles(ctx, t, { mode: drift\|rise\|fall\|orbit\|stream, … })`：fall 就是彩纸（颜色默认取 color 的种子 harmony）；整条命是 t 的纯函数，循环无接缝 |
| 文字标记 | `marker(ctx, box, t, { mode: highlight\|underline\|circle\|strike\|brackets })`；highlight 画在字**前**（垫底），其余画在字后 |
| 配色 | `harmony("#E4572E", { scheme, count, seed })`（analogous/complementary/split/triad/tetrad/mono）、`ramp(stops, u)`（梯度取色） |
| 确定性 | 和既有工具同一张契约：种子化、缓存、t 的纯函数；`determinism.sh catalog-fx` 1 worker 对 3 worker **150/150 逐像素相同**【实测】——GLSL 走 SwiftShader（同一台机器上逐字节相同），这是交付路径（`--no-browser-gpu`）的口径 |
| 性能 | GLSL 转场每像素都过一遍片段着色器，SwiftShader 在 CPU 上算：**全屏转场用半尺寸 FX 画布**（`{ width: W/2, height: H/2 }` 再 drawImage 放大）约省 4 倍；catalog-fx（24 格 + 3 个全屏 GLSL，均半尺寸）草稿 18–19 s，对比 catalog 16 s、demo 11–16 s【实测】 |

## 创意清单

`tools/hf_creative.sh --fx` 随时打印（和 lib.js 同步维护）；这里给分组和用法。所有转场的 `drawA/drawB` 是画**整帧**的 painter（画进 layer，不一定是主画布），和 `wipe/iris/whip` 的约定相同。

**转场（2D）**【实测】：

```js
lib.dissolve(ctx, u, A, B, { cell: 26, seed: 1 });   // 块溶解：格子按 hash 顺序翻面，硬边是刻意的
lib.push(ctx, u, A, B, { dir: [1, 0] });             // A 沿 dir 滑出，B 从对边进
lib.blinds(ctx, u, A, B, { bands: 7, angle: 0, stagger: 0.5 });  // 百叶窗，band 0 带头其余跟
lib.zoomDip(ctx, u, A, B, { zoom: 1.5 });            // 半程把 A 推大并压黑，半程把 B 从大落到 1——卡点切不闪白
```

**GLSL 转场**【实测】——一行一个，编译一次按 name+尺寸缓存：

```js
const fx = lib.shaderTransition("shockwave");            // setup 里建，renderAt 里用
// 渲染时：A/B 是整帧画布（lib.offscreen(name, drawA) 是惯用造法）
ctx.drawImage(fx.render(u, aCanvas, bCanvas), 0, 0);
// 半尺寸（SwiftShader 上约 4 倍速，放大后看不出差）：
const fxHalf = lib.shaderTransition("shockwave", { width: lib.W / 2, height: lib.H / 2 });
ctx.drawImage(fxHalf.render(u, a, b), 0, 0, lib.W, lib.H);
```

七个名字的口味：`dissolve`（噪声烧蚀 + 亮边）、`glitch`（条带位移 + RGB 分离 + 扫描线）、`zoomBlur`（同向推拉 + 径向模糊 + 色散）、`kaleido`（六扇万花筒旋开）、`shockwave`（折射波纹 + 亮环）、`lightLeak`（暖光前沿扫过、身后露出 B）、`warpMorph`（噪声扭变中点最强）。`u` 是 0..1 的原始进度（自己 ease），u≤0/u≥1 时场景里自己直画 A/B（测试卡的 `cut()` 就是这么写的）。`u_seed` 可换形态。写自己的 GLSL：`lib.shader(frag)` 原语还在，头里已有 `u_res/u_time/u_frame/u_tex0/u_tex1`。

**后期**【实测】：

```js
lib.glow(ctx, src, { radius: 26, strength: 0.7, threshold: 0.55 });  // 只加光不压暗（screen）；threshold 抬膝部
lib.duotone(ctx, src, { dark: "#101d42", light: "#ffd9a0" });        // 亮度→双色（SVG 滤镜，无逐像素 JS）
lib.lightLeak(ctx, t, { color: "#ff8a3c", seed: 3, amount: 0.45 });  // 漂移+闪烁的漏光
lib.shimmer(ctx, t, srcLayer, { period: 4, color: "#ffffff" });      // 斜向扫光，只点亮 src 有像素的地方，按 period 循环
```

**逐字编排**【实测】——`ctx.fillStyle` 先设好，`layoutText` 出 `lay`：

```js
lib.drawKinetic(ctx, lay, t, { mode: "rise", stagger: 0.05, dur: 0.55 });
// wave 是无限循环的正弦行波；jitter 按 rate 步进"沸腾"不"抖动"；cascade 带旋转翻入
// 自己的组合：drawGlyphs(ctx, lay, (g, i) => glyphAnim(i, n, t, { mode: "pop" }))
```

**粒子**【实测】：

```js
lib.particles(ctx, t, { mode: "rise", n: 60, seed: 3, area: lib.SAFE.action, size: [1, 3], life: 2, color: "#ff9d4d", twinkle: 0.5 });
// drift 尘埃（区域内回绕，无缝循环）/ rise 余烬（加速上飘，头尾淡入淡出）
// fall 彩纸（旋转+摆动，颜色缺省取 harmony）/ orbit 星尘环 / stream 数据流（沿 dir，两端淡）
// area 收 box() 或 {x,y,w,h} 都行；粒子只画在 area 里
```

**文字标记**【实测】——框从布局造：`lib.box(lay.x0, lay.y - lay.ascent, lay.x1, lay.y + lay.descent)`：

```js
lib.marker(ctx, box, t, { mode: "highlight", color: "#ffd400", draw: 0.3, hold: 0.5 });  // 画在字前面垫底
lib.marker(ctx, box, t, { mode: "circle", color: "#e4572e", draw: 0.5 });                // 手绘圈，8 步/秒沸腾
// underline 画线 / strike 划掉 / brackets 四角括号
```

**配色**【实测】：

```js
lib.harmony("#E4572E", { scheme: "analogous", count: 5, seed: 2 });   // 一色生一家族，带种子抖动
lib.ramp([[0, "#0a0e2a"], [0.45, "#5b2a86"], [1, "#ff9a3c"]], u);     // 梯度取色→hex
```

## 和注册表、原生能力的关系

这层的工具是**画布级**的：场景是 canvas 片子（页面合约 `window.film`）时，它们就是全部画面语汇。HyperFrames 原生的注册表（DOM/GSAP 层的块）是另一路：

- `tools/hf_creative.sh --blocks "<描述>"`：本地词匹配搜 447 个块【实测：`shader transition` 命中 121 条】；on-device 语义排序要一次 33 MB 下载，问过人再加 `--on-device --yes`；
- `--add <block> <项目>`：把块装进项目（`bin/vh hf-init` 搭的工程）；
- 原生着色器转场（页面级 A/B 合成）靠 `--page-side-compositing`（约 6×，SDR mp4 默认开；见 `remotion-speed.md`），和本页的 canvas 级 `shaderTransition` 互不冲突：DOM 场景用前者，canvas 片子用后者；
- 什么时候用哪个：片子走 canvas（大多数风格样片、`bin/vh textcheck` 管得到的字）→ lib.js；片子是 DOM/GSAP 合成（脚手架默认）→ 注册表块 + GSAP。

## 写法约束（不新增，都是既有的规矩）

- **全片一套特效语汇**（`playbook/08` 原则 2）：2–3 种转场、1 种主背景手法反复用；创意包给了更多选择，不是让每个镜头换一种。
- **特效做成预设栈**（`playbook/08`）：系数不写死，`fx` 变量选档，`tools/hf_speed.sh --tier draft` 迭代、定稿换 final 重渲。
- **全屏闪白每秒不超 3 次**（底线）：`zoomDip` 就是为此存在——卡点切走闪白。GLSL 的 `lightLeak`/`shockwave` 有亮环，峰值帧要逐帧看。
- **粒子和循环**：`drift` 在 area 内回绕、`rise/fall/orbit/stream` 按 `life` 周期循环，都是设计好的无接缝循环；自己改周期时保证整除片长（TASTE_CHECKLIST 的循环接缝）。
- **字优先**：bloom/漏光叠在同一帧会过曝（`playbook/08` 的教训）；要读的字亮度压在光效阈值下，URL 出现前光条先收。
- **确定性**：不用 `Math.random()/Date.now()`，粒子/噪声全走 lib 的种子 hash——硬规则 1 的老规矩，创意包没开任何口子。

## 验证与排障

| 想知道 | 跑什么 | 看到 |
|---|---|---|
| 创意包整体没坏 | `tools/hf_creative.sh --demo`（= `render.sh catalog-fx --draft`） | ✓ 150 帧、无错误卡、sheet.png 24 格全有内容【实测】 |
| 逐字节契约 | `styles/_swatch/determinism.sh catalog-fx` | `pixel-identical: 150 · differing: 0`【实测】 |
| 某个 GLSL 转场长什么样 | `render.sh catalog-fx --stage-only` 打印的 snapshot 命令，`--at 2.8/3.5/4.2` | shockwave / lightLeak / warpMorph 全屏帧【实测】 |
| 既有工具没被改坏 | `render.sh catalog --draft` 和 `render.sh demo --draft` | 两张旧卡照常【实测】 |
| 配色在真实代码里出什么 | `tools/hf_creative.sh --palette <hex> --scheme triad` | hex 列表 + 每色的亮度值（就是 lib.js 的函数在跑）【实测】 |
| 场景抛错长什么样 | 洋红 SWATCH ERROR 卡（boot.js 画）+ render.sh 抽帧判失败 | 本页开发中两次被它抓住：`lib.box` 未导出、粒子 area 形状不符【实测】 |

## 反模式

- **全尺寸 GLSL 全屏转场还嫌慢**：SwiftShader 每像素都过片段着色器，1080p 全屏一个转场是 200 万像素×7 采样（zoomBlur）；半尺寸 FX 画布 + drawImage 放大在样片尺度上分辨不出，快约 4 倍【实测口径】。
- **u≤0 / u≥1 还去 render**：转场函数在端点附近有设计好的行为，但直画 A/B 更干净也更快（测试卡的 `cut()` 模式）。
- **粒子不设 area 或 area 形状不对**：area 收 `box()` 或 `{x,y,w,h}`（会归一化），但传个只有 `x/y/w/h` 之外形状的对象，坐标是 NaN，一个粒子都不画——错误不报错，靠测试卡/抽帧看出来【实测教训】。
- **highlight 画在字后面**：`highlight` 是垫底的标记，先画标记再画字；画反了字被黄条盖住。
- **给 canvas 片子装注册表块**：块是 DOM/GSAP 的语汇，canvas 场景装了也用不上；反过来 DOM 场景也别硬 import lib.js 画 canvas。
- **把创意当默认**：原则 1（每个特效说出"因为 X 所以 Y"）没变——工具箱变大了，"说不出来就是装饰"的规矩没变。
