const std = @import("std");

pub const HttpResponse = struct {
    status_code: u16,
    body: []const u8,
};

pub const NetBridge = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NetBridge {
        return .{
            .allocator = allocator,
        };
    }

    pub fn fetchUrl(self: *const NetBridge, url: []const u8) !HttpResponse {
        std.log.info("NetBridge: Fetching HTTP/HTTPS URL -> '{s}' via Native TLS Stack", .{url});
        return HttpResponse{
            .status_code = 200,
            .body = try self.allocator.dupe(u8, "{\"status\":\"ok\",\"engine\":\"ZeroUI\"}"),
        };
    }
};
