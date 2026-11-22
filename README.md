# nullshell

Quickshell 的辅助工具与 QML 界面配置。helper 只补充原生能力缺口，不替代或接管 Quickshell。
界面以按需出现的 command panel 为中心，不提供常驻任务栏。

基于 Quickshell / Qt Quick；首先支持 Hyprland。项目独立于个人 dotfiles，
Nix 是打包和部署入口之一，不是运行时配置语言。

## 日常使用：源码就是桌面配置

```sh
git clone git@github.com:x3ng/nullshell.git ~/.config/quickshell/nullshell
```

安装原生 Quickshell、nullshell runtime/helper 和所需系统依赖后，
由 Hyprland 的启动配置分别运行 `nullshell desktop --no-duplicate`、
`nullshell locker --no-duplicate`、`nullshell polkit --no-duplicate` 和
`nullshell sleep-bridge`。不安装 Quickshell 保活 service。
入口是根目录 `shell.qml`，也支持 `quickshell -c nullshell`，但不要重复启动桌面。

直接编辑 `Theme.qml`、`components/` 等 QML 文件；无需构建、提交、更新 flake
或 switch。在源码目录用 `./bin/nullshell preview-panel` 检查布局；锁屏、登录和 Polkit 有独立预览。
真实 locker 与 Polkit 禁止文件热重载，greeter 使用系统部署的快照。
状态和缓存仍在 XDG 状态目录，不写进这个 Git 仓库。

Nix 默认包就是 `packages.runtime`：安装上游 Quickshell、helper、启动器和依赖，
不携带用户 QML，不包装全局 Quickshell，不主动管理用户配置。
用户可以自行使用 Home Manager 管理配置；这不是安装前提，当前也没有专用 HM 模块。
`packages.helper` 可单独安装；`packages.greeter` 使用独立的系统资源快照。
用户启动器使用原生 `-c nullshell`（以及 `nullshell/lock`、`nullshell/polkit`）。
helper 与 QML 只需接口兼容；用到新 helper 命令的 QML 需要一起更新运行环境。
启动不会自动导入旧配置或状态；需要迁移时显式执行 `nullshell migrate-state`。

## 桌面设置

在命令面板搜索 **Appearance settings**、**Display settings** 或 **Idle and lock settings**：

- [外观](docs/APPEARANCE.md)：深浅色和日出日落，默认可离线按时区估算。
- [显示器](docs/DISPLAYS.md)：排列、模式、缩放与镜像。需要显式启用 Hyprland 加载入口；确认过的布局由 Hyprland 独立恢复。
- [空闲计时](docs/CONFIGURATION.md)：调暗、锁屏、息屏以及暂停计时；不改变合盖或系统挂起策略。

- [架构与迁移规范](docs/SPEC.md)
- [配置格式与热加载](docs/CONFIGURATION.md)
- [界面视觉规范](docs/VISUAL.md)
- [源码预览与开发流程](docs/DEVELOPMENT.md)
- [测试方法与覆盖边界](docs/TESTING.md)
- [跨发行版构建与安装](docs/BUILDING.md)
- [运行依赖与宿主服务边界](docs/DEPENDENCIES.md)
- [仓库与提交规范](AGENTS.md)
- [源码来源](docs/PROVENANCE.md)
- [部署与会话生命周期](docs/DEPLOYMENT.md)
- [Rust 后端协议](docs/BACKEND.md)
- 上游仓库：git@github.com:x3ng/nullshell.git

采用 [MIT 许可证](LICENSE)。引入第三方代码前核实对应版本和文件的许可。
