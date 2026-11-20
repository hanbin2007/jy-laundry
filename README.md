# Laundry · 洗衣房状态监测（iOS & ECS 轮询服务）

苏州大学本部前 3 栋洗衣房的实时状态监测、历史占用统计与提醒系统。包含一套部署在阿里云 ECS 上的轻量级分钟级采集与只读 API 服务，以及遵循 Apple Human Interface Guidelines 设计的原生 iOS 客户端（涵盖 SceneKit 3D 洗衣机交互、Swift Charts 时段统计、桌面/锁屏小组件、锁屏实时活动与灵动岛）。

- 仓库：<https://github.com/JYSci-Tech/Laundry>
- 线上接口：`http://laundry.example.com/laundry`（Nginx 反向代理至本机 `127.0.0.1:18787`）
- 技术基调：
  - **服务端**：零第三方依赖 Python 3（仅使用标准库 + SQLite WAL 模式），由 `systemd` 托管常驻 API 与分钟级定时器。
  - **客户端**：零第三方依赖原生 Swift（SwiftUI、SceneKit、Swift Charts、ActivityKit、WidgetKit、UserNotifications）。

---

## 整体架构

```
                 企鹅科技上游接口 (userapi.qiekj.com)
                                  │
            ┌─────────────────────┴─────────────────────┐
            │ 1. systemd timer 每分钟保底采集           │ 2. 客户端 live=1 按需实时拉取（4s 节流）
            ▼                                           ▼
┌───────────────────────────────────────────────────────────────────────┐
│  阿里云 ECS (laundry.example.com) · /opt/laundry                            │
│  ┌─────────────────┐      WAL 读写       ┌─────────────────────────┐  │
│  │  poll.py        │ ─────────────────► │  data/laundry.db        │  │
│  │  (poller.py)    │                    │  machines / states /    │  │
│  └─────────────────┘ ◄───────────────── │  polls / meta (保留 7 天)│  │
│                                         └────────────▲────────────┘  │
│                                                      │ RLE 压缩组装  │
│  ┌───────────────────────────────────────────────────┴─────────────┐  │
│  │  api.py (ThreadingHTTPServer 127.0.0.1:18787)                   │  │
│  │  GET /api/v1/overview?hours=24|168&live=0|1   (X-Token 鉴权)    │  │
│  └─────────────────────────────────▲───────────────────────────────┘  │
│                                    │ Nginx /laundry/ 反向代理         │
└────────────────────────────────────┼──────────────────────────────────┘
                                     │ HTTP JSON
                                     ▼
┌───────────────────────────────────────────────────────────────────────┐
│  iOS 客户端 (Laundry.app + LaundryWidgetsExtension.appex)             │
│  ├── 概览 (OverviewView)   ：倒计时 + 近 24h 条带 + 各时段使用率 + 3D │
│  ├── 记录 (HomeView)       ：整房概览 + 设备列表 + 24h 时刻读数 + 空闲率│
│  ├── 提醒 (Notifier)       ：单机完成提醒 / 全忙空闲提醒 + 触觉反馈   │
│  └── 扩展 (LaundryWidgets) ：桌面/锁屏小组件 + 锁屏实时活动 + 灵动岛  │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 目录结构

```text
Laundry/
├── Info.plist                      # 主应用 Info.plist
├── WidgetsInfo.plist               # Widget & Live Activity 扩展 Info.plist
├── Laundry.xcodeproj/              # Xcode 工程（iOS 26+，文件系统同步组）
├── Laundry/                        # 主应用源码
│   ├── LaundryApp.swift            # 应用入口，注入 LaundryStore 并响应深链 laundry://machine/<id>
│   ├── RootView.swift              # 三栏 TabView（概览 / 记录 / 设置）、5 秒前台轮询循环与完成提醒弹窗
│   ├── OverviewView.swift          # 「概览」页：单机大号倒计时、近 24 小时条带、各时段使用率与 3D 洗衣机
│   ├── Washer3D.swift              # SceneKit 3D 滚筒洗衣机与轮播手势（按需渲染，静止时暂停帧循环）
│   ├── HomeView.swift              # 「记录」页：全房空闲汇总、设备列表（带缩放导航过渡）、图表卡片
│   ├── UsageCard.swift             # 近 24 小时使用记录条形图（支持 0.2s 长按拖拽读数，不阻塞纵向滚动）
│   ├── ForecastCard.swift          # 近 7 天各时段空闲率图表（Swift Charts，顶部预留读数轨道）
│   ├── Forecast.swift              # 基于近 7 天分钟级记录计算全房/单机各小时空闲率与使用率
│   ├── MachineDetailView.swift     # 单机详情页：运行阶段进度、提醒开关、24 小时统计指标
│   ├── SettingsSheet.swift         # 「设置」页：实时活动时段、通知权限、服务器地址与令牌、数据状态
│   ├── WidgetGallery.swift         # 小组件与实时活动预览画廊
│   ├── LaundryStore.swift          # 全局状态中心（@Observable）：轮询、7 天历史缓存、提醒调度、Live Activity 同步
│   ├── LiveActivityManager.swift   # ActivityKit 实时活动生命周期管理（按设定时段自动启停与更新）
│   ├── Notifier.swift              # 本地通知授权、定时调度与状态变更即时触发
│   ├── Surfaces.swift              # 通用卡片容器（SectionCard）、状态胶囊（StatusPill）、进度条等组件
│   └── DemoData.swift              # DEBUG 模式下的确定性模拟数据生成器与启动参数解析
├── LaundryWidgets/                 # WidgetKit & ActivityKit 扩展
│   ├── LaundryWidgetsBundle.swift  # 小组件与实时活动入口 Bundle
│   ├── StatusWidget.swift          # 桌面（Small / Medium）与锁屏（Circular / Rectangular / Inline）小组件
│   └── LaundryLiveActivity.swift   # 锁屏实时活动与灵动岛（Compact / Minimal / Expanded）配置
├── Shared/                         # 主应用与扩展共享模块
│   ├── Models.swift                # Snapshot / MachineState 模型、RLE 解析、自然排序与时间格式化（Fmt）
│   ├── LaundryAPI.swift            # 默认服务器配置与 HistoryAPI 网络请求层
│   ├── LaundryActivityAttributes.swift # ActivityKit 属性与 ContentState 定义
│   ├── DynamicIslandViews.swift    # 灵动岛各形态视图实现
│   ├── LockScreenActivity.swift    # 锁屏实时活动横幅视图实现
│   ├── WidgetViews.swift           # 各尺寸桌面与锁屏小组件视图实现
│   ├── GlanceParts.swift           # 小组件与灵动岛共用的进度环、倒计时、设备磁贴组件
│   ├── Porthole.swift              # Canvas 绘制的洗衣机舱门图标（根据运行/脱水/空闲/离线状态呈现水位与泡沫）
│   ├── Palette.swift               # 语义化色彩系统（亮/暗色自适应）
│   └── Wording.swift               # 统一中文文案与相对时间表述
└── server/                         # 阿里云 ECS 采集与 API 服务
    ├── common.py                   # 常量配置、校区/楼栋名称切分、SQLite 连接与表结构初始化
    ├── poller.py                   # 请求上游接口并写入 machines / states / polls / meta 表
    ├── poll.py                     # 分钟级保底采集脚本（带 flock 文件锁与 7 天历史自动清理）
    ├── api.py                      # 只读 HTTP API 服务（127.0.0.1:18787，内存缓存 + RLE 组装）
    ├── laundry-poll.service        # systemd 单次采集服务单元
    ├── laundry-poll.timer          # systemd 每分钟定时触发器
    ├── laundry-api.service         # systemd 常驻 API 服务单元
    ├── nginx-laundry.conf          # Nginx /laundry/ 反向代理配置
    └── install.sh                  # 一键部署与幂等更新脚本
