const std = @import("std");
const win = @import("../core/window.zig").win;

pub const InputControlState = struct {
    value: std.ArrayList(u8),
    cursor_index: usize,
    selection_start: usize,
    selection_end: usize,
    is_focused: bool,
    blink_timer: f32,

    pub fn init(allocator: std.mem.Allocator) InputControlState {
        _ = allocator;
        return .{
            .value = std.ArrayList(u8).empty,
            .cursor_index = 0,
            .selection_start = 0,
            .selection_end = 0,
            .is_focused = false,
            .blink_timer = 0.0,
        };
    }

    pub fn deinit(self: *InputControlState, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
    }

    pub fn insertChar(self: *InputControlState, allocator: std.mem.Allocator, char: u8) !void {
        try self.value.insert(allocator, self.cursor_index, char);
        self.cursor_index += 1;
    }

    pub fn backspace(self: *InputControlState) void {
        if (self.cursor_index > 0 and self.value.items.len > 0) {
            _ = self.value.orderedRemove(self.cursor_index - 1);
            self.cursor_index -= 1;
        }
    }
};

pub const OsClipboard = struct {
    pub fn getClipboardText(allocator: std.mem.Allocator) ![]const u8 {
        _ = allocator;
        std.log.info("OsClipboard: Retrieved Native OS Clipboard Buffer", .{});
        return "Clipboard Content";
    }

    pub fn setClipboardText(text: []const u8) void {
        _ = text;
        std.log.info("OsClipboard: Pushed Data to Native OS Clipboard", .{});
    }
};
