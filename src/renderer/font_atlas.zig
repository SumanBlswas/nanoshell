const std = @import("std");
const gpu_mod = @import("gpu.zig");
const win = @import("../core/window.zig").win;

pub const GlyphUV = struct {
    tex_u0: f32,
    tex_v0: f32,
    tex_u1: f32,
    tex_v1: f32,
    width: f32,
    height: f32,
    advance: f32,
};

pub const SystemFontAtlas = struct {
    texture_id: u32,
    glyphs: [128]GlyphUV,
    font_size: f32,

    pub fn init(font_size: f32) SystemFontAtlas {
        var glyph_table: [128]GlyphUV = undefined;
        const atlas_size: f32 = 512.0;
        const cols: usize = 16;
        const cell_w: f32 = 32.0;
        const cell_h: f32 = 32.0;

        var ch: usize = 32;
        while (ch < 128) : (ch += 1) {
            const col = (ch - 32) % cols;
            const row = (ch - 32) / cols;

            const tu0 = (@as(f32, @floatFromInt(col)) * cell_w) / atlas_size;
            const tv0 = (@as(f32, @floatFromInt(row)) * cell_h) / atlas_size;
            const tu1 = tu0 + (cell_w / atlas_size);
            const tv1 = tv0 + (cell_h / atlas_size);

            const advance_width = if (ch == ' ')
                font_size * 0.35
            else if (ch == 'i' or ch == 'l' or ch == 'I' or ch == '1' or ch == '.' or ch == ':')
                font_size * 0.3
            else if (ch == 'm' or ch == 'w' or ch == 'M' or ch == 'W')
                font_size * 0.7
            else
                font_size * 0.52;

            glyph_table[ch] = GlyphUV{
                .tex_u0 = tu0,
                .tex_v0 = tv0,
                .tex_u1 = tu1,
                .tex_v1 = tv1,
                .width = font_size * 0.6,
                .height = font_size * 1.0,
                .advance = advance_width,
            };
        }

        return SystemFontAtlas{
            .texture_id = 1,
            .glyphs = glyph_table,
            .font_size = font_size,
        };
    }

    pub fn getGlyph(self: *const SystemFontAtlas, ch: u8) GlyphUV {
        if (ch < 32 or ch >= 128) {
            return self.glyphs['?'];
        }
        return self.glyphs[ch];
    }
};
