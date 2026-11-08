# nullshell

按需出现的 Linux 桌面 shell，以 command panel 为中心，不提供常驻任务栏。

基于 Quickshell / Qt Quick；首先支持 Hyprland。项目独立于个人 dotfiles，
Nix 是打包和部署入口之一，不是运行时配置语言。

## 日常使用：源码就是桌面配置

```sh
git clone git@github.com:x3ng/nullshell.git ~/.config/quickshell/nullshell
```

安装原生 Quickshell、nullshell runtime/helper 和所需系统依赖后，
`nullshell session-start` 启动会话服务。入口是根目录 `shell.qml`；
也支持 `quickshell -c nullshell`，但不要和桌面服务同时启动。

直接编辑 `Theme.qml`、`components/` 等 QML 文件；无需构建、提交、更新 flake
或 switch。用 `nullshell preview-panel` 检查布局；锁屏、登录和 Polkit 有独立预览。
真实 locker 与 Polkit 禁止文件热重载，greeter 使用系统部署的快照。
状态和缓存仍在 XDG 状态目录，不写进这个 Git 仓库。

Nix 的 `packages.runtime` 安装依赖、helper、启动器与服务，不携带 QML 快照。
Home Manager 设置 `programs.nullshell.editable = true` 选择它。
`packages.helper` 可单独安装；`packages.desktop` 和 `packages.greeter`
保留完整快照部署。helper 与 QML 只需接口兼容，无需同一 Git 提交。

- [架构与迁移规范](docs/SPEC.md)
- [配置格式与热加载](docs/CONFIGURATION.md)
- [界面视觉规范](docs/VISUAL.md)
- [源码预览与开发流程](docs/DEVELOPMENT.md)
- [测试方法与覆盖边界](docs/TESTING.md)
- [跨发行版构建与安装](docs/BUILDING.md)
- [仓库与提交规范](AGENTS.md)
- [源码来源](docs/PROVENANCE.md)
- [部署与会话生命周期](docs/DEPLOYMENT.md)
- [Rust 后端协议](docs/BACKEND.md)
- 上游仓库：git@github.com:x3ng/nullshell.git

采用 [MIT 许可证](LICENSE)。引入第三方代码前核实对应版本和文件的许可。
