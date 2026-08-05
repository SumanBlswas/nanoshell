const std = @import("std");

// ─── NanoShell Installer Generator ───────────────────────────────────────────
// Reads nanoshell.json, generates a professional Inno Setup .iss script,
// then auto-compiles with ISCC.exe if found.
//
// The generated installer shows a DIALOG letting the user choose:
//   [●] Install for all users  → Program Files  (requires UAC / Admin)
//   [○] Install just for me    → AppData\Local  (no admin needed)
// ─────────────────────────────────────────────────────────────────────────────

pub const AppConfig = struct {
    name: []const u8 = "MyApp",
    version: []const u8 = "1.0.0",
    author: []const u8 = "Unknown",
    description: []const u8 = "A NanoShell desktop application",
    icon: []const u8 = "assets\\icon.ico",
    url: []const u8 = "https://example.com",
    exe_name: []const u8 = "app.exe",
    allocated: bool = false,

    pub fn deinit(self: *AppConfig, allocator: std.mem.Allocator) void {
        const def = AppConfig{};
        if (self.name.ptr != def.name.ptr) allocator.free(self.name);
        if (self.version.ptr != def.version.ptr) allocator.free(self.version);
        if (self.author.ptr != def.author.ptr) allocator.free(self.author);
        if (self.description.ptr != def.description.ptr) allocator.free(self.description);
        if (self.icon.ptr != def.icon.ptr) allocator.free(self.icon);
        if (self.url.ptr != def.url.ptr) allocator.free(self.url);
        if (self.exe_name.ptr != def.exe_name.ptr) allocator.free(self.exe_name);
    }
};

/// Load config from nanoshell.json. Falls back to defaults if missing.
pub fn loadConfig(allocator: std.mem.Allocator) !AppConfig {
    const io = std.Io.Threaded.global_single_threaded.io();
    const content = std.Io.Dir.cwd().readFileAlloc(io, "nanoshell.json", allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            std.log.warn("nanoshell.json not found - using defaults.", .{});
            return AppConfig{};
        }
        return err;
    };
    defer allocator.free(content);

    var config = AppConfig{};
    if (jsonField(allocator, content, "name")) |v| { config.name = v; config.allocated = true; }
    if (jsonField(allocator, content, "version")) |v| { config.version = v; config.allocated = true; }
    if (jsonField(allocator, content, "author")) |v| { config.author = v; config.allocated = true; }
    if (jsonField(allocator, content, "description")) |v| { config.description = v; config.allocated = true; }
    if (jsonField(allocator, content, "icon")) |v| { config.icon = v; config.allocated = true; }
    if (jsonField(allocator, content, "url")) |v| { config.url = v; config.allocated = true; }
    if (jsonField(allocator, content, "exe_name")) |v| { config.exe_name = v; config.allocated = true; }
    return config;
}

