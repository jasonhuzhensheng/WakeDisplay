# WakeDisplay

<p align="center">
  <a href="https://github.com/jasonhuzhensheng/WakeDisplay/releases/latest"><img src="https://img.shields.io/github/v/release/jasonhuzhensheng/WakeDisplay?label=release" alt="Latest release"></a>
  <a href="https://github.com/jasonhuzhensheng/WakeDisplay/releases"><img src="https://img.shields.io/github/downloads/jasonhuzhensheng/WakeDisplay/total?label=downloads" alt="Total downloads"></a>
  <a href="https://github.com/jasonhuzhensheng/WakeDisplay/stargazers"><img src="https://img.shields.io/github/stars/jasonhuzhensheng/WakeDisplay?style=flat" alt="Stars"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B-black?logo=apple" alt="macOS 12+">
</p>

<p align="center">
  <b>macOS 菜单栏小工具：一键唤醒"系统看得见、屏幕却不亮"的 USB-C 外接显示器，并解锁系统隐藏的 HiDPI 缩放模式。</b><br>
  <b>A tiny macOS menu-bar utility that wakes USB-C external displays macOS can see but won't light up, and unlocks hidden HiDPI scaling modes.</b>
</p>

<p align="center">
  <a href="#中文说明">中文</a> · <a href="#english">English</a>
</p>

---

## 中文说明

### 解决什么问题

使用 USB-C 一线通便携显示器（尤其是 4K / 高刷屏）时，常见两个顽疾：

| 问题 | 根因 | WakeDisplay 的做法 |
|---|---|---|
| Mac 休眠 / 锁屏后外屏黑掉，系统里仍能看到它，但必须**物理拔插线**才亮 | macOS 电源管理在屏幕变暗时挂起雷电 / USB-C 控制器；显示器面板进入 DDC 省电态后握手未完成 | 菜单 →「唤醒显示器」（或 ⌘⇧R）：声明用户活动 → 发 DDC 开机指令 → 重新探测显示器；不行再用「强制重置」（镜像开/关强制重连） |
| 系统设置里**没有「更大文本 / 更小文本」**缩放选项 | macOS 对不认识的外接屏隐藏了 HiDPI 模式 | 列出全部隐藏模式，一键切换；⌘⇧+ / ⌘⇧− 逐级调字体大小 |

### 功能一览

- 点击菜单栏图标（左键或右键）打开菜单
- 🔆 **唤醒显示器 / ⌘⇧R** — 不闪屏（用户活动声明 + DDC/CI 电源指令 + IOKit 重新探测）
- 🔁 **强制重置** — 先让所有屏休眠再唤醒，再镜像开/关强制重新建立链路（屏幕会闪一下）
- 🤖 **自动唤醒** — 每 5 秒检测：内屏醒着、外屏却在休眠 → 自动点亮
- ☕️ **阻止显示器休眠** — 等价于常驻 `caffeinate -d`
- ☀️ **户外模式（⌃⌥⌘B）** — MacBook 内建屏亮度拉满；Liquid Retina XDR 机型再借用 HDR 余量把整个画面提亮约 1.6 倍（全屏约 800 尼特），阳光下也看得清。关闭即恢复原亮度
- 🧩 **桌面 / 通知中心小组件**（macOS 14+）— 小号：点一下唤醒；中号：唤醒、强制重置、户外模式、字体变大 / 变小、菜单六个按钮。右键桌面 →「编辑小组件」→ 搜索 WakeDisplay 添加
- 🌐 **16 种界面语言**，默认跟随系统语言：English、简体中文、繁體中文、日本語、한국어、Español、Français、Deutsch、Português、Italiano、Русский、العربية、हिन्दी、Bahasa Indonesia、Türkçe、Tiếng Việt
- 🔍 **缩放 / 字体大小** — 每块外接屏一个子菜单，列出系统隐藏的 HiDPI 分辨率；「更大文本 / 更小文本」与系统设置滑块等价
- ✨ **原生分辨率清晰缩放** — 系统不给 HiDPI 选项的屏（如 2880×1800 便携屏）：显示器保持原生分辨率输出，界面「看起来像」1920×1200 等更大字号，依然清晰（虚拟 HiDPI 屏 + 镜像，BetterDisplay 同款原理）
- ⚡️ **写入防断连电源策略** — 一键执行 `sudo pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0`（弹系统密码框，可随时恢复默认）
- 🧹 **清除显示器缓存（EDID）** — 删除 `com.apple.windowserver.displays.plist` 并重启
- 🌐 **界面语言**：默认英文，右键菜单 → Language → 中文 即可切换（自动记住）
- 开机自动启动（LaunchAgent），不占 Dock