```

---

## 功能与设计细节

### 1. iOS 客户端

- **概览（`OverviewView`）**
  - **单机聚焦**：顶部展示当前选中设备的剩余时间（`00:34 剩余`）或状态（`空闲` / `即将完成` / `不可用`），精确到分钟并随系统时钟实时倒数。
  - **近 24 小时条带**：单条水平时间轴展示该设备过去 24 小时的运行与空闲区间及洗涤次数。
  - **各时段使用率 & 3D 洗衣机并排布局**：下半屏左侧展示该设备近 7 天 0–23 时的**各时段使用率**柱状图；右侧为 SceneKit 渲染的 3D 洗衣机模型（`Washer3D`）。
  - **按需渲染与丝滑切换**：在下半屏任意位置上下/左右轻扫或点击页码圆点即可切换设备，后方待命设备带弹簧过渡动画；3D 场景仅在动画或滚筒旋转时渲染，静止或退至后台时自动暂停帧循环以节省电量。
- **记录（`HomeView`）**
  - **整房摘要**：首屏大字展示当前空闲台数、总台数及最早空闲时间；全忙时直接提供「有设备空闲时通知我」按钮。
  - **设备列表**：展示每台设备的动态舱门图标、当前阶段（运行中 / 脱水阶段 / 已空闲时长）、进度条与倒计时，点击可缩放过渡至单机详情页（`MachineDetailView`）。
  - **近 24 小时使用记录（`UsageCard`）**：汇总总洗涤次数与平均使用率，并以共享时间轴对比所有设备。支持 **0.2 秒长按后左右拖动**读取任意时刻各机状态（读数直接替换卡片顶部指标区，不遮挡条带；直接上下滑动页面时由 `ScrollView` 顺畅接管，互不抢手势）。
  - **各时段空闲率（`ForecastCard`）**：使用 Swift Charts 展示近 7 天各小时「至少有一台设备空闲」的时间占比，顶部预留专属读数轨道，按住拖动时胶囊标签不越界、不遮挡摘要文字。
- **实时活动与灵动岛（`LaundryWidgets`）**
  - 支持在「设置」中开启并指定每日生效时段（默认 `21:00–23:00`）。
  - **灵动岛**：Compact 形态左侧圆环展示空闲台数（全忙时展示最快完成设备的进度环），右侧展示「空闲」或原生计时器倒数；Minimal 形态展示进度环或倒计时；Expanded 形态展示汇总行与各设备圆角磁贴。
  - **过期降级**：当数据超过一定时间未刷新时，锁屏与灵动岛自动收起详细磁贴，仅保留摘要提示。
  - **深链跳转**：点击小组件或灵动岛中的特定设备，直接通过 `laundry://machine/<id>` 打开「概览」页并定位到对应洗衣机。
