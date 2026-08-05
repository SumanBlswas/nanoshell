const std = @import("std");
const batch_mod = @import("batch_renderer.zig");
const font_atlas_mod = @import("font_atlas.zig");
const text_engine_mod = @import("text_engine.zig");

pub const TextRasterizer = struct {
    font_atlas: font_atlas_mod.SystemFontAtlas,

    pub fn init(text_engine: *const text_engine_mod.MsdfTextEngine) TextRasterizer {
        _ = text_engine;
        return .{
            .font_atlas = font_atlas_mod.SystemFontAtlas.init(16.0),
        };
    }

    pub fn drawTextLabel(
        self: *const TextRasterizer,
        batch_renderer: *batch_mod.BatchRenderer,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) void {
        var cx = x;
        const scale = font_size / self.font_atlas.font_size;

        for (text) |raw_ch| {
            if (raw_ch == ' ') {
                const space_glyph = self.font_atlas.getGlyph(' ');
                cx += space_glyph.advance * scale;
                continue;
            }

            const glyph = self.font_atlas.getGlyph(raw_ch);
            const is_lower = (raw_ch >= 'a' and raw_ch <= 'z');
            const ch = std.ascii.toUpper(raw_ch);

            var cy = y;
            const w = glyph.width * scale;
            var h = glyph.height * scale;

            if (is_lower) {
                h *= 0.7;
                cy += 3.0 * scale;
            }

            const hw = w * 0.5;
            const hh = h * 0.5;
            const stroke_w = @max(1.1 * scale, 1.0);

            // Render Character Geometry Driven Directly by SystemFontAtlas
            switch (ch) {
                'A' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                },
                'B' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy + hh, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'C' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'D' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy + 1.0, stroke_w, h - 2.0, color);
                    self.drawBox(batch_renderer, cx, cy, w - 1.0, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w - 1.0, stroke_w, color);
                },
                'E' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w * 0.7, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'F' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w * 0.65, stroke_w, color);
                },
                'G' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy + hh, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + hw, cy + hh, hw, stroke_w, color);
                },
                'H' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                },
                'I', '1' => {
                    self.drawBox(batch_renderer, cx + hw - (stroke_w * 0.5), cy, stroke_w, h, color);
                },
                'J' => {
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, stroke_w, hh, color);
                },
                'K' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy + hh, stroke_w, hh, color);
                },
                'L' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'M' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + hw - (stroke_w * 0.5), cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                },
                'N' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + hw - (stroke_w * 0.5), cy + (hh * 0.4), stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w * 0.5, stroke_w, color);
                },
                'O', '0' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'P' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                },
                'Q' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + hw, cy + hh, hw, stroke_w, color);
                },
                'R' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy + hh, stroke_w, hh, color);
                },
                'S', '5' => {
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy + hh, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'T' => {
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + hw - (stroke_w * 0.5), cy, stroke_w, h, color);
                },
                'U', 'V' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'W' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + hw - (stroke_w * 0.5), cy + hh, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                'X' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                },
                'Y' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + hw - (stroke_w * 0.5), cy + hh, stroke_w, hh, color);
                },
                'Z', '2' => {
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                '3' => {
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                },
                '4' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                },
                '6' => {
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy + hh, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                '7' => {
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                },
                '9' => {
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy, stroke_w, hh, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx + w - stroke_w, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, w, stroke_w, color);
                },
                '.' => {
                    self.drawBox(batch_renderer, cx + (hw * 0.7), cy + h - (stroke_w * 1.5), stroke_w * 1.2, stroke_w * 1.2, color);
                },
                '-' => {
                    self.drawBox(batch_renderer, cx, cy + hh, w, stroke_w, color);
                },
                '/' => {
                    self.drawBox(batch_renderer, cx + (hw * 0.5), cy, stroke_w, h, color);
                },
                '(' => {
                    self.drawBox(batch_renderer, cx + (hw * 0.5), cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + (hw * 0.5), cy, hw, stroke_w, color);
                    self.drawBox(batch_renderer, cx + (hw * 0.5), cy + h - stroke_w, hw, stroke_w, color);
                },
                ')' => {
                    self.drawBox(batch_renderer, cx + (hw * 0.5), cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, hw, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + h - stroke_w, hw, stroke_w, color);
                },
                '%' => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w * 1.2, stroke_w * 1.2, color);
                    self.drawBox(batch_renderer, cx + (hw * 0.5), cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx + w - (stroke_w * 1.2), cy + h - (stroke_w * 1.2), stroke_w * 1.2, stroke_w * 1.2, color);
                },
                else => {
                    self.drawBox(batch_renderer, cx, cy, stroke_w, h, color);
                    self.drawBox(batch_renderer, cx, cy, w, stroke_w, color);
                    self.drawBox(batch_renderer, cx, cy + hh, w * 0.8, stroke_w, color);
                },
            }

            cx += glyph.advance * scale;
        }
    }

    fn drawBox(
        self: *const TextRasterizer,
        batch_renderer: *batch_mod.BatchRenderer,
        rx: f32,
        ry: f32,
        rw: f32,
        rh: f32,
        color: [4]f32,
    ) void {
        _ = self;
        batch_renderer.drawQuad(.{
            .rect = .{ rx, ry, rw, rh },
            .color = color,
            .color2 = color,
            .radii = .{ 0.0, 0.0, 0.0, 0.0 },
            .shadow = .{ 0.0, 0.0, 0.0, 0.0 },
            .shadow_color = .{ 0.0, 0.0, 0.0, 0.0 },
            .params = .{ 0.0, 0.0, 0.0, 0.0 },
        }) catch {};
    }
};