### 使用环境

| 项目 | 要求 |
|---|---|
| 系统 | macOS 12 Monterey 及以上（在 macOS 14 / 15 上测试） |
| 芯片 | **Apple Silicon**（M1–M4）完整支持。Intel Mac 可编译使用，但 DDC 电源指令一项不可用 |
| 编译 | Xcode Command Line Tools（`xcode-select --install`），无其他依赖 |
| 显示器 | 任意 USB-C / DP 外接屏。DDC 唤醒需显示器 OSD 中 **DDC/CI 开启**；HiDPI 模式通常需要 4K 及以上分辨率 |

### 安装

**方式一：直接下载（推荐）**
到 [Releases](https://github.com/jasonhuzhensheng/WakeDisplay/releases/latest) 下载最新的 `WakeDisplay-vX.Y.zip`，解压后拖到「应用程序」。应用未经 Apple 公证，首次启动前执行：
```bash
xattr -dr com.apple.quarantine /Applications/WakeDisplay.app
```

**方式二：从源码编译**

```bash
git clone https://github.com/jasonhuzhensheng/WakeDisplay.git
cd WakeDisplay
chmod +x build.sh && ./build.sh
open /Applications/WakeDisplay.app
```

`build.sh` 会编译、ad-hoc 签名并安装到 `/Applications`。首次启动后右键菜单栏图标，勾选「开机自动启动」。

> 如果提示 `zsh: permission denied: ./build.sh`，先执行 `chmod +x build.sh`。

### 推荐配置（一次配好，长期省心）

1. **双线供电**：显示器 PD 口接独立充电头，信号口接 Mac——Mac 休眠时显示器主板不断电
2. 显示器 OSD：输入源**锁定 Type-C / DP**（不用 Auto），**DDC/CI 开启**
3. 4K 144Hz 请使用标明 **DP 1.4 / 40 Gbps** 的全功能 C-to-C 线
4. 右键 WakeDisplay → 写入防断连电源策略
5. 右键 WakeDisplay → 勾选「自动唤醒」和「开机自动启动」
6. 缩放子菜单里选 **2560×1440 HiDPI**（4K 屏推荐）或 1920×1080 HiDPI
7. 系统设置 → 显示器 → 排列 → 把菜单栏拖到你常看的那块屏

### 快捷键

| 快捷键 | 功能 |
|---|---|
| ⌘⇧R | 唤醒显示器 |
| ⌘⇧+ | 更大文本（下一个更低的 HiDPI 分辨率） |
| ⌘⇧− | 更小文本 |
| ⌃⌥⌘B | 户外模式开 / 关 |
| ⌃⌥⌘M | 在鼠标位置弹出菜单（图标被刘海挡住时用） |

### 常见问题

**点了没反应？** 先确认显示器 OSD 调得出来。调不出来且电源灯亮 → 彻底断电放电（拔掉所有线、按住电源键 15 秒、等 30 秒）；仍不亮 → 用手机 / iPad 直连测试显示器本身是否故障。

**缩放子菜单里没有 HiDPI 项？** 打开子菜单里的「✨ 原生分辨率清晰缩放」，然后在「看起来像」列表里选字号，或用 ⌘⇧+ / ⌘⇧− 逐级调整。设置会记住，下次启动自动恢复。

**写入电源策略后笔记本更耗电？** 是的，`sleep 0` 会阻止深度休眠。不需要时点「恢复系统默认电源策略」即可。

**编译报 `IOAVServiceCreateWithService` 链接错误？** 你是 Intel Mac，这个私有符号只在 Apple Silicon 的 IOKit 中存在。删除 `main.swift` 中 `ddcWrite` 相关代码或改为空实现即可。

### 技术细节

| 手段 | 实现 |
|---|---|
| 用户活动声明 | `IOPMAssertionDeclareUserActivity` |
| DDC/CI 电源指令 | `IOAVServiceWriteI2C` 向 `DCPAVServiceProxy`（Location = External）写 VCP 0xD6 = 1（与 [m1ddc](https://github.com/waydabber/m1ddc) 同一通路） |
| 重新探测 | `IOServiceRequestProbe` 遍历 `IODisplayConnect` / `AppleCLCD2` / `DCPAVControllerProxy` 等 |
| 镜像重连 | `CGConfigureDisplayMirrorOfDisplay` 开 → 1.5 s → 关 |
| 原生分辨率清晰缩放 | 私有 `CGVirtualDisplay`（hiDPI=1）创建虚拟屏，`CGConfigureDisplayMirrorOfDisplay` 把物理屏镜像到虚拟屏 |
| 隐藏 HiDPI 模式 | `CGDisplayCopyAllDisplayModes` + `kCGDisplayShowDuplicateLowResolutionModes`，`CGConfigureDisplayWithDisplayMode` 持久切换 |
| 全局快捷键 | Carbon `RegisterEventHotKey` |

Swift 单文件 + 一个私有 API 头文件（`CGVirtualDisplay.h`），无第三方依赖。

---

## English

### What it fixes

Two chronic annoyances with single-cable USB-C portable monitors (especially 4K / high-refresh panels) on macOS:

| Problem | Root cause | What WakeDisplay does |
|---|---|---|
| After sleep / lock the external display goes dark; macOS still lists it, but only **physically unplugging the cable** brings it back | macOS power management suspends the Thunderbolt / USB-C controller when the screen dims; the panel drops into DDC power-save and the link never re-handshakes | Menu → "Wake Display" (or ⌘⇧R): declare user activity → send a DDC power-on command → re-probe display services; if that fails, "Force Reset" toggles mirroring to force a fresh link |
| System Settings shows **no "Larger Text / Smaller Text"** scaling options | macOS hides HiDPI modes for displays it doesn't recognise | Lists every hidden mode and switches with one click; ⌘⇧+ / ⌘⇧− step through text sizes |

### Features

- Click the menu-bar icon (left or right) to open the menu
- 🔆 **Wake Display / ⌘⇧R** — no flicker (user-activity assertion + DDC/CI power command + IOKit re-probe)
- 🔁 **Force reset** — sleep all displays, wake them, then toggle mirroring to force a fresh link (screens blink once)
- 🤖 **Auto-wake** — every 5 s: if the built-in display is awake but an external one is asleep, wake it
- ☕️ **Prevent display sleep** — a persistent `caffeinate -d`
- ☀️ **Outdoor mode (⌃⌥⌘B)** — built-in MacBook display to 100% brightness; on Liquid Retina XDR models it also uses the HDR headroom to brighten the whole desktop ~1.6× (≈800 nits full-screen) for direct sunlight. Turning it off restores your previous brightness
- 🧩 **Desktop / Notification Center widget** (macOS 14+) — small: tap to wake; medium: six buttons for Wake, Force Reset, Outdoor, Larger / Smaller Text and Menu. Right-click the desktop → Edit Widgets → search "WakeDisplay"
- 🌐 **16 UI languages**, following your system language by default: English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Português, Italiano, Русский, العربية, हिन्दी, Bahasa Indonesia, Türkçe, Tiếng Việt
- 🔍 **Scaling / text size** — one submenu per external display listing hidden HiDPI resolutions; "Larger / Smaller Text" behave like the System Settings slider
- ✨ **Sharp scaling at native resolution** — for panels macOS gives no HiDPI options (e.g. a 2880×1800 portable screen): the panel keeps its native signal while the UI "looks like" 1920×1200 or another larger size, still sharp (HiDPI virtual display + mirroring, the same technique as BetterDisplay)
- ⚡️ **Apply anti-disconnect power policy** — runs `sudo pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0` via the system password prompt (restore defaults any time)
- 🧹 **Reset display cache (EDID)** — deletes `com.apple.windowserver.displays.plist` and reboots
- 🌐 **UI language**: English by default; switch to Chinese via right-click → Language → 中文 (remembered)
- Launch at login (LaunchAgent), no Dock icon

### Requirements

| | |
|---|---|
| OS | macOS 12 Monterey or later (tested on macOS 14 / 15) |
| Chip | **Apple Silicon** (M1–M4) fully supported. Builds and runs on Intel, but the DDC power command is unavailable there |
| Build | Xcode Command Line Tools (`xcode-select --install`); no other dependencies |
| Display | Any USB-C / DP external display. DDC wake requires **DDC/CI enabled** in the monitor's OSD; HiDPI modes generally need 4K or higher |

### Install

**Option 1: download (recommended)**
Grab the latest `WakeDisplay-vX.Y.zip` from [Releases](https://github.com/jasonhuzhensheng/WakeDisplay/releases/latest), unzip, and move it to Applications. The app is not notarized, so before the first launch run:
```bash
xattr -dr com.apple.quarantine /Applications/WakeDisplay.app
```

**Option 2: build from source**

```bash
git clone https://github.com/jasonhuzhensheng/WakeDisplay.git
cd WakeDisplay
chmod +x build.sh && ./build.sh
open /Applications/WakeDisplay.app
```

`build.sh` compiles, ad-hoc signs and installs to `/Applications`. After first launch, right-click the menu-bar icon and tick "Launch at login".

> If you see `zsh: permission denied: ./build.sh`, run `chmod +x build.sh` first.

### Recommended setup

1. **Two cables**: monitor's PD port → its own charger; signal port → Mac. The monitor's board stays powered while the Mac sleeps
2. Monitor OSD: lock input to **Type-C / DP** (not Auto), keep **DDC/CI on**
3. For 4K 144 Hz use a full-featured C-to-C cable rated **DP 1.4 / 40 Gbps**
4. Right-click WakeDisplay → Apply anti-disconnect power policy
5. Right-click WakeDisplay → tick "Auto-wake" and "Launch at login"
6. In the scaling submenu pick **2560×1440 HiDPI** (recommended for 4K) or 1920×1080 HiDPI
7. System Settings → Displays → Arrange → drag the menu bar onto the screen you look at most

### Shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧R | Wake display |
| ⌘⇧+ | Larger text (next lower HiDPI resolution) |
| ⌘⇧− | Smaller text |
| ⌃⌥⌘B | Outdoor mode on / off |
| ⌃⌥⌘M | Open the menu at the mouse pointer (if the icon is hidden behind the notch) |

### FAQ

**Nothing happens when I click?** First check the monitor's own OSD comes up. If it doesn't and the power LED is on → full power drain (unplug everything, hold power 15 s, wait 30 s). Still dark → test the monitor with a phone / iPad to rule out hardware failure.

**No HiDPI entries in the scaling submenu?** Turn on "✨ Sharp Scaling at Native Resolution" in that submenu, then pick a size from the "Looks like" list or step with ⌘⇧+ / ⌘⇧−. The choice is remembered and restored at launch.

**Laptop drains faster after applying the power policy?** Yes, `sleep 0` prevents deep sleep. Use "Restore default power policy" when you don't need it.

**Link error about `IOAVServiceCreateWithService`?** You're on an Intel Mac; that private symbol only exists in Apple Silicon's IOKit. Remove or stub out `ddcWrite` in `main.swift`.

### How it works

| Method | Implementation |
|---|---|
| User-activity assertion | `IOPMAssertionDeclareUserActivity` |
| DDC/CI power command | `IOAVServiceWriteI2C` to `DCPAVServiceProxy` (Location = External), VCP 0xD6 = 1 — same path as [m1ddc](https://github.com/waydabber/m1ddc) |
| Re-probe | `IOServiceRequestProbe` over `IODisplayConnect` / `AppleCLCD2` / `DCPAVControllerProxy` etc. |
| Mirror reconnect | `CGConfigureDisplayMirrorOfDisplay` on → 1.5 s → off |
| Sharp scaling at native resolution | Private `CGVirtualDisplay` (hiDPI=1) virtual display; `CGConfigureDisplayMirrorOfDisplay` mirrors the panel onto it |
| Hidden HiDPI modes | `CGDisplayCopyAllDisplayModes` + `kCGDisplayShowDuplicateLowResolutionModes`; `CGConfigureDisplayWithDisplayMode` with `.permanently` |
| Global hotkeys | Carbon `RegisterEventHotKey` |

Single Swift file plus one private-API header (`CGVirtualDisplay.h`), no third-party dependencies.

---

## 作者 / Author

**胡震生 Jason Hu** — 「大老二」· X: [@HUZHENSHENG](https://x.com/HUZHENSHENG) · 0xBig2

本项目使用 **Claude Fable 5.1**（Anthropic）协助开发。
Built with the help of **Claude Fable 5.1** (Anthropic).

欢迎 issue / PR，特别是不同显示器型号的兼容性反馈。
Issues and PRs welcome — compatibility reports for other monitor models are especially useful.

## License

MIT © 2026 Jason Hu (胡震生)
