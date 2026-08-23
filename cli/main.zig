const std = @import("std");
const installer = @import("installer.zig");

extern "kernel32" fn GetCommandLineW() callconv(.c) [*:0]const u16;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const cmd_line_ptr = GetCommandLineW();
    const len = std.mem.indexOfSentinel(u16, 0, cmd_line_ptr);

    var args_iter = try std.process.Args.Iterator.Windows.init(allocator, cmd_line_ptr[0..len]);
    defer args_iter.deinit();

    _ = args_iter.skip(); // skip executable name

    const subcmd = args_iter.next() orelse "";

    if (std.mem.eql(u8, subcmd, "build")) {
        std.log.info("NanoShell Build", .{});
        std.log.info("Building production release binary...", .{});

        const io = std.Io.Threaded.global_single_threaded.io();
        _ = std.Io.Dir.cwd().createDir(io, "dist", .default_dir) catch {};

        var config = installer.loadConfig(allocator) catch installer.AppConfig{};
        defer config.deinit(allocator);

        var bundler = @import("bundler.zig").SingleBinaryBundler.init(allocator, .{
            .app_name = config.name,
            .entry_point = "app/index.html",
            .output_dir = "dist",
        });
        try bundler.bundle();

        std.log.info("Build complete.", .{});
        return;
    }

    if (std.mem.eql(u8, subcmd, "package") or std.mem.eql(u8, subcmd, "installer")) {
        std.log.info("NanoShell Build & Package", .{});
        std.log.info("Building production release binary...", .{});

        const io = std.Io.Threaded.global_single_threaded.io();
        _ = std.Io.Dir.cwd().createDir(io, "dist", .default_dir) catch {};

        var config = installer.loadConfig(allocator) catch installer.AppConfig{};
        defer config.deinit(allocator);

        var bundler = @import("bundler.zig").SingleBinaryBundler.init(allocator, .{
            .app_name = config.name,
            .entry_point = "app/index.html",
            .output_dir = "dist",
        });
        try bundler.bundle();

        try installer.run(allocator);
        return;
    }

    const dev_server = @import("dev_server.zig");

    if (std.mem.eql(u8, subcmd, "start")) {
        var server = dev_server.DevServer.init(allocator);
        try server.runDevMode(".");
        return;
    }

    // Scaffolding a new NanoShell project if an app name is passed
    if (subcmd.len > 0 and !std.mem.startsWith(u8, subcmd, "-")) {
        const app_dir_name = subcmd;
        std.log.info("Scaffolding new NanoShell app in .\\{s}...", .{app_dir_name});

        const io = std.Io.Threaded.global_single_threaded.io();
        _ = std.Io.Dir.cwd().createDir(io, app_dir_name, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                std.log.err("Failed to create directory '{s}': {s}", .{ app_dir_name, @errorName(err) });
                return err;
            }
        };

        var app_dir = std.Io.Dir.cwd().openDir(io, app_dir_name, .{}) catch |err| {
            std.log.err("Failed to open directory '{s}': {s}", .{ app_dir_name, @errorName(err) });
            return err;
        };

        _ = app_dir.createDir(io, "app", .default_dir) catch {};
        _ = app_dir.createDir(io, "assets", .default_dir) catch {};
        _ = app_dir.createDir(io, "resources", .default_dir) catch {};
        _ = app_dir.createDir(io, "bin", .default_dir) catch {};
        _ = app_dir.createDir(io, "bin/resources", .default_dir) catch {};

        // Write placeholder assets/icon.ico
        try app_dir.writeFile(io, .{ .sub_path = "assets/icon.ico", .data = "NANO_ICON" });

        // Write default nanoshell.json with full window management settings
        const json_content = try std.fmt.allocPrint(allocator,
            "{{\n" ++
            "  \"name\": \"{s}\",\n" ++
            "  \"version\": \"1.0.0\",\n" ++
            "  \"author\": \"Your Name\",\n" ++
            "  \"description\": \"Blazing fast desktop app created with NanoShell\",\n" ++
            "  \"icon\": \"assets\\\\icon.ico\",\n" ++
            "  \"exe_name\": \"{s}.exe\",\n" ++
            "  \"window\": {{\n" ++
            "    \"width\": 1280,\n" ++
            "    \"height\": 720,\n" ++
            "    \"resizable\": true,\n" ++
            "    \"frameless\": false,\n" ++
            "    \"transparent\": false,\n" ++
            "    \"always_on_top\": false\n" ++
            "  }}\n" ++
            "}}\n",
            .{ app_dir_name, app_dir_name }
        );
        defer allocator.free(json_content);

        try app_dir.writeFile(io, .{ .sub_path = "nanoshell.json", .data = json_content });

        // Write default package.json so npm start, npm run build, npm run package work out-of-the-box
        const pkg_json_content = try std.fmt.allocPrint(allocator,
            "{{\n" ++
            "  \"name\": \"{s}\",\n" ++
            "  \"version\": \"1.0.0\",\n" ++
            "  \"description\": \"A NanoShell native desktop application\",\n" ++
            "  \"main\": \"app/index.html\",\n" ++
            "  \"scripts\": {{\n" ++
            "    \"start\": \".\\\\bin\\\\{s}.exe --dev\",\n" ++
            "    \"build\": \".\\\\bin\\\\{s}.exe --build\",\n" ++
            "    \"package\": \".\\\\bin\\\\{s}.exe --package\"\n" ++
            "  }},\n" ++
            "  \"keywords\": [\"nanoshell\", \"desktop\", \"native\"],\n" ++
            "  \"author\": \"\",\n" ++
            "  \"license\": \"MIT\"\n" ++
            "}}\n",
            .{ app_dir_name, app_dir_name, app_dir_name, app_dir_name }
        );
        defer allocator.free(pkg_json_content);

        try app_dir.writeFile(io, .{ .sub_path = "package.json", .data = pkg_json_content });

        // Write default HTML/CSS/JS inside app/
        const html_content =
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\  <meta charset="UTF-8">
            \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\  <title>NanoShell Application</title>
            \\  <link rel="stylesheet" href="styles.css">
            \\</head>
            \\<body>
            \\  <div class="container">
            \\    <div class="fps-badge"><span id="fps-val">120</span> FPS Locked</div>
            \\    <h1>⚡ NanoShell Desktop App</h1>
            \\    <p>Ultra-lightweight WebKit desktop runtime</p>
            \\    <button id="btn">Click Me</button>
            \\  </div>
            \\  <!-- app.js is injected inline by the NanoShell engine at load time -->
            \\</body>
            \\</html>
        ;
        try app_dir.writeFile(io, .{ .sub_path = "app/index.html", .data = html_content });

        const css_content =
            \\body {
            \\  margin: 0;
            \\  font-family: system-ui, -apple-system, sans-serif;
            \\  background: #0f172a;
            \\  color: #f8fafc;
            \\  display: flex;
            \\  justify-content: center;
            \\  align-items: center;
            \\  height: 100vh;
            \\}
            \\.container {
            \\  position: relative;
            \\  text-align: center;
            \\  background: #1e293b;
            \\  padding: 2.5rem;
            \\  border-radius: 1rem;
            \\  box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            \\}
            \\.fps-badge {
            \\  position: absolute;
            \\  top: 1rem;
            \\  right: 1rem;
            \\  font-size: 0.75rem;
            \\  font-weight: bold;
            \\  color: #38bdf8;
            \\  background: rgba(56, 189, 248, 0.1);
            \\  padding: 0.25rem 0.5rem;
            \\  border-radius: 0.25rem;
            \\}
            \\button {
            \\  background: #38bdf8;
            \\  color: #0f172a;
            \\  border: none;
            \\  padding: 0.75rem 1.5rem;
            \\  font-weight: bold;
            \\  border-radius: 0.5rem;
            \\  cursor: pointer;
            \\}
            \\button:hover { background: #7dd3fc; }
        ;
        try app_dir.writeFile(io, .{ .sub_path = "app/styles.css", .data = css_content });

        const js_content =
            \\// NanoShell Application JavaScript (0% Idle CPU Overhead)
            \\console.log('⚡ [NanoShell] App loaded successfully');
            \\
            \\const btn = document.getElementById('btn');
            \\if (btn) {
            \\  btn.addEventListener('click', () => {
            \\    alert('Hello from NanoShell!');
            \\  });
            \\}
        ;
        try app_dir.writeFile(io, .{ .sub_path = "app/app.js", .data = js_content });

        // Copy prebuilt runtime binaries and DLLs into scaffolded project
        const cwd = std.Io.Dir.cwd();
        const exe_dst_path = try std.fmt.allocPrint(allocator, "bin/{s}.exe", .{app_dir_name});
        defer allocator.free(exe_dst_path);

        _ = cwd.copyFile("zig-out/bin/example_app.exe", app_dir, exe_dst_path, io, .{}) catch
            cwd.copyFile("example_app.exe", app_dir, exe_dst_path, io, .{}) catch {};

        _ = cwd.copyFile("zig-out/bin/AppCore.dll", app_dir, "bin/AppCore.dll", io, .{}) catch
            cwd.copyFile("AppCore.dll", app_dir, "bin/AppCore.dll", io, .{}) catch {};

        _ = cwd.copyFile("zig-out/bin/Ultralight.dll", app_dir, "bin/Ultralight.dll", io, .{}) catch
            cwd.copyFile("Ultralight.dll", app_dir, "bin/Ultralight.dll", io, .{}) catch {};

        _ = cwd.copyFile("zig-out/bin/UltralightCore.dll", app_dir, "bin/UltralightCore.dll", io, .{}) catch
            cwd.copyFile("UltralightCore.dll", app_dir, "bin/UltralightCore.dll", io, .{}) catch {};

        _ = cwd.copyFile("zig-out/bin/WebCore.dll", app_dir, "bin/WebCore.dll", io, .{}) catch
            cwd.copyFile("WebCore.dll", app_dir, "bin/WebCore.dll", io, .{}) catch {};

        _ = cwd.copyFile("vendor/bin/vcruntime140.dll", app_dir, "bin/vcruntime140.dll", io, .{}) catch
            cwd.copyFile("zig-out/bin/vcruntime140.dll", app_dir, "bin/vcruntime140.dll", io, .{}) catch {};

        _ = cwd.copyFile("vendor/bin/msvcp140.dll", app_dir, "bin/msvcp140.dll", io, .{}) catch
            cwd.copyFile("zig-out/bin/msvcp140.dll", app_dir, "bin/msvcp140.dll", io, .{}) catch {};

        _ = cwd.copyFile("vendor/bin/vcruntime140_1.dll", app_dir, "bin/vcruntime140_1.dll", io, .{}) catch
            cwd.copyFile("zig-out/bin/vcruntime140_1.dll", app_dir, "bin/vcruntime140_1.dll", io, .{}) catch {};

        _ = cwd.copyFile("vendor/resources/icudt67l.dat", app_dir, "bin/icudt67l.dat", io, .{}) catch
            cwd.copyFile("bin/icudt67l.dat", app_dir, "bin/icudt67l.dat", io, .{}) catch {};

        _ = cwd.copyFile("vendor/resources/cacert.pem", app_dir, "bin/cacert.pem", io, .{}) catch
            cwd.copyFile("bin/cacert.pem", app_dir, "bin/cacert.pem", io, .{}) catch {};

        _ = cwd.copyFile("vendor/resources/icudt67l.dat", app_dir, "bin/resources/icudt67l.dat", io, .{}) catch
            cwd.copyFile("bin/resources/icudt67l.dat", app_dir, "bin/resources/icudt67l.dat", io, .{}) catch {};

        _ = cwd.copyFile("vendor/resources/cacert.pem", app_dir, "bin/resources/cacert.pem", io, .{}) catch
            cwd.copyFile("bin/resources/cacert.pem", app_dir, "bin/resources/cacert.pem", io, .{}) catch {};

        std.log.info("=================================================================", .{});
        std.log.info("  SUCCESS! Scaffolded new NanoShell app: .\\{s}", .{app_dir_name});
        std.log.info("  To get started:", .{});
        std.log.info("    cd {s}", .{app_dir_name});
        std.log.info("    npx nanoshell package", .{});
        std.log.info("=================================================================", .{});
        return;
    }

    var config = installer.loadConfig(allocator) catch installer.AppConfig{};
    defer config.deinit(allocator);

    // Help banner if no command or invalid command is provided
    std.log.info("+===================================================+", .{});
    std.log.info("|  NanoShell CLI  v{s}  . by Suman Biswas         |", .{config.version});
    std.log.info("|  17MB RAM . 120 FPS . WebKit-powered desktop apps  |", .{});
    std.log.info("+===================================================+", .{});
    std.log.info("Usage:", .{});
    std.log.info("  npx nanoshell <my-app>    Scaffold a new NanoShell app", .{});
    std.log.info("  npx nanoshell build        Build production release binary only", .{});
    std.log.info("  npx nanoshell start        Launch the dev engine", .{});
    std.log.info("  npx nanoshell package      Build binary and generate Windows installer", .{});
    std.log.info("nanoshell package:", .{});
    std.log.info("  - Reads nanoshell.json for app name, version, author", .{});
    std.log.info("  - Generates setup.iss (Inno Setup script)", .{});
    std.log.info("  - Auto-compiles to dist\\AppName-Setup.exe if ISCC found", .{});
    std.log.info("  - Installer lets user choose: Admin OR per-user install", .{});
}
