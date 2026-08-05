const std = @import("std");
const gpu_mod = @import("gpu.zig");
const win = @import("../core/window.zig").win;

pub const GlyphMetric = struct {
    uv_rect: [4]f32, // [u0, v0, u1, v1]
    width: f32,
    height: f32,
    advance: f32,
};

pub const FontAtlas = struct {
    texture_id: u32,
    glyphs: [128]GlyphMetric,
    font_size: f32,

    pub fn init(font_size: f32) FontAtlas {
        var glyph_table: [128]GlyphMetric = undefined;
        const cell_w = font_size * 0.65;
        const cell_h = font_size * 1.2;

        var i: usize = 0;
        while (i < 128) : (i += 1) {
            glyph_table[i] = GlyphMetric{
                .uv_rect = .{ 0.0, 0.0, 1.0, 1.0 },
                .width = cell_w,
                .height = cell_h,
                .advance = cell_w * 0.95,
            };
        }

        return FontAtlas{
            .texture_id = 1,
            .glyphs = glyph_table,
            .font_size = font_size,
        };
    }
};

pub const MsdfTextEngine = struct {
    allocator: std.mem.Allocator,
    font_size: f32,
    atlas: FontAtlas,

    pub fn init(allocator: std.mem.Allocator, font_size: f32) MsdfTextEngine {
        return .{
            .allocator = allocator,
            .font_size = font_size,
            .atlas = FontAtlas.init(font_size),
        };
    }

    pub fn measureText(self: *const MsdfTextEngine, text: []const u8) [2]f32 {
        const text_length = @as(f32, @floatFromInt(text.len));
        const advance_per_char = self.font_size * 0.55;
        return .{ text_length * advance_per_char, self.font_size * 1.2 };
    }

    pub fn renderTextGpu(self: *const MsdfTextEngine, text: []const u8, x: f32, y: f32, color: [4]f32, gpu_ctx: *gpu_mod.GpuContext) void {
        _ = self;
        _ = text;
        _ = x;
        _ = y;
        _ = color;
        _ = gpu_ctx;
    }
};
