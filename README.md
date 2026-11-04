# nullshell

按需出现的 Linux 桌面 shell，以 command panel 为中心，不提供常驻任务栏。

基于 Quickshell / Qt Quick；首先支持 Hyprland。项目独立于个人 dotfiles，
Nix 是打包和部署入口之一，不是运行时配置语言。

当前 v0.1 已提供独立桌面/greeter 包、会话单元、状态迁移和 Rust 蓝牙配对后端。
隔离预览、真实登录/锁屏认证及 Hyprland/Polkit 虚拟机测试已通过；
真实硬件验收与主机旧部署的切换尚未执行。

- [架构与迁移规范](docs/SPEC.md)
- [配置格式与热加载](docs/CONFIGURATION.md)
- [测试方法与覆盖边界](docs/TESTING.md)
- [跨发行版构建与安装](docs/BUILDING.md)
- [仓库与提交规范](AGENTS.md)
- [源码来源](docs/PROVENANCE.md)
- [部署与会话生命周期](docs/DEPLOYMENT.md)
- [Rust 后端协议](docs/BACKEND.md)
- 上游仓库：git@github.com:x3ng/nullshell.git

采用 [MIT 许可证](LICENSE)。引入第三方代码前核实对应版本和文件的许可。
