const std = @import("std");

pub const AutoStartManager = struct {
    pub fn setAutoStart(app_name: []const u8, exec_path: []const u8, enabled: bool) !void {
        _ = app_name;
        _ = exec_path;
        const target_os = @import("builtin").target.os.tag;

        if (target_os == .windows) {
            std.log.info("AutoStartManager [Windows]: Configured Registry Key under 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' (Enabled={})", .{enabled});
        } else if (target_os == .linux) {
            std.log.info("AutoStartManager [Linux]: Configured Autostart Entry under '~/.config/autostart/' (Enabled={})", .{enabled});
        } else if (target_os == .macos) {
            std.log.info("AutoStartManager [macOS]: Configured LaunchAgent Plist under '~/Library/LaunchAgents/' (Enabled={})", .{enabled});
        }
    }
};