- **洗涤完成与空闲提醒**
  - 前台每 5 秒轮询一次：一旦检测到被提醒的设备（或全忙时的任意设备）变为空闲，立即触发本地通知与触觉反馈，并清除对应提醒。
  - 应用退至后台时，基于估算的结束时间由系统 `UNUserNotificationCenter` 准时送达本地通知；若洗涤过程中剩余时间估算发生偏移（> 45 秒），前台轮询会自动重设通知时间。

### 2. ECS 轮询与 API 服务

- **双轨数据采集**：
  1. `laundry-poll.timer` 每分钟整点触发 `poll.py`，使用 `fcntl.flock` 防止并发重入，每小时自动清理超过 7 天（`RETENTION_DAYS = 7`）的 `states` 记录。
  2. 客户端在前台刷新时携带 `live=1`，`api.py` 内部通过 4 秒节流锁（`refresh_live(min_interval=4.0)`）实时请求上游接口并落盘 SQLite，兼顾实时性与上游限流保护。
- **目标过滤**：默认聚焦 `本部` · `前3栋`（排除名称含 `女生` 的设备，可在 `server/common.py` 中调整 `FOCUS_CAMPUS`、`FOCUS_BUILDING`、`FOCUS_EXCLUDE`）。
- **RLE 压缩传输**：每台设备在时间窗口内的分钟级状态序列通过游程编码（Run-Length Encoding）压缩为 `[[startOffset, lengthMinutes, status], ...]`，大幅减小 24 小时与 168 小时（7 天）请求的 JSON 体积。

---

## 接口说明

### `GET /laundry/api/v1/overview`

- **鉴权**：请求头 `X-Token: <token>` 或查询参数 `?token=<token>`（服务端使用 `hmac.compare_digest` 定长比对）。
- **查询参数**：
  - `hours`：时间窗口小时数，范围 `1..168`（客户端日常轮询传 `24`，周统计传 `168`）。
  - `live`：`1` 表示触发一次服务端实时采集（4 秒内最多执行一次）后返回最新数据；`0` 表示直接读取最近一次分钟级采集缓存。
