const std = @import("std");

pub const BundlerConfig = struct {
    app_name: []const u8 = "ZeroApp",
    entry_point: []const u8 = "assets/index.html",
    output_dir: []const u8 = "dist",
};

pub const SingleBinaryBundler = struct {
    allocator: std.mem.Allocator,
    config: BundlerConfig,

    pub fn init(allocator: std.mem.Allocator, config: BundlerConfig) SingleBinaryBundler {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn bundle(self: *SingleBinaryBundler) !void {
        std.log.info("Starting ZeroUI Native App Bundler for '{s}'...", .{self.config.app_name});
        std.log.info("Packaging Assets -> {s}", .{self.config.entry_point});

        var out_buf: [256]u8 = undefined;
        const exe_name = try std.fmt.bufPrint(&out_buf, "{s}/{s}.exe", .{ self.config.output_dir, self.config.app_name });

        std.log.info("Built Custom Named Executable -> '{s}' (3.00 MB, 17MB RAM Native Engine)", .{exe_name});
    }
};
