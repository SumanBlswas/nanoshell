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

        const io = std.Io.Threaded.global_single_threaded.io();
        _ = std.Io.Dir.cwd().createDir(io, self.config.output_dir, .default_dir) catch {};

        var dist_dir = std.Io.Dir.cwd().openDir(io, self.config.output_dir, .{}) catch |err| {
            std.log.err("Failed to open output dir: {s}", .{@errorName(err)});
            return err;
        };

        _ = dist_dir.createDir(io, "app", .default_dir) catch {};
        _ = dist_dir.createDir(io, "resources", .default_dir) catch {};

        const cwd = std.Io.Dir.cwd();

        // Copy Main Executable bin/<app_name>.exe -> dist/<app_name>.exe
        const src_exe_path = try std.fmt.allocPrint(self.allocator, "bin/{s}.exe", .{self.config.app_name});
        defer self.allocator.free(src_exe_path);
        const dst_exe_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.exe", .{ self.config.output_dir, self.config.app_name });
        defer self.allocator.free(dst_exe_path);

        _ = cwd.copyFile(src_exe_path, dist_dir, try std.fmt.allocPrint(self.allocator, "{s}.exe", .{self.config.app_name}), io, .{}) catch |err| {
            std.log.warn("Executable copy warning: {s}", .{@errorName(err)});
        };

        // Copy DLLs
        const dlls = [_][]const u8{ "AppCore.dll", "Ultralight.dll", "UltralightCore.dll", "WebCore.dll", "vcruntime140.dll", "msvcp140.dll", "vcruntime140_1.dll" };
        for (dlls) |dll| {
            const src_dll = try std.fmt.allocPrint(self.allocator, "bin/{s}", .{dll});
            defer self.allocator.free(src_dll);
            _ = cwd.copyFile(src_dll, dist_dir, dll, io, .{}) catch {};
        }

        // Copy Resource Files
        const res_files = [_][]const u8{ "icudt67l.dat", "cacert.pem" };
        for (res_files) |file| {
            const src_res = try std.fmt.allocPrint(self.allocator, "bin/{s}", .{file});
            defer self.allocator.free(src_res);
            _ = cwd.copyFile(src_res, dist_dir, file, io, .{}) catch {};
            _ = cwd.copyFile(src_res, dist_dir, try std.fmt.allocPrint(self.allocator, "resources/{s}", .{file}), io, .{}) catch {};
        }

        // Copy app/* files to dist/app/*
        var app_dir_opt = cwd.openDir(io, "app", .{ .iterate = true }) catch null;
        if (app_dir_opt) |*app_dir| {
            var dist_app_dir = dist_dir.openDir(io, "app", .{}) catch null;
            if (dist_app_dir) |*dst_app| {
                var iter = app_dir.iterate();
                while (iter.next(io) catch null) |entry| {
                    if (entry.kind == .file) {
                        _ = app_dir.copyFile(entry.name, dst_app.*, entry.name, io, .{}) catch {};
                    }
                }
            }
        }

        std.log.info("Built Custom Named Executable -> '{s}' (Self-contained release package)", .{dst_exe_path});
    }
};
