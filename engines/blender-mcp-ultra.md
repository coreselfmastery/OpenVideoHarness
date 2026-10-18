# blender-mcp-ultra：Blender 引擎的 MCP（探索阶段专用）

> **实测 Linux headless（2026-10-18）**：在 Linux 沙箱里跑了完整链路——官方 Blender 5.2.2 LTS Linux x64 tarball（headless `blender -b`）+ PyPI `blender-mcp-ultra` 3.2.0 网关 + 仓库 main（`7a1538c`，2026-08-29）的 addon。下文标【实测 Linux】的都是在它上面验证过的：248 个工具注册、token 认证拒绝错误/缺失 token、`execute_blender_code` 的 AST 拦截、真实建场景、Cycles CPU 出 PNG、glTF 导出、快照/锁/计划工具。**仓库规则不变：MCP 只在探索阶段用，不进管线；会话不是产物，固化成 `build.py`（见 `blender.md` 的"安全"一节）。**

标记：【实测 Linux】= 上面的沙箱 E2E（Blender 5.2.2 headless + 网关 3.2.0）；【实测】= 维护者的 Mac（沿用 `blender.md` 的口径）；【二手】= 只读到文档/源码，没跑过；【推测】= 无证据推断。引用编号 `[n]` 见文末。

## 要点

