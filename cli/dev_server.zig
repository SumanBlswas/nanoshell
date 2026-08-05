const std = @import("std");
const installer = @import("installer.zig");

pub const DevServer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DevServer {
        return .{ .allocator = allocator };
    }

    pub fn runDevMode(self: *DevServer, app_dir_name: []const u8) !void {
        _ = app_dir_name;
        std.log.info("=================================================================", .{});
        std.log.info("  ⚡ NanoShell Dev Server Started", .{});
        std.log.info("  Watching app/ directory & nanoshell.json for live changes...", .{});
        std.log.info("=================================================================", .{});

        var config = installer.loadConfig(self.allocator) catch installer.AppConfig{};
        defer config.deinit(self.allocator);

        // Find executable inside bin/ or zig-out/bin/
        const io = std.Io.Threaded.global_single_threaded.io();
        const cwd = std.Io.Dir.cwd();

        var found_exe: ?[]const u8 = null;

        const candidate_paths = [_][]const u8{
            "zig-out/bin/example_app.exe",
            "bin/example_app.exe",
            "zig-out/bin/nanoshell.exe",
        };

        for (candidate_paths) |p| {
            if (cwd.openFile(io, p, .{})) |f| {
                f.close(io);
                found_exe = p;
                break;
            } else |_| {}
        }

        if (found_exe == null) {
            // Search bin/ for any .exe
            var bin_dir = cwd.openDir(io, "bin", .{ .iterate = true }) catch null;
            if (bin_dir) |*d| {
                defer d.close(io);
                var iter = d.iterate();
                while (iter.next(io) catch null) |entry| {
                    if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe")) {
                        found_exe = try std.fmt.allocPrint(self.allocator, "bin/{s}", .{entry.name});
                        break;
                    }
                }
            }
        }

        var win_exe_buf: [256]u8 = undefined;
        const exe_to_run = found_exe orelse "bin\\app.exe";
        var pos: usize = 0;
        for (exe_to_run) |ch| {
            if (ch == '/') {
                win_exe_buf[pos] = '\\';
            } else {
                win_exe_buf[pos] = ch;
            }
            pos += 1;
        }
        win_exe_buf[pos] = 0;
        const win_path = win_exe_buf[0..pos];

        var dev_cmd_buf: [300]u8 = undefined;
        const dev_cmd = std.fmt.bufPrintZ(&dev_cmd_buf, "{s} --dev", .{win_path}) catch win_path;

        std.log.info("Launching NanoShell runtime in DEV mode: {s}", .{dev_cmd});

        // Launch app process once - native engine handles smooth in-window hot reload in dev mode
        var child = try self.spawnChildProcess(dev_cmd);
        defer _ = child.kill();

        std.log.info("App running! In-window hot reload active for app/index.html, styles.css, app.js.", .{});

        const WinApi = struct {
            pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
            pub extern "kernel32" fn GetExitCodeProcess(hProcess: std.os.windows.HANDLE, lpExitCode: *u32) callconv(.winapi) i32;
        };

        var exit_code: u32 = 259; // STILL_ACTIVE
        while (exit_code == 259) {
            WinApi.Sleep(500);
            _ = WinApi.GetExitCodeProcess(child.hProcess, &exit_code);
        }
    }

    fn spawnChildProcess(self: *DevServer, exe_path: []const u8) !ChildProcess {
        _ = self;
        var cmd_utf16: [1024]u16 = undefined;
        const len = try std.unicode.utf8ToUtf16Le(&cmd_utf16, exe_path);
        cmd_utf16[len] = 0;

        const STARTUPINFOW = extern struct {
            cb: u32 = 104,
            lpReserved: ?[*:0]u16 = null,
            lpDesktop: ?[*:0]u16 = null,
            lpTitle: ?[*:0]u16 = null,
            dwX: u32 = 0,
            dwY: u32 = 0,
            dwXSize: u32 = 0,
            dwYSize: u32 = 0,
            dwXCountChars: u32 = 0,
            dwYCountChars: u32 = 0,
            dwFillAttribute: u32 = 0,
            dwFlags: u32 = 0,
            wShowWindow: u16 = 0,
            cbReserved2: u16 = 0,
            lpReserved2: ?*u8 = null,
            hStdInput: ?std.os.windows.HANDLE = null,
            hStdOutput: ?std.os.windows.HANDLE = null,
            hStdError: ?std.os.windows.HANDLE = null,
        };

        const PROCESS_INFORMATION = extern struct {
            hProcess: std.os.windows.HANDLE,
            hThread: std.os.windows.HANDLE,
            dwProcessId: u32,
            dwThreadId: u32,
        };

        const WinApi = struct {
            pub extern "kernel32" fn CreateProcessW(
                lpApplicationName: ?[*:0]const u16,
                lpCommandLine: ?[*:0]u16,
                lpProcessAttributes: ?*anyopaque,
                lpThreadAttributes: ?*anyopaque,
                bInheritHandles: i32,
                dwCreationFlags: u32,
                lpEnvironment: ?*anyopaque,
                lpCurrentDirectory: ?[*:0]const u16,
                lpStartupInfo: *const STARTUPINFOW,
                lpProcessInformation: *PROCESS_INFORMATION,
            ) callconv(.winapi) i32;

            pub extern "kernel32" fn TerminateProcess(hProcess: std.os.windows.HANDLE, uExitCode: u32) callconv(.winapi) i32;
            pub extern "kernel32" fn CloseHandle(hObject: std.os.windows.HANDLE) callconv(.winapi) i32;
        };

        var si = STARTUPINFOW{};
        var pi: PROCESS_INFORMATION = undefined;

        const res = WinApi.CreateProcessW(null, @ptrCast(&cmd_utf16), null, null, 0, 0, null, null, &si, &pi);
        if (res == 0) return error.ProcessCreationFailed;

        return ChildProcess{
            .hProcess = pi.hProcess,
            .hThread = pi.hThread,
        };
    }

    fn getAppModTime(self: *DevServer) i128 {
        _ = self;
        const io = std.Io.Threaded.global_single_threaded.io();
        const cwd = std.Io.Dir.cwd();
        var max_mtime: i128 = 0;

        var app_dir = cwd.openDir(io, "app", .{ .iterate = true }) catch return 0;
        defer app_dir.close(io);

        var iter = app_dir.iterate();
        while (iter.next(io) catch null) |entry| {
            if (entry.kind == .file) {
                if (app_dir.statFile(io, entry.name, .{})) |st| {
                    const ns = st.mtime.toNanoseconds();
                    if (ns > max_mtime) max_mtime = ns;
                } else |_| {}
            }
        }
        return max_mtime;
    }
};

pub const ChildProcess = struct {
    hProcess: std.os.windows.HANDLE,
    hThread: std.os.windows.HANDLE,

    pub fn kill(self: *ChildProcess) void {
        const WinApi = struct {
            pub extern "kernel32" fn TerminateProcess(hProcess: std.os.windows.HANDLE, uExitCode: u32) callconv(.winapi) i32;
            pub extern "kernel32" fn CloseHandle(hObject: std.os.windows.HANDLE) callconv(.winapi) i32;
        };
        _ = WinApi.TerminateProcess(self.hProcess, 1);
        _ = WinApi.CloseHandle(self.hProcess);
        _ = WinApi.CloseHandle(self.hThread);
    }
};
