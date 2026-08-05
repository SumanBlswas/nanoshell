const std = @import("std");
const gpu_mod = @import("gpu.zig");

pub const QuadInstance = extern struct {
    rect: [4]f32,         // [x, y, w, h]
    color: [4]f32,        // [r, g, b, a] Primary Fill
    color2: [4]f32,       // [r, g, b, a] Secondary Fill / Gradient End
    radii: [4]f32,        // [top-left, top-right, bottom-right, bottom-left]
    shadow: [4]f32,       // [offset_x, offset_y, blur, spread]
    shadow_color: [4]f32, // [r, g, b, a]
    params: [4]f32,       // [draw_type, angle_or_scale, border_width, glass_blur]
};

pub const BatchRenderer = struct {
    allocator: std.mem.Allocator,
    instances: std.ArrayList(QuadInstance),
    max_quads: usize,
    draw_calls_last_frame: u32,
    quad_count_last_frame: u32,

    pub fn init(allocator: std.mem.Allocator, max_quads: usize) BatchRenderer {
        var instances = std.ArrayList(QuadInstance).empty;
        instances.ensureTotalCapacity(allocator, max_quads) catch {};
        return .{
            .allocator = allocator,
            .instances = instances,
            .max_quads = max_quads,
            .draw_calls_last_frame = 0,
            .quad_count_last_frame = 0,
        };
    }

    pub fn deinit(self: *BatchRenderer) void {
        self.instances.deinit(self.allocator);
    }

    pub fn beginBatch(self: *BatchRenderer) void {
        self.instances.clearRetainingCapacity();
    }

    pub fn drawQuad(self: *BatchRenderer, instance: QuadInstance) !void {
        if (self.instances.items.len >= self.max_quads) {
            return error.BufferOverflow;
        }
        try self.instances.append(self.allocator, instance);
    }

    pub fn flush(self: *BatchRenderer, gpu_ctx: *gpu_mod.GpuContext) void {
        if (self.instances.items.len == 0) return;
        _ = gpu_ctx;

        gpu_mod.gl.glBegin(gpu_mod.gl.QUADS);
        for (self.instances.items) |q| {
            const x = q.rect[0];
            const y = q.rect[1];
            const w = q.rect[2];
            const h = q.rect[3];

            gpu_mod.gl.glColor4f(q.color[0], q.color[1], q.color[2], q.color[3]);
            gpu_mod.gl.glVertex2f(x, y);
            gpu_mod.gl.glVertex2f(x + w, y);
            gpu_mod.gl.glVertex2f(x + w, y + h);
            gpu_mod.gl.glVertex2f(x, y + h);
        }
        gpu_mod.gl.glEnd();

        self.draw_calls_last_frame = 1;
        self.quad_count_last_frame = @intCast(self.instances.items.len);
    }

    pub fn endBatch(self: *BatchRenderer, gpu_ctx: *gpu_mod.GpuContext) void {
        self.flush(gpu_ctx);
    }
};