fn jsonField(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ?[]const u8 {
    const needle = std.fmt.allocPrint(allocator, "\"{s}\"", .{key}) catch return null;
    defer allocator.free(needle);
    const pos = std.mem.indexOf(u8, json, needle) orelse return null;
    const rest = json[pos + needle.len ..];
    var i: usize = 0;
    while (i < rest.len and (rest[i] == ' ' or rest[i] == ':' or rest[i] == '\t')) : (i += 1) {}
    if (i >= rest.len or rest[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < rest.len and rest[i] != '"') : (i += 1) {}
    if (i >= rest.len) return null;
    return allocator.dupe(u8, rest[start..i]) catch null;
}

extern "kernel32" fn GetEnvironmentVariableW(lpName: [*:0]const u16, lpBuffer: [*]u16, nSize: u32) callconv(.c) u32;

fn getEnvVarDynamic(allocator: std.mem.Allocator, key: []const u8) ?[]const u8 {
    var key_utf16_buf: [256]u16 = undefined;
    const key_len = std.unicode.utf8ToUtf16Le(&key_utf16_buf, key) catch return null;
    key_utf16_buf[key_len] = 0;

    var val_utf16_buf: [1024]u16 = undefined;
    const len = GetEnvironmentVariableW(@ptrCast(&key_utf16_buf), &val_utf16_buf, 1024);
    if (len == 0 or len >= 1024) return null;

    var val_utf8_buf: [1024]u8 = undefined;
    const utf8_len = std.unicode.utf16LeToUtf8(&val_utf8_buf, val_utf16_buf[0..len]) catch return null;
    return allocator.dupe(u8, val_utf8_buf[0..utf8_len]) catch null;
}

/// Search for ISCC.exe dynamically across any user's system (%LocalAppData%, %ProgramFiles%, %ProgramFiles(x86)%)
pub fn findIscc(allocator: std.mem.Allocator) ?[]const u8 {
    const io = std.Io.Threaded.global_single_threaded.io();

    const env_keys = [_][]const u8{ "LOCALAPPDATA", "PROGRAMFILES", "PROGRAMFILES(X86)" };
    const sub_paths = [_][]const u8{
        "\\Programs\\Inno Setup 6\\ISCC.exe",
        "\\Programs\\Inno Setup 5\\ISCC.exe",
        "\\Inno Setup 6\\ISCC.exe",
        "\\Inno Setup 5\\ISCC.exe",
    };

    for (env_keys) |key| {
        if (getEnvVarDynamic(allocator, key)) |base_dir| {
            defer allocator.free(base_dir);
            for (sub_paths) |sub| {
                if (std.fmt.allocPrint(allocator, "{s}{s}", .{ base_dir, sub })) |p| {
                    if (std.Io.Dir.accessAbsolute(io, p, .{})) |_| {
                        return p;
                    } else |_| {
                        allocator.free(p);
                    }
                } else |_| {}
            }
        }
    }

    const fallback_paths = [_][]const u8{
        "C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe",
        "C:\\Program Files\\Inno Setup 6\\ISCC.exe",
        "C:\\Program Files (x86)\\Inno Setup 5\\ISCC.exe",
        "C:\\Program Files\\Inno Setup 5\\ISCC.exe",
    };
    for (fallback_paths) |p| {
        std.Io.Dir.accessAbsolute(io, p, .{}) catch continue;
        return allocator.dupe(u8, p) catch null;
    }

    return null;
}

/// Generate the Inno Setup script.
pub fn generateIss(allocator: std.mem.Allocator, config: AppConfig) ![]const u8 {
    const app_id = try allocator.dupe(u8, config.name);
    defer allocator.free(app_id);
    for (app_id) |*c| if (c.* == ' ') { c.* = '_'; };

    return std.fmt.allocPrint(allocator,
        \\; NanoShell Installer Script - generated by: npx nanoshell package
        \\; App: {s} v{s}  |  Author: {s}
        \\
        \\#define AppName      "{s}"
        \\#define AppVersion   "{s}"
        \\#define AppPublisher "{s}"
        \\#define AppURL       "{s}"
        \\#define AppExeName   "{s}"
        \\
        \\[Setup]
        \\AppId={{{{NS-{s}}}}}
        \\AppName={{#AppName}}
        \\AppVersion={{#AppVersion}}
        \\AppVerName={{#AppName}} {{#AppVersion}}
        \\AppPublisher={{#AppPublisher}}
        \\AppPublisherURL={{#AppURL}}
        \\AppSupportURL={{#AppURL}}
        \\AppUpdatesURL={{#AppURL}}
        \\
        \\; --- Install Scope ------------------------------------------------
        \\; PrivilegesRequired=lowest  means non-admin install by default.
        \\; PrivilegesRequiredOverridesAllowed=dialog  adds a dialog so the
        \\; user can CHOOSE between per-user or system-wide (admin) install.
        \\PrivilegesRequired=lowest
        \\PrivilegesRequiredOverridesAllowed=dialog
        \\
        \\DefaultDirName={{autopf}}\\{{#AppName}}
        \\DefaultGroupName={{#AppName}}
        \\AllowNoIcons=yes
        \\
        \\; --- Output -------------------------------------------------------
        \\OutputDir=dist
        \\OutputBaseFilename={{#AppName}}-Setup
        \\
        \\; --- Compression (lzma2/ultra64 = smallest .exe size) ---------------
        \\Compression=lzma2/ultra64
        \\SolidCompression=yes
        \\LZMAUseSeparateProcess=yes
        \\
        \\; --- Architecture --------------------------------------------------
        \\ArchitecturesInstallIn64BitMode=x64compatible
        \\
        \\; --- Appearance ----------------------------------------------------
        \\WizardStyle=modern
        \\
        \\[Languages]
        \\Name: "english"; MessagesFile: "compiler:Default.isl"
        \\
        \\[Tasks]
        \\Name: "desktopicon"; Description: "{{cm:CreateDesktopIcon}}"; GroupDescription: "{{cm:AdditionalIcons}}"; Flags: unchecked
        \\
        \\[Files]
        \\; Main executable
        \\Source: "bin\{{#AppExeName}}"; DestDir: "{{app}}"; Flags: ignoreversion
        \\
        \\; NanoShell Runtime DLLs & Portable C++ Runtimes
        \\Source: "bin\AppCore.dll";        DestDir: "{{app}}"; Flags: ignoreversion
        \\Source: "bin\Ultralight.dll";     DestDir: "{{app}}"; Flags: ignoreversion
        \\Source: "bin\UltralightCore.dll"; DestDir: "{{app}}"; Flags: ignoreversion
        \\Source: "bin\WebCore.dll";        DestDir: "{{app}}"; Flags: ignoreversion
        \\Source: "bin\vcruntime140.dll";   DestDir: "{{app}}"; Flags: ignoreversion skipifdoesntexist
        \\Source: "bin\msvcp140.dll";       DestDir: "{{app}}"; Flags: ignoreversion skipifdoesntexist
        \\Source: "bin\vcruntime140_1.dll"; DestDir: "{{app}}"; Flags: ignoreversion skipifdoesntexist
        \\
        \\; ICU Unicode data and TLS certs
        \\Source: "bin\icudt67l.dat"; DestDir: "{{app}}"; Flags: ignoreversion
        \\Source: "bin\cacert.pem";   DestDir: "{{app}}"; Flags: ignoreversion
        \\Source: "bin\resources\*";  DestDir: "{{app}}\resources"; Flags: ignoreversion recursesubdirs createallsubdirs
        \\
        \\; App HTML / CSS / JS assets
        \\Source: "app\*"; DestDir: "{{app}}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
        \\
        \\[Icons]
        \\Name: "{{group}}\\{{#AppName}}";                         Filename: "{{app}}\\{{#AppExeName}}"; WorkingDir: "{{app}}"
        \\Name: "{{group}}\\{{cm:UninstallProgram,{{#AppName}}}}"; Filename: "{{uninstallexe}}"
        \\Name: "{{userdesktop}}\\{{#AppName}}"; Filename: "{{app}}\\{{#AppExeName}}"; WorkingDir: "{{app}}"; Tasks: desktopicon
        \\
        \\[Run]
        \\Filename: "{{app}}\\{{#AppExeName}}"; WorkingDir: "{{app}}"; Description: "{{cm:LaunchProgram,{{#StringChange(AppName, '&', '&&')}}}}"; Flags: nowait postinstall skipifsilent
        \\
        \\[UninstallRun]
        \\Filename: "{{app}}\\{{#AppExeName}}"; Parameters: "--uninstall"; Flags: skipifdoesntexist runhidden; RunOnceId: "CleanupApp"
        \\
    , .{
        config.name,
        config.version,
        config.author,
        config.name,
        config.version,
        config.author,
        config.url,
        config.exe_name,
        app_id,
    });
}

/// Main: load config, write .iss, find ISCC, auto-compile.
pub fn run(allocator: std.mem.Allocator) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.log.info("NanoShell Installer Generator v1.0.2", .{});
    std.log.info("Powered by Inno Setup . by Suman Biswas", .{});

    std.log.info("[1/4] Reading nanoshell.json...", .{});
    var config = try loadConfig(allocator);
    defer config.deinit(allocator);
    std.log.info("App: {s} v{s} by {s} ({s})", .{ config.name, config.version, config.author, config.exe_name });

    std.log.info("[2/4] Generating setup.iss...", .{});
    const iss = try generateIss(allocator, config);
    defer allocator.free(iss);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = "setup.iss", .data = iss });
    std.log.info("Written: setup.iss", .{});

    _ = std.Io.Dir.cwd().createDir(io, "dist", .default_dir) catch {};

    std.log.info("[3/4] Searching for Inno Setup (ISCC.exe)...", .{});
    if (findIscc(allocator)) |iscc_path| {
        defer allocator.free(iscc_path);
        std.log.info("Found Inno Setup at: {s}", .{iscc_path});
        std.log.info("[4/4] Compiling setup.iss into dist\\{s}-Setup.exe...", .{config.name});

        // Auto-compile using Windows CreateProcessW API
        const cmd_str = try std.fmt.allocPrint(allocator, "\"{s}\" setup.iss", .{iscc_path});
        defer allocator.free(cmd_str);

        var cmd_utf16: [1024]u16 = undefined;
        const cmd_len = try std.unicode.utf8ToUtf16Le(&cmd_utf16, cmd_str);
        cmd_utf16[cmd_len] = 0;

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

            pub extern "kernel32" fn WaitForSingleObject(hHandle: std.os.windows.HANDLE, dwMilliseconds: u32) callconv(.winapi) u32;
            pub extern "kernel32" fn CloseHandle(hObject: std.os.windows.HANDLE) callconv(.winapi) i32;
            pub extern "kernel32" fn GetExitCodeProcess(hProcess: std.os.windows.HANDLE, lpExitCode: *u32) callconv(.winapi) i32;
        };

        var si = STARTUPINFOW{};
        var pi: PROCESS_INFORMATION = undefined;

        const res = WinApi.CreateProcessW(
            null,
            @ptrCast(&cmd_utf16),
            null,
            null,
            0,
            0,
            null,
            null,
            &si,
            &pi,
        );

        if (res != 0) {
            defer _ = WinApi.CloseHandle(pi.hProcess);
            defer _ = WinApi.CloseHandle(pi.hThread);
            _ = WinApi.WaitForSingleObject(pi.hProcess, 0xFFFFFFFF);

            var exit_code: u32 = 0;
            _ = WinApi.GetExitCodeProcess(pi.hProcess, &exit_code);

            if (exit_code == 0) {
                std.log.info("=================================================================", .{});
                std.log.info("  SUCCESS! Windows Installer Built -> dist\\{s}-Setup.exe", .{config.name});
                std.log.info("=================================================================", .{});
            } else {
                std.log.err("ISCC compilation exited with code {d}.", .{exit_code});
            }
        } else {
            std.log.warn("Could not auto-launch ISCC.exe. Open setup.iss in Inno Setup.", .{});
        }
    } else {
        std.log.info("[4/4] setup.iss generated successfully!", .{});
        std.log.info("  1. Install Inno Setup: https://jrsoftware.org/isdl.php", .{});
        std.log.info("  2. Open setup.iss or run: ISCC setup.iss", .{});
        std.log.info("  3. Output binary will be saved in: dist\\{s}-Setup.exe", .{config.name});
    }
}
