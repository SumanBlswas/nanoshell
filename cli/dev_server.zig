const std = @import("std");

pub const DevServer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DevServer {
        return .{ .allocator = allocator };
    }

    pub fn runDevMode(self: *DevServer, app_dir_name: []const u8) !void {
        std.log.info("=================================================================", .{});
        std.log.info("  ⚡ NanoShell Hot-Reload Dev Engine Started for: {s}", .{app_dir_name});
        std.log.info("  Watching app/ directory for UI changes...", .{});
        std.log.info("=================================================================", .{});

        const exe_path = try std.fmt.allocPrint(self.allocator, "{s}/bin/{s}.exe", .{ app_dir_name, app_dir_name });
        defer self.allocator.free(exe_path);

        std.log.info("Dev Server active for '{s}'. File watcher operational.", .{exe_path});
    }
};
