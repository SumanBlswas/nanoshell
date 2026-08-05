const std = @import("std");
const dom_mod = @import("../js_runtime/dom_bridge.zig");

pub const ResolvedStyle = struct {
    bg_color: [4]f32,
    bg_color2: [4]f32,
    text_color: [4]f32,
    radii: [4]f32,
    shadow_color: [4]f32,
};

pub const CssResolver = struct {
    pub fn resolveStyle(node: *const dom_mod.DomNode) ResolvedStyle {
        const cls = node.class_name;
        const tag = node.tag_name;
        const id = node.id;

        // 1. Sidebar (.sidebar)
        if (std.mem.indexOf(u8, cls, "sidebar") != null or std.mem.eql(u8, tag, "aside")) {
            return .{
                .bg_color = .{ 0.078, 0.094, 0.176, 0.6 },
                .bg_color2 = .{ 0.05, 0.06, 0.12, 0.6 },
                .text_color = .{ 0.94, 0.96, 0.98, 1.0 },
                .radii = .{ 0.0, 0.0, 0.0, 0.0 },
                .shadow_color = .{ 0.0, 0.0, 0.0, 0.0 },
            };
        }

        // 2. Glass Cards (.glass-card)
        if (std.mem.indexOf(u8, cls, "glass-card") != null or std.mem.indexOf(u8, cls, "metric-card") != null) {
            return .{
                .bg_color = .{ 0.117, 0.16, 0.23, 0.45 },
                .bg_color2 = .{ 0.08, 0.11, 0.17, 0.45 },
                .text_color = .{ 1.0, 1.0, 1.0, 1.0 },
                .radii = .{ 20.0, 20.0, 20.0, 20.0 },
                .shadow_color = .{ 0.0, 0.0, 0.0, 0.3 },
            };
        }

        // 3. Primary Action Button (.btn-primary)
        if (std.mem.indexOf(u8, cls, "btn-primary") != null or std.mem.indexOf(u8, id, "dialog") != null) {
            return .{
                .bg_color = .{ 0.0, 0.95, 0.99, 1.0 }, // #00f2fe
                .bg_color2 = .{ 0.31, 0.67, 0.99, 1.0 }, // #4facfe
                .text_color = .{ 0.0, 0.0, 0.0, 1.0 },
                .radii = .{ 12.0, 12.0, 12.0, 12.0 },
                .shadow_color = .{ 0.0, 0.95, 0.99, 0.3 },
            };
        }

        // 4. Accent Action Button (.btn-accent)
        if (std.mem.indexOf(u8, cls, "btn-accent") != null or std.mem.indexOf(u8, id, "child") != null) {
            return .{
                .bg_color = .{ 0.47, 0.16, 0.79, 1.0 }, // #7928ca
                .bg_color2 = .{ 1.0, 0.0, 0.5, 1.0 }, // #ff0080
                .text_color = .{ 1.0, 1.0, 1.0, 1.0 },
                .radii = .{ 12.0, 12.0, 12.0, 12.0 },
                .shadow_color = .{ 1.0, 0.0, 0.5, 0.3 },
            };
        }

        // 5. Secondary Action Button (.btn-secondary)
        if (std.mem.indexOf(u8, cls, "btn-secondary") != null or std.mem.indexOf(u8, id, "taskbar") != null) {
            return .{
                .bg_color = .{ 1.0, 1.0, 1.0, 0.1 },
                .bg_color2 = .{ 1.0, 1.0, 1.0, 0.1 },
                .text_color = .{ 1.0, 1.0, 1.0, 1.0 },
                .radii = .{ 12.0, 12.0, 12.0, 12.0 },
                .shadow_color = .{ 0.0, 0.0, 0.0, 0.0 },
            };
        }

        // 6. Active Navigation Button (.nav-btn.active)
        if (std.mem.indexOf(u8, cls, "active") != null) {
            return .{
                .bg_color = .{ 0.0, 0.95, 0.99, 0.15 },
                .bg_color2 = .{ 0.31, 0.67, 0.99, 0.15 },
                .text_color = .{ 0.0, 0.95, 0.99, 1.0 },
                .radii = .{ 12.0, 12.0, 12.0, 12.0 },
                .shadow_color = .{ 0.0, 0.95, 0.99, 0.2 },
            };
        }

        // 7. Status Badge (.status-badge)
        if (std.mem.indexOf(u8, cls, "status-badge") != null or std.mem.indexOf(u8, cls, "status") != null) {
            return .{
                .bg_color = .{ 0.0, 0.95, 0.99, 0.08 },
                .bg_color2 = .{ 0.0, 0.95, 0.99, 0.08 },
                .text_color = .{ 0.0, 0.95, 0.99, 1.0 },
                .radii = .{ 12.0, 12.0, 12.0, 12.0 },
                .shadow_color = .{ 0.0, 0.0, 0.0, 0.0 },
            };
        }

        // Default Component Style
        return .{
            .bg_color = .{ 0.1, 0.13, 0.22, 0.5 },
            .bg_color2 = .{ 0.07, 0.09, 0.15, 0.5 },
            .text_color = .{ 0.9, 0.93, 0.96, 1.0 },
            .radii = .{ 12.0, 12.0, 12.0, 12.0 },
            .shadow_color = .{ 0.0, 0.0, 0.0, 0.2 },
        };
    }
};
