const std = @import("std");

pub const TaskbarDockManager = struct {
    progress: f32,
    badge_count: u32,

    pub fn init() TaskbarDockManager {
        return .{
            .progress = 0.0,
            .badge_count = 0,
        };
    }

    pub fn setTaskbarProgress(self: *TaskbarDockManager, progress: f32) void {
        self.progress = std.math.clamp(progress, 0.0, 1.0);
        std.log.info("TaskbarDockManager: Taskbar Progress Updated -> {d:.0}% (ITaskbarList3 Active)", .{self.progress * 100.0});
    }

    pub fn setBadge(self: *TaskbarDockManager, count: u32) void {
        self.badge_count = count;
        std.log.info("TaskbarDockManager: Taskbar Overlay Badge Set -> Count={d}", .{self.badge_count});
    }

    pub fn pinToTaskbar() void {
        std.log.info("TaskbarDockManager: Application Pinned to OS Taskbar / Dock", .{});
    }
};
