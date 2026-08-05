const std = @import("std");
const taffy_c = @import("../core/taffy_bindings.zig").c;

pub const CssColor = [4]f32;

pub fn parseDimension(val: []const u8) taffy_c.CTaffyDimension {
    const trimmed = std.mem.trim(u8, val, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "auto")) {
        return .{ .value = 0.0, .dim_type = taffy_c.TAFFY_DIMENSION_AUTO };
    }
    if (std.mem.endsWith(u8, trimmed, "%")) {
        const num_str = trimmed[0 .. trimmed.len - 1];
        const parsed = std.fmt.parseFloat(f32, num_str) catch 0.0;
        return .{ .value = parsed, .dim_type = taffy_c.TAFFY_DIMENSION_PERCENT };
    }
    if (std.mem.endsWith(u8, trimmed, "px")) {
        const num_str = trimmed[0 .. trimmed.len - 2];
        const parsed = std.fmt.parseFloat(f32, num_str) catch 0.0;
        return .{ .value = parsed, .dim_type = taffy_c.TAFFY_DIMENSION_POINTS };
    }

    const parsed = std.fmt.parseFloat(f32, trimmed) catch 0.0;
    return .{ .value = parsed, .dim_type = taffy_c.TAFFY_DIMENSION_POINTS };
}

pub fn parseColor(val: []const u8) CssColor {
    const trimmed = std.mem.trim(u8, val, " \t\r\n");
    if (trimmed.len > 0 and trimmed[0] == '#') {
        if (trimmed.len == 7) { // #RRGGBB
            const r = std.fmt.parseInt(u8, trimmed[1..3], 16) catch 0;
            const g = std.fmt.parseInt(u8, trimmed[3..5], 16) catch 0;
            const b = std.fmt.parseInt(u8, trimmed[5..7], 16) catch 0;
            return .{ @as(f32, @floatFromInt(r)) / 255.0, @as(f32, @floatFromInt(g)) / 255.0, @as(f32, @floatFromInt(b)) / 255.0, 1.0 };
        }
    }
    // Default Fallback Color
    return .{ 0.2, 0.4, 0.8, 1.0 };
}

pub fn applyCssProperty(style: *taffy_c.CTaffyStyle, prop: []const u8, val: []const u8) void {
    if (std.mem.eql(u8, prop, "width")) {
        style.width = parseDimension(val);
    } else if (std.mem.eql(u8, prop, "height")) {
        style.height = parseDimension(val);
    } else if (std.mem.eql(u8, prop, "flex-direction") or std.mem.eql(u8, prop, "flexDirection")) {
        if (std.mem.eql(u8, val, "column")) {
            style.flex_direction = taffy_c.TAFFY_FLEX_DIRECTION_COLUMN;
        } else if (std.mem.eql(u8, val, "row")) {
            style.flex_direction = taffy_c.TAFFY_FLEX_DIRECTION_ROW;
        }
    } else if (std.mem.eql(u8, prop, "display")) {
        if (std.mem.eql(u8, val, "flex")) {
            style.display = taffy_c.TAFFY_DISPLAY_FLEX;
        } else if (std.mem.eql(u8, val, "grid")) {
            style.display = taffy_c.TAFFY_DISPLAY_GRID;
        } else if (std.mem.eql(u8, val, "none")) {
            style.display = taffy_c.TAFFY_DISPLAY_NONE;
        }
    }
}
