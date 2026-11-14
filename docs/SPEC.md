# nullshell v0.1 架构与迁移规范

状态：架构方向和 Rust 选型已确认；具体后端协议在实现前定案。本文描述目标，不代表能力已完成。

## 产品范围

无常驻 bar；command panel 默认展示有用状态，输入后统一搜索应用、窗口与操作。
迁移保留通知、OSD、壁纸、多显示器、锁屏、greeter、Polkit 与设备控制。
第一版只承诺 Hyprland/Linux；其他 compositor 通过适配层扩展，不宣称开箱支持。

## 分层与所有权

1. QML views：布局、交互、动画、短期页面状态；不得构造系统命令或实现认证协议。
2. Application：搜索 provider、稳定身份、action 分发、请求生命周期；不依赖页面生命周期。
3. Adapters：按功能提供能力、可用性、状态、异步结果；不要为每个原生属性重复建立模型。
4. Providers：Quickshell 原生 API 优先；缺失协议用自有 helper；CLI 过渡实现明确登记。
5. Configuration/state：配置默认值、用户偏好、运行状态分别有版本与验证。
6. Integration：打包、会话生命周期、PAM/greetd/systemd/portal 接入；不包含个人 UI 偏好。

设备状态以原生系统服务为准。操作 accepted 不等于 completed；适配层必须区分
请求受理、结果和超时，并处理取消、设备消失、服务重连。UI 不解析 helper 输出。

## 进程与安全边界

- desktop：panel、通知服务、OSD、壁纸及桌面适配层；详情页按需加载。
- lock：独立用户进程，使用 Wayland session-lock 与 PAM；禁止认证期间热重载。
- polkit：独立用户认证代理；授权决策由系统 Polkit authority 执行。
- greeter：greetd 启动的专用账户进程，共享 UI 资源，不加载用户 HOME；可读取安装时授权的独立外观快照。
- 自有 helper：仅在明确需要的能力上启用；默认不增加通用常驻 daemon。

独立打包不会替代 compositor、PipeWire、NetworkManager、BlueZ、logind、PAM、
Polkit 或 portal。nullshell 的目标是统一交互与协调，不重写这些基础服务。
桌面、locker 和 Polkit 由 Hyprland 显式直接启动，不安装 Quickshell 保活 unit。
Quickshell 使用 --no-duplicate 防重复启动；退出会话时客户端随 Wayland 断开退出。
蓝牙 helper 按需运行；仅未来确有常驻需要的 helper 才单独设计 service。

## 配置与动态数据

wallpaper.json 保留静态默认配置；终端 argv 与 idle 超时有独立用户配置。
Keep awake、通知历史、壁纸选择，以及 greeter 上次成功登录的用户名和会话
分别保存状态；greeter 状态由专用账户持有。

目标路径：

- 包内 defaults：只读、可移植默认值，不含个人用户名、HOME 或显示器名称。
- $XDG_CONFIG_HOME/nullshell/config.json：版本化用户设置，用户/dotfiles 管理。
- $XDG_STATE_HOME/nullshell/：Keep awake、通知历史及 UI 保存的偏好覆盖；原子写入。
- $XDG_CACHE_HOME/nullshell/：可重建缓存；$XDG_RUNTIME_DIR 下放临时 IPC 资源。
- greeter：独立系统状态保存上次成功认证的用户名与会话 ID；不读取上述用户路径。

优先级：包默认值 < 用户配置 < 明确允许 UI 修改的持久覆盖。
每个状态域只有一个写入者，多进程读者订阅更新。
每个可修改字段须声明所有者、覆盖/重置行为和是否即时生效，不允许整份运行状态覆盖配置。
无效热加载保留上一次有效配置并反馈错误；首次启动使用安全默认值。
布局、动画和主题定义直接在本地 QML 配置仓库编辑。
外观同步例外：桌面将当前深浅模式及实际颜色导出为 version 1 数据快照；
greeter 只读取验证过的导出数据，不加载用户提供的 QML；锁屏和 Polkit 保持用户侧机制。
跨账户导出由安装配置指定来源账户与目录；不增加常驻 daemon。
外观和壁纸是独立事件域。greeter 壁纸只同步全局默认，复制受限图片而非 HOME 链接；
独立描述文件原子发布，资源只保留两个固定槽位，取消时清理，不积累历史。
darkman 保持用户会话的模式来源，greeter 未登录时使用最后一次快照，不独立调度。
运行态和已有行为设置继续使用现有 XDG 文件；helper 与 QML 仅要求协议兼容。
桌面入口为仓库根目录 shell.qml，runtime 包不绑定 QML 快照。
greeter 默认使用包内 QML；可通过显式安装命令复制工作树资源到系统管理目录覆盖。
安装仅处理代码文件，不执行用户 QML、不重启认证进程；下一次 greeter 启动生效。
主题数据同步、QML 程序安装与运行依赖更新是三个独立接口。
旧 quickshell 状态按版本迁移一次，保留源文件；尤其保证 Keep awake 不因迁移丢失。

## 扩展后端契约

