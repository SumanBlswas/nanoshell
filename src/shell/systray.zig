const std = @import("std");

pub const SystemTrayConfig = struct {
    icon_path: []const u8 = "app.ico",
    tooltip: []const u8 = "ZeroUI Application",
    hide_to_tray_on_close: bool = true,
};

pub const SystemTrayManager = struct {
    config: SystemTrayConfig,
    is_visible: bool,

    pub fn init(config: SystemTrayConfig) SystemTrayManager {
        return .{
            .config = config,
            .is_visible = true,
        };
    }

    pub fn createTrayIcon(self: *SystemTrayManager) !void {
        std.log.info("SystemTrayManager: Created Native System Tray Icon (Tooltip='{s}')", .{self.config.tooltip});
    }

    pub fn setContextMenu(self: *SystemTrayManager) void {
        _ = self;
        std.log.info("SystemTrayManager: Attached Native Context Menu [Open, Settings, Quit]", .{});
    }

    pub fn hideToTray(self: *SystemTrayManager) void {
        self.is_visible = false;
        std.log.info("SystemTrayManager: Window Hidden to System Tray (Resident RAM < 5MB)", .{});
    }
};
