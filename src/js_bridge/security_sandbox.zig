const std = @import("std");

pub const SandboxError = error{
    AccessDenied,
    PermissionDisabled,
};

pub const SecuritySandbox = struct {
    allow_fs_read: bool,
    allow_fs_write: bool,
    allow_sys_info: bool,
    allow_dialogs: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SecuritySandbox {
        return .{
            .allow_fs_read = true,
            .allow_fs_write = true,
            .allow_sys_info = true,
            .allow_dialogs = true,
            .allocator = allocator,
        };
    }

    pub fn checkFsRead(self: *const SecuritySandbox, path: []const u8) SandboxError!void {
        _ = path;
        if (!self.allow_fs_read) {
            std.log.err("Sandbox Security Violation: Read File Access Denied", .{});
            return SandboxError.AccessDenied;
        }
    }

    pub fn checkFsWrite(self: *const SecuritySandbox, path: []const u8) SandboxError!void {
        _ = path;
        if (!self.allow_fs_write) {
            std.log.err("Sandbox Security Violation: Write File Access Denied", .{});
            return SandboxError.AccessDenied;
        }
    }

    pub fn checkSysInfo(self: *const SecuritySandbox) SandboxError!void {
        if (!self.allow_sys_info) {
            return SandboxError.PermissionDisabled;
        }
    }

    pub fn checkDialog(self: *const SecuritySandbox) SandboxError!void {
        if (!self.allow_dialogs) {
            return SandboxError.PermissionDisabled;
        }
    }
};
