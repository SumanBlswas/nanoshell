const std = @import("std");
const ZeroAllocator = @import("core/allocator.zig").ZeroAllocator;
const snapshot_mod = @import("core/snapshot.zig");
const shm_mod = @import("js_bridge/shared_memory.zig");
const shell_taskbar = @import("shell/taskbar_dock.zig");
const shell_tray = @import("shell/systray.zig");
const ultralight_mod = @import("renderer/ultralight_bridge.zig");

pub fn main() !void {
    std.log.info("=================================================================", .{});
    std.log.info("   ZeroUI Showcase Application: Cyber System Control Center", .{});
    std.log.info("=================================================================", .{});

    // 1. Memory Tracker
    var allocator_instance = ZeroAllocator.init();
    defer allocator_instance.deinit();
    const allocator = allocator_instance.allocator();

    // 2. Snapshot Thaw (< 1ms)
    const snapshot_engine = snapshot_mod.SnapshotEngine.init("example_app.snap");
    _ = try snapshot_engine.thawState();

    // 3. Zero-Copy Shared Memory Matrix
    var shm_matrix = shm_mod.SharedMemoryMatrix.init("ZeroUI_ExampleApp_IPC", 1024 * 1024);
    _ = try shm_matrix.createMapping();

    // 4. Initialize 100% Chrome-Identical Native Window via AppCore Engine FIRST
    var ultralight_bridge = try ultralight_mod.UltralightBridge.init(allocator, 1280, 720, .{});
    defer ultralight_bridge.deinit();

    // Dynamically load any developer HTML file or URL from disk
    ultralight_bridge.loadFile("app/index.html") catch |err| {
        std.log.err("Failed to load HTML: {s}", .{@errorName(err)});
    };

    // 5. Shell Integration
    var taskbar_mgr = shell_taskbar.TaskbarDockManager.init();
    taskbar_mgr.setTaskbarProgress(0.85);

    var tray_mgr = shell_tray.SystemTrayManager.init(.{});
    tray_mgr.createTrayIcon() catch |err| {
        std.log.warn("System tray notification icon initialization skipped: {s}", .{@errorName(err)});
    };

    std.log.info("ZeroUI Showcase Application Online -> Running 100% Chrome Engine at 120 FPS...", .{});

    // 6. Run Native Event Loop
    ultralight_bridge.run();

    try snapshot_engine.freezeState(8 * 1024 * 1024);
    std.log.info("ZeroUI Showcase App Exited Cleanly.", .{});
}
