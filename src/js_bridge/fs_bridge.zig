const std = @import("std");
const SecuritySandbox = @import("security_sandbox.zig").SecuritySandbox;

pub const FsBridge = struct {
    allocator: std.mem.Allocator,
    sandbox: *const SecuritySandbox,

    pub fn init(allocator: std.mem.Allocator, sandbox: *const SecuritySandbox) FsBridge {
        return .{
            .allocator = allocator,
            .sandbox = sandbox,
        };
    }

    pub fn readFile(self: *const FsBridge, path: []const u8) ![]u8 {
        try self.sandbox.checkFsRead(path);
        const file_content = try std.fs.cwd().readFileAlloc(self.allocator, path, 50 * 1024 * 1024);
        return file_content;
    }

    pub fn writeFile(self: *const FsBridge, path: []const u8, data: []const u8) !void {
        try self.sandbox.checkFsWrite(path);
        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
    }

    pub fn readDir(self: *const FsBridge, path: []const u8) !std.ArrayList([]const u8) {
        try self.sandbox.checkFsRead(path);
        var file_list = std.ArrayList([]const u8).empty;

        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            try file_list.append(self.allocator, try self.allocator.dupe(u8, entry.name));
        }

        return file_list;
    }
};
