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

        // Copy Main Executable (search zig-out/bin, bin, root, example_app.exe)
        const possible_srcs = [_][]const u8{
            "zig-out/bin/example_app.exe",
            "example_app.exe",
            "bin/example_app.exe",
            try std.fmt.allocPrint(self.allocator, "bin/{s}.exe", .{self.config.app_name}),
            try std.fmt.allocPrint(self.allocator, "{s}.exe", .{self.config.app_name}),
        };
        const dst_exe_name = try std.fmt.allocPrint(self.allocator, "{s}.exe", .{self.config.app_name});
        defer self.allocator.free(dst_exe_name);
        const dst_exe_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.exe", .{ self.config.output_dir, self.config.app_name });
        defer self.allocator.free(dst_exe_path);

        var copied = false;
        for (possible_srcs) |src| {
            if (cwd.copyFile(src, dist_dir, dst_exe_name, io, .{})) |_| {
                copied = true;
                break;
            } else |_| {}
        }
        if (!copied) {
            std.log.warn("Executable copy warning: Could not locate baseline executable binary", .{});
        }

        // Copy DLLs to dist/ (search vendor/lib, zig-out/bin, and root)
        const dlls = [_][]const u8{ "AppCore.dll", "Ultralight.dll", "UltralightCore.dll", "WebCore.dll", "vcruntime140.dll", "msvcp140.dll", "vcruntime140_1.dll" };
        for (dlls) |dll| {
            const possible_dll_srcs = [_][]const u8{
                try std.fmt.allocPrint(self.allocator, "vendor/lib/{s}", .{dll}),
                try std.fmt.allocPrint(self.allocator, "zig-out/bin/{s}", .{dll}),
                try std.fmt.allocPrint(self.allocator, "bin/{s}", .{dll}),
                dll,
            };
            defer for (possible_dll_srcs) |p| self.allocator.free(p);

            const dst_dll = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.config.output_dir, dll });
            defer self.allocator.free(dst_dll);

            for (possible_dll_srcs) |src_dll| {
                if (copyFileSimple(src_dll, dst_dll)) {
                    break;
                }
            }
        }

        // Copy Resource Files to dist/ and dist/resources/
        const res_files = [_][]const u8{ "icudt67l.dat", "cacert.pem" };
        for (res_files) |file| {
            const possible_res_srcs = [_][]const u8{
                try std.fmt.allocPrint(self.allocator, "vendor/resources/{s}", .{file}),
                try std.fmt.allocPrint(self.allocator, "resources/{s}", .{file}),
                try std.fmt.allocPrint(self.allocator, "zig-out/bin/resources/{s}", .{file}),
                try std.fmt.allocPrint(self.allocator, "bin/{s}", .{file}),
            };
            defer for (possible_res_srcs) |p| self.allocator.free(p);

            const dst_res1 = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.config.output_dir, file });
            defer self.allocator.free(dst_res1);
            const dst_res2 = try std.fmt.allocPrint(self.allocator, "{s}/resources/{s}", .{ self.config.output_dir, file });
            defer self.allocator.free(dst_res2);

            for (possible_res_srcs) |src_res| {
                if (copyFileSimple(src_res, dst_res1)) {
                    _ = copyFileSimple(src_res, dst_res2);
                    break;
                }
            }
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

fn copyFileSimple(src: []const u8, dst: []const u8) bool {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.Dir.cwd().copyFile(src, std.Io.Dir.cwd(), dst, io, .{}) catch return false;
    return true;
}