- **状态码约定**：
  - `10`：空闲（`idle`）
  - `20`：运行中（`busy`）
  - `-1`：未知 / 离线 / 无记录（`offline`）
- **响应示例**：

```json
{
  "ok": true,
  "generatedAt": 1763608800,
  "window": {
    "start": 1763522460,
    "minutes": 1440
  },
  "lastPoll": {
    "minute": 1763608800,
    "ok": true,
    "total": 2,
    "idle": 1,
    "error": null,
    "fetchedAt": 1763608802,
    "ageSeconds": 2
  },
  "series": [[0, 1], [5, 2]],
  "machines": [
    {
      "id": 12345,
      "name": "本部前3栋57号机",
      "campus": "本部",
      "building": "前3栋",
      "label": "57号机",
      "status": 10,
      "remaining": "",
      "runs": [
        [0, 1200, 10],
        [1200, 38, 20],
        [1238, 202, 10]
      ]
    }
  ]
}
```

### `GET /laundry/health`

免鉴权健康检查接口，返回 `{"ok": true}`。

---

## 快速开始与部署

### 1. 服务端部署（阿里云 ECS）

1. 在 `server/` 目录下准备访问令牌文件 `server/token`（单行随机字符串，已被 `.gitignore` 忽略；若 `/opt/laundry/data/token` 已存在则无需重复提供）。
2. 在服务器上执行安装脚本：

```bash
cd server
sudo bash install.sh
```

`install.sh` 会自动完成以下操作：
- 创建系统用户 `laundry` 与数据目录 `/opt/laundry/data`（权限 `700`）；
- 安装 `common.py`、`poller.py`、`poll.py`、`api.py` 至 `/opt/laundry`；
- 注册并启动 `laundry-poll.timer` 与 `laundry-api.service`；
- 安装 Nginx 配置 `/etc/nginx/conf.d/laundry-api.conf` 并热重载 Nginx；
- 立即以 `laundry` 用户执行一次首次采集并校验 `http://127.0.0.1:18787/health`。

常用运维命令：

```bash
# 查看 API 服务状态与日志
systemctl status laundry-api.service
journalctl -u laundry-api.service -f

# 查看分钟级采集定时器与日志
systemctl list-timers laundry-poll.timer
journalctl -u laundry-poll.service -n 50
```

### 2. iOS 客户端构建与调试

使用 Xcode 打开 `Laundry.xcodeproj`，选择 `Laundry` Scheme 即可在模拟器或真机上编译运行：

```bash
xcodebuild -project Laundry.xcodeproj \
  -scheme Laundry \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

#### DEBUG 启动参数（`DemoData.swift`）

在 `DEBUG` 构建下，可通过 Scheme 的 **Arguments Passed On Launch** 传入以下参数，无需等待真实洗衣机即可预览各种状态与界面：

| 参数 | 示例 | 说明 |
|---|---|---|
| `-demo <mode>` | `-demo mixed` / `busy` / `spin` / `trio` | 使用内置确定性模拟数据替代服务器（`mixed` 一空一忙、`busy` 全忙、`spin` 脱水阶段、`trio` 三台设备） |
| `-tab <name>` | `-tab records` / `settings` | 启动时直接进入「记录」或「设置」标签页 |
| `-machine <index>` | `-machine 1` | 启动时在「概览」页选中指定下标的设备 |
| `-switchAfter <sec>` | `-switchAfter 2.5` | 启动指定秒数后在「概览」页自动切换到下一台设备（便于录制 3D 轮播过渡） |
| `-scroll <id>` | `-scroll usage` / `forecast` | 在「记录」页启动后自动滚动至「近 24 小时使用记录」或「各时段空闲率」卡片 |
| `-open <id>` | `-open 1` | 在「记录」页启动后直接进入对应设备 ID 的详情页 |
| `-activity` | `-activity` | 忽略时段限制，全天候强制开启实时活动与灵动岛 |
| `-staleSoon` | `-staleSoon` | 让实时活动在启动数秒后进入过期（stale）状态，便于验证降级布局 |
