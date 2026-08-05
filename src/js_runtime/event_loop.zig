const std = @import("std");
const dom_bridge = @import("dom_bridge.zig");
const taffy = @import("../core/taffy_bindings.zig");

pub const EventCallback = struct {
    event_type: []const u8,
    node: *dom_bridge.DomNode,
};

pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    raf_callbacks: std.ArrayList(*const fn () void),
    pending_events: std.ArrayList(EventCallback),

    pub fn init(allocator: std.mem.Allocator) EventLoop {
        return .{
            .allocator = allocator,
            .raf_callbacks = std.ArrayList(*const fn () void).empty,
            .pending_events = std.ArrayList(EventCallback).empty,
        };
    }

    pub fn deinit(self: *EventLoop) void {
        self.raf_callbacks.deinit(self.allocator);
        self.pending_events.deinit(self.allocator);
    }

    pub fn requestAnimationFrame(self: *EventLoop, cb: *const fn () void) !void {
        try self.raf_callbacks.append(self.allocator, cb);
    }

    pub fn dispatchClickEvent(self: *EventLoop, root: *dom_bridge.DomNode, click_x: f32, click_y: f32, taffy_tree: *taffy.TaffyTreeWrapper) void {
        _ = self;
        // Hit-test click_x, click_y against node bounding boxes
        if (taffy_tree.getLayout(root.taffy_node_id)) |box| {
            if (click_x >= box.x and click_x <= box.x + box.width and click_y >= box.y and click_y <= box.y + box.height) {
                std.log.info("Hit-Test Succeeded on Element '{s}' at ({d:.1}, {d:.1})", .{ root.tag_name, click_x, click_y });
            }
        } else |_| {}
    }

    pub fn processFrame(self: *EventLoop) void {
        for (self.raf_callbacks.items) |cb| {
            cb();
        }
        self.raf_callbacks.clearRetainingCapacity();
    }
};