建议新后端统一采用 Rust（Cargo + serde/serde_json + zbus；异步运行时随协议实现确定）。
QML/JS 保留界面与轻量应用逻辑；已有 Python helper 保留到替代验收通过。
选择 Rust 是为了类型化协议与资源生命周期管理，不宣称其 UI 性能优于 Go。
Go 也是可行方案，但第一版不并行维护两种扩展语言；当前不需要 C++/Qt 插件。
不引入 QML 原生插件 ABI，除非存在不可由进程协议解决的已证实需求。
按需子进程可使用带版本的 JSON Lines/stdin/stdout：请求 ID、结果、事件、取消、
超时、消息长度限制和退出行为必须定义；日志走 stderr，敏感信息禁止进日志或 argv。
需要共享常驻能力时另行设计 Unix socket 或 D-Bus，不提前搭建插件宿主。
睡眠延迟抑制器必须由持有实际文件描述符的进程维护；普通 JSON 应答不能替代锁定确认。

## 能力迁移顺序

1. 提取现有代码与许可证/来源记录，建立独立可构建包及安全预览；不先重写 UI。
2. 解耦个人 Hyprland Lua、用户名、终端、壁纸；提供稳定 CLI 和配置 schema。
3. 切换 dotfiles/Nix 引用；验证成功后删除旧实现，避免两个长期维护源。
4. 优先替换 Bluetooth 配对的文本交互桥，使用实际 BlueZ Agent1 协议。
5. v0.1 保留 hypridle 负责睡眠握手；未来替换必须单独实现和验收。必须取得锁屏协议确认后
   才释放 logind delay inhibitor，并测试 suspend/resume、超时、崩溃与外部锁定请求。
6. 根据原生 API 的实际缺口增加后端，不重写已经可用的音频、媒体、电池等模块。

## 打包和开发目标

独立 flake 提供 desktop、greeter、预览入口、开发环境、HM/NixOS 模块。
普通发行版提供同一份资源与命令的安装方式；不要求安装 Nix。
release 使用只读资源；development 显式选择源码目录，不硬编码开发者路径。
预览不注册通知/Polkit 服务，不认证、不锁屏、不执行电源操作。
后端按最终语言使用标准工具链；QML 使用 Qt 工具检查，Nix 使用 nixfmt。

## 参考 DMS 的规则

参考其模块边界、原生能力使用、协议实现和生命周期处理；不搬入整套产品 UX。
引入代码前记录具体仓库、commit、文件、许可证及修改；保留所需声明。
尚未审计 DMS 当前代码或许可证，不假定其组件采用统一许可。

## 验收

- 保留目前搜索、窗口操作、通知、壁纸、锁屏和设备操作行为；动态标题不重建 hover 项。
- Keep awake 跨重载/重启保持；多屏热插拔正确；配置错误不会破坏有效状态。
- desktop 重启不影响已启动应用、锁屏或正在进行的 Polkit 会话。
- 不同 DE 不误启动桌面服务；缺失硬件/可选服务给出明确不可用状态。
- greeter 不依赖用户目录；实际 PAM/greetd/睡眠流程需要真实会话验收，预览不算通过。
- 仓库只含源码、正式文档及有意义的测试；构建产物、截图、临时诊断留在仓库外。

## 材质与回退

Quickshell 是上游运行时，nullshell 维护 QML、桌面适配和必要的 helper，
不维护 Quickshell 分支。材质参数属于内部 UI 实现，本轮不新增用户配置选项。

桌面玻璃使用 BackgroundEffect 的区域请求，不依赖个人 layer rules 开启模糊。
当前 Quickshell 接口没有通用的能力或请求成功回执；因此只对已支持的 Hyprland
读取 `decoration:blur:enabled`，启动及浮层重新打开时刷新。未知合成器、禁用、
查询失败和超时均使用不透明底色，并取消模糊请求。用户针对单个窗口的规则
仍可能覆盖合成效果；这不是逐窗口模糊成功的保证，也不是跨合成器支持声明。
锁屏自行绘制并模糊壁纸，使用独立的 frosted 材质，不读取桌面截图。

## 外观同步的所有权边界

| 内容 | 所有者/写入方 | 消费者 |
| --- | --- | --- |
| 用户会话当前深浅模式 | darkman；手动操作也提交给它 | 桌面订阅，保留现有用户侧模式状态 |
| 配色与界面程序 | nullshell 用户侧 QML/公共视觉组件 | 各界面使用组件；只导出颜色数据给 greeter |
| 用户壁纸选择及原图 | 用户侧 WallpaperState/用户文件 | 桌面与锁屏沿用现有用户侧机制 |
| greeter 颜色快照、壁纸描述及图片副本 | 用户侧按需导出器 | greeter 只读，预览可注入相同数据 |
| 跨账户路径和目录权限 | 系统安装模块 | 向生产者和消费者注入，不由 QML 猜测 HOME |
| 登录过程及上次登录选择 | greeter 专用账户 | 与外观目录独立，不向用户侧导出 |

共享 QML 组件不等于共享可写运行状态。greeter 外观快照是用户侧结果的派生副本，
不是第二套主题配置，不允许反向覆盖用户设置。外观和壁纸分别由自己的事件触发；
一个域更新失败，不重置另一个域或认证过程。greeter 没有跨账户写入用户偏好的接口。
本次不改变锁屏/Polkit 的入口或状态协议，也不增加全局外观 daemon。