| | |
|---|---|
| 是什么 | [carlosh7/blender-mcp](https://github.com/carlosh7/blender-mcp)（PyPI 包名 `blender-mcp-ultra`），MIT，248 个带类型签名的 MCP 工具，控制真 Blender。不是 ahujasid 版的 fork：作者自己的审计说得很清楚，是在 upstream 概念上的独立重写（325 个提交全是作者本人的）[1][2] |
| 版本（实测 Linux） | 网关 **3.2.0**（PyPI wheel）；addon 用仓库 main `7a1538c`；GitHub release 里的 addon zip 停在 **3.1.0**（要 3.2.0 的 addon 就用仓库检出，见安装） |
| 工具数 | **248**（7 个基础 + 241 个 registry），网关**不开 Blender 也能全部注册**——元数据在本地构建，Blender 后开也来得及【实测 Linux】 |
| 版本要求 | Blender 4.2+ 或 5.x（实测 5.2.2 LTS）；网关 Python ≥ 3.10（实测 3.12 venv）；Blender 5.2 自带 Python 3.13 + numpy |
| 安全 | localhost-only socket + **强制 token**（错误/缺失 token 实测被拒）+ **AST 拦截双侧**（网关和 addon 各拦一次；`import os`、`open()`、`import subprocess` 实测全被拦）+ REST 限速 30 req/min、1 MB body + 10 s 超时 + 自动 undo [1][3] |
| 定位 | **只在探索阶段用**：看场景、试构图、试灯光、出小样，然后把确认有用的操作固化成 `timeline.json` + `build.py`。管线（build → render → PNG 序列）照旧走 `blender -b` 脚本 |
| 许可证 | MIT（gateway 和 addon 都是）[1]。注意：**调用 bpy 的脚本要发布仍按 GPL**（`blender.md` 的"许可证"一节），MIT 的只是工具本身 |

## 架构

```
agent（Claude Code / Cursor / opencode / 任意 MCP 客户端）
   │  MCP stdio（默认）或 SSE :9879
   ▼
blender-mcp-server（网关，FastMCP）
   │  · 248 个工具的元数据在本地注册（不需要 Blender 开着）
   │  · code_guard 在这一层先拦一次
   │  · --lite / BLENDER_MCP_LITE=1：只注册 24 个核心 + tools_search +
   │    tool_execute（上下文成本 ~30k → ~4k tokens，能力不减）
   ▼  TCP 127.0.0.1:9876，强制 token
addon/_axsock.py（跑在 Blender 里）
   │  · token 校验（constant-time 比较）
   │  · GUI 模式：所有 bpy 调用经 bpy.app.timers 串行回主线程
   │  · headless 模式：serve_forever() 阻塞式，handler 直接在主线程
   ▼
mcp_ultra/ ToolRegistry（241 个工具，16 类）→ bpy → 场景
```

启动顺序无所谓：工具全部在网关本地注册，Blender 没开时调用会得到明确的连接错误，Blender 一开就好（按调用重连）[3]【实测 Linux】。

## 安装

### 1. 网关（任何机器）

```bash
pip install blender-mcp-ultra        # 或 uv tool install blender-mcp-ultra
```

装出两个命令：`blender-mcp-server`（MCP 网关）和 `blender-mcp`（CLI：doctor / start / stop / restart / sse）。`blender-mcp --doctor` 做健康检查——Python、PATH 上的 Blender、MCP SDK、socket 连通性（实测能探测到 headless 服务器）、磁盘【实测 Linux】。

### 2. addon（两种来路）

- **GUI（维护者的 Mac）**：从 [releases](https://github.com/carlosh7/blender-mcp/releases) 下载 `blender_mcp_ultra.zip` → Blender `Edit > Preferences > Add-ons > Install…` → 启用 **blender-mcp-ultra** → 3D 视图 `N` 面板点 **Connect**。注意 release zip 今天是 3.1.0，比 PyPI 落后一个 minor【二手】。
- **仓库检出（版本最新，headless 必须这条路）**：

```bash
git clone --depth 1 https://github.com/carlosh7/blender-mcp.git
# GUI 安装：cd blender-mcp && pip install -e .   # Blender 4.2+/5.x 扩展
```

### 3. 客户端注册（Claude Code）

```bash
claude mcp add blender -- blender-mcp-server
# 仓库检出的来路：
claude mcp add blender -- python /path/to/blender-mcp/mcp_server.py
```

`mcp.json`（Claude Desktop / Cursor / Windsurf / VS Code）：

```json
{ "mcpServers": { "blender": { "command": "blender-mcp-server" } } }
```

## headless 配方（实测 Linux）

官方自己的 CI 就是这么跑的（`docs/skills/headless_ci.md`）：无 GUI 时 `bpy.app.timers` 不触发，线程模式失效，用**阻塞式服务器**，handler 直接在主线程跑（bpy 天然安全）：

```python
# blender_headless_server.py
import sys
sys.path.insert(0, "/path/to/blender-mcp/addon")
import _axsock
_axsock.serve_forever(host="127.0.0.1", port=9876)   # 不返回
```

```bash
blender -b --factory-startup --python blender_headless_server.py
```

- **headless 下不可用**：`get_viewport_screenshot`、`vlm_capture`（没有 viewport）——都**优雅失败**，返回明确错误，不会挂死服务器【实测 Linux】。要看画面就 `render_render` 出 PNG 再看。
- **headless 下可用（全部实测 Linux）**：建/改场景、材质、灯光、相机、物理、`render_render`（Cycles CPU）、`io_export_gltf`（72 KB 合法 glb）、快照/锁/计划、`tools_search`、`guidance_*`、`docs_scene`。
- 多实例：`BLENDER_MCP_SOCKET_PORT`（addon 侧）与 `BLENDER_PORT`（网关侧）配对改端口；`BLENDER_HOST` 指到远端 Blender（走 SSH 隧道，别裸开）[4]。

## 安全模型（含实测）

**token 认证（强制）**：解析顺序 `BLENDER_MCP_TOKEN` 环境变量 > 场景属性 > 自动生成 `secrets.token_hex(16)` 落盘 `~/.config/blender-mcp/socket_token`（macOS 在 `~/Library/Application Support/blender-mcp/`，权限 0600），addon 和网关读同一个文件，零配置。socket 用 `secrets.compare_digest` 比较。**实测 Linux**：错误 token 和缺失 token 都返回 `unauthorized: invalid or missing token`。

**AST 拦截（code_guard，双侧）**：网关和 addon 各有一份相同的黑名单——禁 import `os`/`sys`/`subprocess`/`socket`/`shutil`/`pathlib`/`importlib`/`ctypes`/`pickle` 等 25 个模块，禁 `open`/`eval`/`exec`/`compile`/`__import__` 等调用，允许的根只有 `bpy` 等。**实测 Linux**：`import os; os.system('id')`、`open('/tmp/pwned.txt','w')`、`import subprocess` 全被网关拦下（"⛔ Bloqueado por seguridad"），合法 bpy 代码照常跑。也就是说 **MCP 的 `execute_code` 通道做不了文件 I/O、起不了进程、开不了网络**——比另外两个 MCP 的裸 `exec()` 强一个量级。

**REST（:9877，可选）**：token 同 socket、1 MB body 上限、30 req/min 限速、AST 拦截、只绑 127.0.0.1。SSE（:9879）同理走 token。v3.2.0 还去掉了 `SO_REUSEPORT`（Linux 上防端口抢占）[3]。

**他们自己的审计史（值得知道）**：2026-08 的 `AUDIT_REPORT.md` 是作者自己写的红队记录——mini_http 曾有无认证的 LAN RCE（`0.0.0.0` + 裸 `exec()`），被自己发现、复现、修复并回归验证；`mcp` 2.0 破坏 FastMCP 的坑也修了（钉死 `<2`）；gitleaks 全历史扫描，活动树 0 泄漏 [2]。这个"自己给自己做审计并公开"的记录，是选它而不是另外两个的核心理由之一。

**它不覆盖的（仓库规则因此不变）**：

- registry 工具**按设计就要写文件**（`render_render` 的 filepath、`io_export_*`、`blueprint_save`），路径参数没做白名单——乱指路径会覆盖文件。探索阶段在项目目录里跑，别指着别处。
- 间接提示注入照样是威胁：`.blend` 里的对象名、文本块、素材元数据都可能带指令。第三方 `.blend` 先 `--disable-autoexec`（命令行默认 `-Y`）打开扫一遍再用（`blender.md` 的老规则）。
- AST 拦截不是沙箱：bpy 本身能改用户设置、删场景。**默认关、用前问用户、放在虚拟机或单独的 macOS 用户下**——这三条照旧（`blender.md`"安全"一节）。`sandbox-exec` + `env -i` 的那套是给管线脚本的，MCP 会话没法套，所以更要隔离环境。
- 下载素材（PolyHaven CC0、AmbientCG CC0、Sketchfab 逐件许可）照旧进素材台账。

## 248 个工具：与本仓库相关的部分

全量清单让 agent 自己 `tools/list`（或 `tools_search`）拿，这里只列探索阶段用得上的。计数为实测 Linux 的 live 注册数：

| 类 | 数 | 探索阶段的用法 |
|---|---|---|
| scene | 16 | `scene.get_info`（AGENTS.md 第一铁律：动手前先看）、`scene.mood`（灯光语言快调）、`scene.diff`（配合 `scene.mark` 看改了什么）、`scene.check_blockout` |
| object / mesh | 10 / 11 | 建块、`mesh.bevel_edges`（反 blockout 铁律：不许裸图元） |
| material | 7 | `material.pbr`（wood/metal/glass/…程序化 PBR，实测 wood 生效） |
| light / camera | 5 / 9 | `light.three_point`（实测）、`camera.set_framing`（实测） |
| render | 9 | `render.set_engine` + `scene.render_settings` + `render.render`（实测 Cycles CPU 出 320×180 PNG）；探索完把参数抄进 `blender.lock` |
| io / export | 10 / 4 | `io_export_gltf`（实测，给 HyperFrames/Three.js 引用素材） |
| physics | 12 | 刚体/布料/粒子试动力学，**烘焙结果当素材**进 `caches/`（`blender.md` 的老规则） |
| vc（版本） | 3 | `vc_snapshot` / `vc_restore`：探索过程的检查点（实测） |
| collab | 12 | 多 agent 时的对象锁/任务/消息（`collab_lock_acquire` 实测） |
| plan | 4 | `plan_create` / `plan_execute`：镜头步骤清单 |
| vlm | 5 | `vlm_capture` / `vlm_composition_check` / `vlm_lighting_check`：**GUI 专用**（headless 不可用），agent 看自己的渲染结果自查 |
| guidance | 2 | `guidance.list` / `guidance.get`：22 篇内置工作流指南（场景、灯光、动画……实测），替代旧版的可安装 skills |
| docs / spatial / inspect | 3 / 6 / 3 | `docs_scene` 导出场景文档（实测）、空间查询、拓扑体检 |
| 基础 | 7 | `get_scene_info`、`execute_blender_code`（过 code_guard）、`search_api_docs`（先查 API 再写代码）、`snap_and_parent`（27 锚点拼装）、`tool_execute`、`get_viewport_screenshot`、`get_python_api_docs` |

工具名的两种写法等价：MCP 名 `material_pbr` = registry 名 `material.pbr`（`tool_execute` 两个都收）。

## 探索阶段工作流（对齐 `blender.md` 的流程表）

1. **先看再动**（阶段 2–3，blockout animatic 前后）：`scene.get_info` + `docs_scene` 读现状；`plan_create` 列这个镜头要试的几件事。
2. **试**：建块 → `mesh.bevel_edges` + `material.pbr` + 平滑着色（反 blockout：没有这三样的就是占位块，`scene.check_blockout` 会点名）→ `light.three_point` / `scene.mood` → `camera.set_framing`。
3. **看**：GUI 会话用 `vlm_capture` + `vlm_composition_check`；headless 用 `render_render` 出小 PNG 自己看。构图过关 = 关卡 ② 的节奏和构图检查有据可依。
4. **存档**：`vc_snapshot` 打检查点，`scene_mark` + `scene_diff` 记录净变更；确认有用的参数（视图变换、灯光能量、相机 fov、采样数）**抄进 BRIEF 和 `timeline.json`**。
5. **固化**：探索会话到此为止。把结果写成 `timeline.json` + `lib/build.py`，管线（build → render → PNG → 合成）从这走——MCP 会话不可复现，不能当产物，这是硬规则。

## 与另外两个 MCP 的对比

| | blender-mcp-ultra（本页） | 官方 MCP（Blender Lab）[5] | ahujasid/mcp-for-blender [5] |
|---|---|---|---|
| 工具数 | 248，带类型签名（pydantic 校验，实测报错给出准确字段名） | 少量（执行代码为主） | 十几个 |
| 代码执行 | AST 双侧拦截，实测禁 os/open/subprocess | 裸执行，官方自警无防护 | 裸 `exec()`；新版有 `BLENDER_MCP_SAFE_MODE=1` |
| 传输 | stdio / SSE / REST，全走强制 token | stdio | 无认证本地 TCP（有 CVE-2026-10661） |
| Blender 版本 | 4.2+ / 5.x（实测 5.2.2） | 5.1+ | 3.0+ |
| headless | 官方 CI 就这么跑（本页配方实测） | — | — |
| 许可证 | MIT | GPL-3.0 | MIT |

结论：**探索阶段要用 MCP，就用 blender-mcp-ultra**；另外两个只在需要对照时读文档。三个都绕不开"LLM 代码在 Blender 里执行"这个本质，所以隔离环境的老规矩不因为工具变好而废除。

## Kaggle / CI 说明

- Kaggle 上跑 Blender 本身要先装（官方 Linux tarball 解压即用，无需 root）；`blender -b` + headless 配方就是它的 CI 形态。2×T4 对 Cycles 有用（`OPTIX`/`CUDA`），但 **MCP 探索阶段的目的不是渲染速度**，CPU 小样就够；真渲染走管线脚本的分块渲染。
- 网关在 Kaggle（Linux）上 `pip install blender-mcp-ultra` 即装；token 自动生成在 `~/.config/blender-mcp/socket_token`。不要在 Kaggle 上开 SSE/REST 对公网（`MCP_SSE_HOST`）——token 不是为公网设计的。
- 这条链路（headless 服务器 + 网关 + 248 工具 + Cycles CPU 小样）整体在 Linux 上实测过（见页首），Kaggle 只是同一配方换机器【实测 Linux + 推测（Kaggle 部分未跑）】。

## 来源

- [1] 仓库与 README：https://github.com/carlosh7/blender-mcp （2026-10-18 核对：248 工具、架构、安全声明、Blender 4.2+/5.x、MIT）；PyPI：https://pypi.org/pypi/blender-mcp-ultra/json （3.2.0，>=3.10，MIT）
- [2] 自审计：仓库内 `AUDIT_REPORT.md`（2026-08-21/24：LAN RCE 发现→复现→修复→回归；score 54→78；gitleaks/bandit/pip-audit 结论）
- [3] v3.2.0 变更：仓库内 `CHANGELOG.md`（token 强制落盘 0600、code_guard 接入 cmd_execute_code、去 SO_REUSEPORT、网关本地注册全量 registry、--lite 模式）
- [4] 远程/Docker：仓库内 `docs/remote.md`（`BLENDER_HOST`/`BLENDER_PORT`、SSE :9879、Docker）
- [5] 官方 MCP 与 ahujasid 的事实与来源：见 `blender.md` 引用 [16]（2026-10-01 核对）
- 【实测 Linux】原始证据：`e2e_render.png`（Cycles CPU 320×180）、`e2e_scene.glb`（72 KB）、MCP 握手与 248 工具清单、token 拒绝与 AST 拦截的响应原文，测试脚本 `mcp_probe.py` / `blender_headless_server.py` / `e2e_battery*.py`（会话内留存）
