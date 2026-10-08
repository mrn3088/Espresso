# Espresso

[English](#english) | [中文](#中文)

---

## 中文

**让 Mac 通宵跑 coding agent:不断网、不休眠、不打扰。**

本地跑 coding agent(Claude Code、Kimi Code 等)时,Mac 一休眠,网络断开、API 请求中断、任务白跑。Espresso 是 macOS 的「防休眠」一键开关:本质是 `pmset -a disablesleep 0/1` 的图形化 + 命令行封装,**设置一次,永不再输密码**。

UI 参考 Warp (1.1.1.1):菜单栏一个咖啡杯,点开一个大圆钮——橙色发光 = 防休眠中(合盖也不睡),灰色 = 正常睡眠。同一个开关,菜单栏 app 和 `espresso` 命令随便用哪个,状态实时同步。

### 安装

要求:**macOS 15 (Sequoia) 及以上**(Apple Silicon / Intel),装有 Xcode Command Line Tools(没有则 `xcode-select --install`)。**不支持 macOS 14 及更早版本**:系统自带的 `lockf` 太旧,开关命令会直接报错。

```bash
git clone https://github.com/mrn3088/Espresso.git
cd Espresso
./install.sh
```

一次安装,两个形态都就位:

- **UI 版**:`~/Applications/Espresso.app`,自动启动,驻留菜单栏
- **CLI 版**:`/usr/local/bin/espresso`

安装过程弹一次系统密码框(唯一一次),完成两件事:

1. 往 `/etc/sudoers.d/pmset-espresso` 写入最小权限免密规则——**只放行这两条精确命令**,其他 sudo 照常要密码:
   ```
   <你的用户名> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
   ```
2. 把 `espresso` CLI 装到 `/usr/local/bin`

### 使用

菜单栏:点咖啡杯 → 点大圆钮;下方「时长」可选 直到手动关闭 / 1 / 2 / 4 / 8 / 12 小时。命令行:

```bash
espresso on       # 开启防休眠(合盖也不睡),直到手动关闭
espresso for 2h   # 定时防休眠,到点自动恢复睡眠(支持 90m、2h、1h30m,最长 7 天)
espresso off      # 恢复正常睡眠(同时取消定时)
espresso toggle   # 切换
espresso status   # 查看状态、剩余时间、供电;开启时退出码 0,关闭时 1,方便脚本判断
```

**定时会话**:`for` 会立即开启防休眠,并装一个用户级 LaunchAgent(`~/Library/LaunchAgents/com.mrn3088.espresso.timer.plist`),每 30 秒检查一次,到点执行 `pmset -a disablesleep 0` 后自动删除自己。它不依赖菜单栏 app 或终端——关掉 app、关掉终端、甚至重启登录后都照样到点关闭。`on` / `off` 会取消正在进行的定时;再次 `for` 会用新时长覆盖。首次使用时 macOS 可能弹「已添加后台项目」通知,属正常现象。

**电池提醒**:防休眠开启且 Mac 正在用电池(或 UPS)供电时,菜单栏图标会变成警告三角,面板里显示提醒;`espresso status` 会给出警告,用电池时执行 `espresso on` / `for` 也会在 stderr 提醒(不影响退出码)。Espresso **不会**因为拔掉电源而自动关闭防休眠(不打断正在跑的 agent),只是提醒你可能会耗尽电量。

`status` 的退出码让脚本可以这么写:

```bash
espresso status || espresso on   # 确保防休眠开着
```

**界面语言**:app 默认英文,点弹层右上角的 EN/中文 可切换,选择会被记住;CLI 输出跟随同一设置。

### 卸载

```bash
./uninstall.sh
```

停 app、删 `~/Applications/Espresso.app`、删 CLI、删 sudoers 规则、取消定时会话(删除其 LaunchAgent);若卸载时正处于防休眠状态,会先帮你恢复正常睡眠。

### 为什么不用 Amphetamine / caffeinate?

App Store 沙盒 app 调不了 `pmset`;`caffeinate` 类方案只防**闲置**休眠,合盖照样睡、网络照样断。Espresso 用的是系统级 `disablesleep`,合盖也保持唤醒、网络不断,代价是修改该设置必须 root —— 所以用一条最小权限的 sudoers 免密规则解决,一次授权永久免密。

### 常用命令

```bash
pmset -g | grep -i sleepdisabled   # 查看原始状态
./build.sh                          # 改完 app 代码重新编译安装
```

### 项目结构

| 文件 | 说明 |
| --- | --- |
| `EspressoApp.swift` | 菜单栏 app 全部代码(SwiftUI `MenuBarExtra`) |
| `espresso` | CLI(bash,与 app 共用同一条免密规则;app 内也内置一份,开关 / 定时都经由它) |
| `tests/test_espresso.sh` | CLI 轻量测试(时长解析等),`./tests/test_espresso.sh` |
| `build.sh` | 编译 + 打包 + ad-hoc 签名到 `~/Applications/Espresso.app` |
| `install.sh` / `uninstall.sh` | 一键安装 / 卸载(app + CLI + sudoers 规则) |
| `make_icon.swift` | 图标生成器,改动后重新生成 `AppIcon.icns` |
| `Info.plist` | app bundle 配置(`LSUIElement`,无 Dock 图标) |

> 提醒:防休眠开启时合盖也不会睡,放包里前记得 `espresso off`,以免耗电发热。不确定何时结束时,用 `espresso for 8h` 这类定时会话更安全。

---

## English

**Let your Mac run coding agents all night: no sleep, no dropped network, no interruptions.**

When the Mac sleeps, the network drops and your local coding agents (Claude Code, Kimi Code, etc.) die mid-task. Espresso is a one-click "no-sleep" switch for macOS: a GUI + CLI wrapper around `pmset -a disablesleep 0/1` — **authorize once, never type a password again**.

The UI is inspired by Warp (1.1.1.1): a coffee cup in the menu bar opens a panel with one big round button — glowing orange = no-sleep on (lid-close won't sleep either), gray = normal sleep. The menu bar app and the `espresso` command drive the same switch and stay in sync.

### Install

Requires **macOS 15 (Sequoia) or later** (Apple Silicon or Intel) and Xcode Command Line Tools (`xcode-select --install` if missing). **macOS 14 and earlier are not supported**: their built-in `lockf` is too old, so the on/off commands fail.

```bash
git clone https://github.com/mrn3088/Espresso.git
cd Espresso
./install.sh
```

One install, two front-ends:

- **UI**: `~/Applications/Espresso.app`, launched automatically, lives in the menu bar
- **CLI**: `/usr/local/bin/espresso`

A system password prompt appears **once and only once**, doing two things:

1. Writing a least-privilege sudoers rule to `/etc/sudoers.d/pmset-espresso` — **only these two exact commands** are whitelisted; every other `sudo` command still requires a password:
   ```
   <your-username> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
   ```
2. Installing the `espresso` CLI to `/usr/local/bin`

### Usage

Menu bar: click the coffee cup, then the big round button. The **Duration** menu below it offers Until turned off / 1 / 2 / 4 / 8 / 12 hours. Command line:

```bash
espresso on       # no-sleep on (lid-close won't sleep) until turned off
espresso for 2h   # no-sleep for a while, then sleep is restored automatically
                  # (accepts 90m, 2h, 1h30m; max 7 days)
espresso off      # back to normal sleep (cancels any timer)
espresso toggle   # flip the switch
espresso status   # state, time left, power source; exit code 0 = on, 1 = off
```

**Timed sessions**: `for` turns no-sleep on immediately and installs a per-user LaunchAgent (`~/Library/LaunchAgents/com.mrn3088.espresso.timer.plist`) that checks every 30 seconds; when time is up it runs `pmset -a disablesleep 0` and removes itself. It does not depend on the menu bar app or the terminal — quitting the app, closing the terminal, or even rebooting and logging back in won't stop the auto-off. `on` and `off` cancel a running timer; another `for` replaces it with the new duration. macOS may show a "Background Items Added" notification the first time; that is expected.

**Battery warning**: when no-sleep is on and the Mac is running on battery (or UPS) power, the menu bar icon turns into a warning triangle and the panel shows a warning; `espresso status` prints one, and `espresso on` / `for` print one to stderr when started on battery (the exit code is unaffected). Espresso does **not** turn itself off when you unplug (it won't interrupt a running agent) — it just tells you the battery may drain.

The `status` exit code enables patterns like:

```bash
espresso status || espresso on   # make sure no-sleep is on
```

**Language**: the app defaults to English; switch to Chinese with the EN/中文 control at the top right of the panel (persisted). CLI output follows the same setting.

### Uninstall

```bash
./uninstall.sh
```

Stops the app, removes `~/Applications/Espresso.app`, the CLI, the sudoers rule, and any pending timer (its LaunchAgent). If no-sleep is active at uninstall time, normal sleep is restored first.

### Why not Amphetamine / caffeinate?

Sandboxed App Store apps cannot run `pmset`, and `caffeinate`-style tools only prevent **idle** sleep — closing the lid still sleeps and the network still drops. Espresso uses the system-level `disablesleep` setting: the Mac stays awake (and online) with the lid closed. That setting requires root to modify, hence the single least-privilege sudoers rule — one authorization, passwordless forever.

### Handy commands

```bash
pmset -g | grep -i sleepdisabled   # raw state
./build.sh                          # rebuild & reinstall after editing the app code
```

### Project layout

| File | Purpose |
| --- | --- |
| `EspressoApp.swift` | The entire menu bar app (SwiftUI `MenuBarExtra`) |
| `espresso` | The CLI (bash, shares the same sudoers rule as the app; a copy is bundled in the app, which drives on/off/timers through it) |
| `tests/test_espresso.sh` | Lightweight CLI tests (duration parsing etc.): `./tests/test_espresso.sh` |
| `build.sh` | Compile + bundle + ad-hoc sign into `~/Applications/Espresso.app` |
| `install.sh` / `uninstall.sh` | One-step install / uninstall (app + CLI + sudoers rule) |
| `make_icon.swift` | Icon generator; rerun to regenerate `AppIcon.icns` |
| `Info.plist` | App bundle config (`LSUIElement`, no Dock icon) |

> Heads-up: with no-sleep on, the Mac stays awake even with the lid closed — run `espresso off` before tossing it in a bag, or it will burn battery and heat up. For unattended runs, a timed session like `espresso for 8h` is the safer choice.
