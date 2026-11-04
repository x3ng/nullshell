# nullshell

按需出现的 Linux 桌面 shell，以 command panel 为中心，不提供常驻任务栏。

基于 Quickshell / Qt Quick；首先支持 Hyprland。项目独立于个人 dotfiles，
Nix 是打包和部署入口之一，不是运行时配置语言。

当前已提取第一批运行时资源，提供独立 Nix 包和隔离预览测试。
尚未接入主机会话：旧服务命名、状态路径和部分 Hyprland Lua 依赖仍待迁移，
桌面包不是已完成的可部署发行版。Rust helper 尚未实现。

- [架构与迁移规范](docs/SPEC.md)
- [配置格式与热加载](docs/CONFIGURATION.md)
- [测试方法与覆盖边界](docs/TESTING.md)
- [跨发行版构建与安装](docs/BUILDING.md)
- [仓库与提交规范](AGENTS.md)
- [源码来源](docs/PROVENANCE.md)
- 上游仓库：git@github.com:x3ng/nullshell.git

许可证待选定；引入第三方代码前核实对应版本和文件的许可。
