pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Shared commands for search and visible controls. Services remain the owners
// of state and asynchronous feedback; navigation is handled by LauncherPanel.
Scope {
    id: root
    required property var services
    required property var appearance
    required property var keyboard
    required property var hyprControls
    readonly property var session: sessionActions
    SessionActions { id: sessionActions }
    signal navigateRequested(string section)
    readonly property var panelActions: ["overview", "desktop", "wifi", "bluetooth", "audio", "notifications", "appearance", "session", "wallpaper", "brightness"]
    readonly property var entries: [
        {id: "session", description: "Lock, sleep, log out, restart or shut down", title: "Power and session", keywords: "power shutdown reboot logout suspend 电源 关机 重启 注销 休眠 锁屏", icon: "power", enabled: true},
        {id: "appearance", description: "Light, dark, automatic and location settings", title: "Appearance settings", keywords: "theme auto solar 深色 浅色 自动 定位 主题 外观", icon: "brightness", enabled: true},
        {id: "auto", description: "Follow local sunrise and sunset", title: "Use automatic appearance", keywords: "theme solar 自动 主题 日出 日落", icon: "clock", enabled: appearance.appearanceAvailable},
        {id: "appearance-resume", description: "Clear the temporary appearance override", title: "Resume automatic appearance", keywords: "theme solar 恢复 自动 主题", icon: "clock", enabled: appearance.appearanceAvailable && appearance.automatic && appearance.overrideUntil > 0},
        {id: "desktop", description: "Browse windows, workspaces and layouts", title: "Manage windows and workspaces", keywords: "desktop layout float fullscreen move close 桌面 窗口 工作区 布局 平铺 浮动 全屏 移动 关闭", icon: "window", enabled: true},
        {id: "overview", description: "Adjust frequent controls and see current status", title: "Open quick controls", keywords: "status settings 总览 状态 系统 设置 控制 快捷", icon: "app", enabled: true},
        {id: "wifi", description: "Choose a network and manage connections", title: "Wi-Fi settings", keywords: "network wireless 网络 无线", icon: "wifi", enabled: true},
        {id: "bluetooth", description: "Connect, pair and manage devices", title: "Bluetooth settings", keywords: "devices 蓝牙 设备", icon: "bluetooth", enabled: true},
        {id: "audio", description: "Choose output and microphone devices", title: "Audio devices", keywords: "sound volume output input 声音 音频 音量 输出 输入", icon: "headphones", enabled: true},
        {id: "wallpaper", description: "Choose a shared desktop and lock-screen background", title: "Choose wallpaper", keywords: "background image desktop lock 壁纸 背景 桌面 锁屏", icon: "window", enabled: true},
        {id: "brightness", description: "Adjust the display backlight", title: "Adjust brightness", keywords: "display screen 亮度 屏幕 显示", icon: "brightness", enabled: true},
        {id: "wifi-toggle", description: "Enable or disable the wireless radio", title: services.controls.wifiEnabled ? "Turn off Wi-Fi" : "Turn on Wi-Fi", keywords: "wireless radio 无线 网络 开关", icon: "wifi", enabled: services.controls.wifiAvailable && !services.controls.wifiBusy},
        {id: "bluetooth-toggle", description: "Enable or disable the Bluetooth radio", title: services.controls.bluetoothEnabled ? "Turn off Bluetooth" : "Turn on Bluetooth", keywords: "radio 蓝牙 开关", icon: "bluetooth", enabled: services.controls.bluetoothAvailable && !services.controls.bluetoothBusy},
        {id: "notifications", description: "Read recent notifications and history", title: "Notification center", keywords: "messages 通知 历史 消息", icon: "app", enabled: true},
        {id: "output-mute", description: "Toggle sound on the current output", title: services.sink?.audio?.muted ? "Unmute output" : "Mute output", keywords: "sound speaker 静音 扬声器 取消静音", icon: "volume", enabled: !!services.sink?.audio},
        {id: "mic-mute", description: "Toggle the current microphone", title: services.source?.audio?.muted ? "Unmute microphone" : "Mute microphone", keywords: "mic 静音 麦克风 取消静音", icon: "mic", enabled: !!services.source?.audio},
        {id: "keep-awake", description: "Pause or resume automatic dimming, locking and screen power-off", title: services.keepAwake ? "Resume idle behavior" : "Keep awake", keywords: "idle dim lock screen 保持唤醒 空闲 息屏 自动锁屏", icon: "eye", enabled: true},
        {id: "light", description: "Switch desktop and applications to light mode", title: "Use light appearance", keywords: "theme 浅色 主题 外观", icon: "brightness", enabled: appearance.appearanceAvailable && appearance.appearanceKnown},
        {id: "dark", description: "Switch desktop and applications to dark mode", title: "Use dark appearance", keywords: "theme 深色 主题 外观", icon: "moon", enabled: appearance.appearanceAvailable && appearance.appearanceKnown},
        {id: "keyboard", description: "Toggle the on-screen keyboard", title: keyboard.shown ? "Hide screen keyboard" : "Show screen keyboard", keywords: "osk 屏幕键盘 虚拟键盘", icon: "keyboard", enabled: keyboard.available && !keyboard.pending},
        {id: "lock", description: "Secure the current session", title: "Lock screen", keywords: "session 锁屏 锁定", icon: "window", enabled: hyprControls.available && !hyprControls.busy}
    ].concat(services.controls.powerProfiles.map(profile => ({
        id: "power:" + profile,
        title: "Use power profile: " + profile,
        description: "Change performance and energy use",
        keywords: "battery energy 电源 性能 节能 均衡",
        icon: "battery", enabled: services.controls.powerAvailable
    }))).map(action => Object.assign({}, action, {actionType: panelActions.includes(action.id) ? "panel" : "operation"}))

    // Shared by search and buttons. The service still validates at dispatch time.
    function available(id) {
        return entries.some(action => action.id === id && action.enabled);
    }

    // true means accepted, not async completion and not a request to close UI.
    // Service feedback signals report asynchronous failures independently.
    function execute(id) {
        if (!available(id)) return false;
        if (["overview", "desktop", "wifi", "bluetooth", "audio", "notifications", "appearance", "wallpaper", "session"].includes(id)) {
            navigateRequested(id);
            return true;
        }
        switch (id) {
        case "brightness": navigateRequested("overview"); break;
        case "wifi-toggle": return services.controls.toggleWifi();
        case "bluetooth-toggle": return services.controls.toggleBluetooth();
        case "output-mute": return services.toggleOutputMute();
        case "mic-mute": return services.toggleMicMute();
        case "keep-awake": return services.toggleKeepAwake();
        case "auto": return appearance.selectMode("auto");
        case "appearance-resume": appearance.resumeAutomatic(); return true;
        case "light": return appearance.setTheme(false);
        case "dark": return appearance.setTheme(true);
        case "keyboard": return keyboard.toggle();
        case "lock": return hyprControls.lock();
        default:
            if (!id.startsWith("power:")) return false;
            return services.controls.setPowerProfile(id.slice(6));
        }
        return true;
    }
}
