const std = @import("std");
const gpu_mod = @import("gpu.zig");
const batch_mod = @import("batch_renderer.zig");

pub const DevToolsOverlay = struct {
    enabled: bool,
    fps: f32,
    frame_time_us: u64,
    draw_call_count: u32,

    pub fn init() DevToolsOverlay {
        return .{
            .enabled = true,
            .fps = 120.0,
            .frame_time_us = 8333, // 8.33ms per frame (120 FPS)
            .draw_call_count = 1,
        };
    }

    pub fn toggle(self: *DevToolsOverlay) void {
        self.enabled = !self.enabled;
        std.log.info("DevToolsOverlay: Toggled In-Engine Inspector (Visible={})", .{self.enabled});
    }

    pub fn renderOverlay(self: *DevToolsOverlay, batch_renderer: *batch_mod.BatchRenderer, gpu_ctx: *gpu_mod.GpuContext) void {
        if (!self.enabled) return;
        _ = gpu_ctx;

        // Draw In-Engine Debug Overlay Bar at top-right
        batch_renderer.drawQuad(.{
            .rect = .{ 10.0, 10.0, 320.0, 48.0 },
            .color = .{ 0.0, 0.0, 0.0, 0.8 },
            .color2 = .{ 0.1, 0.1, 0.1, 0.8 },
            .radii = .{ 8.0, 8.0, 8.0, 8.0 },
            .shadow = .{ 0.0, 4.0, 8.0, 0.0 },
            .shadow_color = .{ 0.0, 0.0, 0.0, 0.5 },
            .params = .{ 0.0, 0.0, 1.0, 0.0 },
        }) catch {};
    }
};
