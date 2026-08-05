const std = @import("std");
const SecuritySandbox = @import("security_sandbox.zig").SecuritySandbox;
const win = @import("../core/window.zig").win;

pub const DialogBridge = struct {
    sandbox: *const SecuritySandbox,

    pub fn init(sandbox: *const SecuritySandbox) DialogBridge {
        return .{
            .sandbox = sandbox,
        };
    }

    pub fn showMessageBox(self: *const DialogBridge, title: [*:0]const u8, message: [*:0]const u8) !void {
        try self.sandbox.checkDialog();

        var title_buf: [256]u16 = undefined;
        const t_len = try std.unicode.utf8ToUtf16Le(&title_buf, std.mem.span(title));
        title_buf[t_len] = 0;

        var msg_buf: [1024]u16 = undefined;
        const m_len = try std.unicode.utf8ToUtf16Le(&msg_buf, std.mem.span(message));
        msg_buf[m_len] = 0;

        _ = MessageBoxW(null, @ptrCast(&msg_buf), @ptrCast(&title_buf), 0x00000000 | 0x00000040);
    }
};

pub extern "user32" fn MessageBoxW(
    hWnd: win.HWND,
    lpText: [*:0]const u16,
    lpCaption: [*:0]const u16,
    uType: win.UINT,
) callconv(.winapi) i32;
