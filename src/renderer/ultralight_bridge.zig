const std = @import("std");
const gpu_mod = @import("gpu.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdint.h");
    @cInclude("stdbool.h");
    @cInclude("windows.h");
    @cInclude("psapi.h");
    @cInclude("Ultralight/CAPI/CAPI_Config.h");
    @cInclude("Ultralight/CAPI/CAPI_Renderer.h");
    @cInclude("Ultralight/CAPI/CAPI_View.h");
    @cInclude("Ultralight/CAPI/CAPI_Surface.h");
    @cInclude("Ultralight/CAPI/CAPI_Bitmap.h");
    @cInclude("Ultralight/CAPI/CAPI_String.h");
    @cInclude("AppCore/CAPI.h");
    @cInclude("JavaScriptCore/JavaScript.h");
});

pub const UltralightConfig = struct {
    font_family_standard: []const u8 = "Segoe UI",
    device_scale: f64 = 1.0,
    enable_gpu: bool = false,
    show_fps: bool = false,
    enable_hot_reload: bool = false,
};

pub const UltralightBridge = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    app: c.ULApp,
    window: c.ULWindow,
    overlay: c.ULOverlay,
    view: c.ULView,
    update_counter: u32 = 0,
    config: UltralightConfig = .{},
    last_app_mtime: i128 = 0,

    fn onResize(user_data: ?*anyopaque, window: c.ULWindow, width: c_uint, height: c_uint) callconv(.c) void {
        _ = window;
        if (user_data) |ud| {
            const overlay: c.ULOverlay = @ptrCast(@alignCast(ud));
            c.ulOverlayResize(overlay, width, height);
        }
    }

    fn onChangeCursor(user_data: ?*anyopaque, caller: c.ULView, cursor: c.ULCursor) callconv(.c) void {
        _ = caller;
        if (user_data) |ud| {
            const window: c.ULWindow = @ptrCast(@alignCast(ud));
            c.ulWindowSetCursor(window, cursor);
        }
    }

    fn onClose(user_data: ?*anyopaque, window: c.ULWindow) callconv(.c) void {
        _ = window;
        if (user_data) |ud| {
            const app: c.ULApp = @ptrCast(@alignCast(ud));
            c.ulAppQuit(app);
        }
    }

    fn onUpdate(user_data: ?*anyopaque) callconv(.c) void {
        if (user_data) |ud| {
            const self: *UltralightBridge = @ptrCast(@alignCast(ud));
            self.update_counter += 1;

            // In-Window Hot Reload Check (Dev mode only): Every 15 ticks (~120ms at 120 FPS)
            if (self.config.enable_hot_reload and self.update_counter % 15 == 0) {
                const io = std.Io.Threaded.global_single_threaded.io();
                const cwd = std.Io.Dir.cwd();
                var max_mtime: i128 = 0;

                // Resolve executable base and parent directory
                var exe_path_buf: [1024]u8 = undefined;
                const raw_len = c.GetModuleFileNameA(null, &exe_path_buf, 1024);
                var base_dir: []const u8 = "";
                var parent_dir: []const u8 = "";
                if (raw_len > 0 and raw_len < 1024) {
                    const exe_full = exe_path_buf[0..raw_len];
                    if (std.mem.lastIndexOfScalar(u8, exe_full, '\\')) |last_slash| {
                        base_dir = exe_full[0 .. last_slash + 1];
                        const base_no_trail = exe_full[0..last_slash];
                        if (std.mem.lastIndexOfScalar(u8, base_no_trail, '\\')) |parent_slash| {
                            parent_dir = exe_full[0 .. parent_slash + 1];
                        }
                    }
                }

                const search_dirs = [_][]const u8{ parent_dir, base_dir, "" };
                for (search_dirs) |sdir| {
                    var full_app_p: [1024]u8 = undefined;
                    const p_str = if (sdir.len > 0)
                        std.fmt.bufPrintZ(&full_app_p, "{s}app", .{sdir}) catch continue
                    else
                        "app";

                    var app_dir = cwd.openDir(io, p_str, .{ .iterate = true }) catch continue;
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
                    if (max_mtime > 0) break;
                }

                if (self.last_app_mtime > 0 and max_mtime > self.last_app_mtime) {
                    std.log.info("⚡ In-Window Hot Reload -> Reloading Web View...", .{});
                    self.loadFile("app/index.html") catch |err| {
                        std.log.err("Failed to reload HTML: {s}", .{@errorName(err)});
                    };
                }
                if (max_mtime > 0) {
                    self.last_app_mtime = max_mtime;
                }
            }

            // Memory Purge: Every 120 ticks (~1.0s at 120 FPS)
            if (self.update_counter >= 120) {
                self.update_counter = 0;
                const renderer = c.ulAppGetRenderer(self.app);
                c.ulPurgeMemory(renderer);
            }
        }
    }

    // Native C JS Callback Handlers for JSObjectMakeFunctionWithCallback
    fn jsNativeSetTitle(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0 and global_bridge_instance != null) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var buf: [512]u8 = undefined;
            const len = c.JSStringGetUTF8CString(str_ref, &buf, 512);
            if (len > 0) {
                c.ulWindowSetTitle(global_bridge_instance.?.window, &buf);
            }
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeMinimize(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            const hwnd: ?c.HWND = @ptrCast(@alignCast(c.ulWindowGetNativeHandle(inst.window)));
            if (hwnd) |h| _ = c.ShowWindow(h, c.SW_MINIMIZE);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeMaximize(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            const hwnd: ?c.HWND = @ptrCast(@alignCast(c.ulWindowGetNativeHandle(inst.window)));
            if (hwnd) |h| _ = c.ShowWindow(h, c.SW_MAXIMIZE);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeClose(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            c.ulWindowClose(inst.window);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeCenter(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            c.ulWindowMoveToCenter(inst.window);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeShowMessage(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        var title_buf: [256]u8 = undefined;
        var msg_buf: [1024]u8 = undefined;
        @memset(&title_buf, 0); @memset(&msg_buf, 0);

        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            _ = c.JSStringGetUTF8CString(str_ref, &title_buf, 256);
        }
        if (argumentCount > 1) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[1], null);
            defer c.JSStringRelease(str_ref);
            _ = c.JSStringGetUTF8CString(str_ref, &msg_buf, 1024);
        }

        const hwnd: c.HWND = if (global_bridge_instance) |inst| @ptrCast(@alignCast(c.ulWindowGetNativeHandle(inst.window))) else null;
        _ = c.MessageBoxA(hwnd, &msg_buf, &title_buf, c.MB_OK | c.MB_ICONINFORMATION);

        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeShowOpen(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        var sz_file: [260]u8 = undefined;
        @memset(&sz_file, 0);

        var ofn: c.OPENFILENAMEA = std.mem.zeroes(c.OPENFILENAMEA);
        ofn.lStructSize = @sizeOf(c.OPENFILENAMEA);
        ofn.hwndOwner = if (global_bridge_instance) |inst| @ptrCast(@alignCast(c.ulWindowGetNativeHandle(inst.window))) else null;
        ofn.lpstrFile = &sz_file;
        ofn.nMaxFile = 260;
        ofn.lpstrFilter = "All Files (*.*)\x00*.*\x00Text Files (*.txt)\x00*.txt\x00\x00";
        ofn.nFilterIndex = 1;
        ofn.Flags = c.OFN_PATHMUSTEXIST | c.OFN_FILEMUSTEXIST;

        if (c.GetOpenFileNameA(&ofn) != 0) {
            const str_ref = c.JSStringCreateWithUTF8CString(&sz_file);
            defer c.JSStringRelease(str_ref);
            return c.JSValueMakeString(ctx, str_ref);
        }

        return c.JSValueMakeNull(ctx);
    }

    pub var global_bridge_instance: ?*UltralightBridge = null;

    fn onWindowObjectReady(user_data: ?*anyopaque, view: c.ULView, frame_id: u64, is_main_frame: bool, url: c.ULString) callconv(.c) void {
        _ = frame_id;
        _ = is_main_frame;
        _ = url;
        const ctx = c.ulViewLockJSContext(view);
        defer c.ulViewUnlockJSContext(view);

        const global_obj = c.JSContextGetGlobalObject(ctx);

        const name_ns = c.JSStringCreateWithUTF8CString("NanoShell");
        defer c.JSStringRelease(name_ns);
        const name_zero_ui = c.JSStringCreateWithUTF8CString("ZeroUI");
        defer c.JSStringRelease(name_zero_ui);

        const ns_obj = c.JSObjectMake(ctx, null, null);
        const window_obj = c.JSObjectMake(ctx, null, null);
        const dialog_obj = c.JSObjectMake(ctx, null, null);

        // Bind Window Native Functions
        const fn_title = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeSetTitle);
        const fn_min = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeMinimize);
        const fn_max = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeMaximize);
        const fn_close = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeClose);
        const fn_center = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeCenter);

        const str_title = c.JSStringCreateWithUTF8CString("setTitle"); defer c.JSStringRelease(str_title);
        const str_min = c.JSStringCreateWithUTF8CString("minimize"); defer c.JSStringRelease(str_min);
        const str_max = c.JSStringCreateWithUTF8CString("maximize"); defer c.JSStringRelease(str_max);
        const str_close = c.JSStringCreateWithUTF8CString("close"); defer c.JSStringRelease(str_close);
        const str_center = c.JSStringCreateWithUTF8CString("center"); defer c.JSStringRelease(str_center);

        c.JSObjectSetProperty(ctx, window_obj, str_title, fn_title, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, window_obj, str_min, fn_min, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, window_obj, str_max, fn_max, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, window_obj, str_close, fn_close, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, window_obj, str_center, fn_center, c.kJSPropertyAttributeNone, null);

        // Bind Dialog Native Functions
        const fn_msg = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShowMessage);
        const fn_open = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShowOpen);

        const str_msg = c.JSStringCreateWithUTF8CString("showMessage"); defer c.JSStringRelease(str_msg);
        const str_msg_box = c.JSStringCreateWithUTF8CString("showMessageBox"); defer c.JSStringRelease(str_msg_box);
        const str_open = c.JSStringCreateWithUTF8CString("showOpen"); defer c.JSStringRelease(str_open);

        c.JSObjectSetProperty(ctx, dialog_obj, str_msg, fn_msg, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, dialog_obj, str_msg_box, fn_msg, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, dialog_obj, str_open, fn_open, c.kJSPropertyAttributeNone, null);

        // Attach Sub-Objects to NanoShell Global
        const str_win_prop = c.JSStringCreateWithUTF8CString("window"); defer c.JSStringRelease(str_win_prop);
        const str_dlg_prop = c.JSStringCreateWithUTF8CString("dialog"); defer c.JSStringRelease(str_dlg_prop);

        c.JSObjectSetProperty(ctx, ns_obj, str_win_prop, window_obj, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_dlg_prop, dialog_obj, c.kJSPropertyAttributeNone, null);

        c.JSObjectSetProperty(ctx, global_obj, name_ns, ns_obj, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, global_obj, name_zero_ui, ns_obj, c.kJSPropertyAttributeNone, null);
        std.log.info("⚡ Live JS Native Binding Injected into Window!", .{});

        // Automatically inject real-time floating FPS Debugger HUD if show_fps is true
        if (user_data) |ud| {
            const self: *UltralightBridge = @ptrCast(@alignCast(ud));
            if (self.config.show_fps) {
                const fps_js_code =
                    \\(function() {
                    \\  if (document.getElementById('nanoshell-fps-hud')) return;
                    \\  var hud = document.createElement('div');
                    \\  hud.id = 'nanoshell-fps-hud';
                    \\  hud.style.position = 'fixed';
                    \\  hud.style.top = '12px';
                    \\  hud.style.right = '12px';
                    \\  hud.style.zIndex = '999999';
                    \\  hud.style.background = 'rgba(15, 23, 42, 0.85)';
                    \\  hud.style.backdropFilter = 'blur(8px)';
                    \\  hud.style.color = '#38bdf8';
                    \\  hud.style.border = '1px solid rgba(56, 189, 248, 0.3)';
                    \\  hud.style.padding = '6px 12px';
                    \\  hud.style.borderRadius = '20px';
                    \\  hud.style.fontFamily = 'monospace, sans-serif';
                    \\  hud.style.fontSize = '12px';
                    \\  hud.style.fontWeight = 'bold';
                    \\  hud.style.pointerEvents = 'none';
                    \\  hud.style.boxShadow = '0 4px 12px rgba(0,0,0,0.4)';
                    \\  hud.innerHTML = '⚡ FPS: <span id="nanoshell-fps-val">--</span>';
                    \\  document.body.appendChild(hud);
                    \\
                    \\  var lastTime = performance.now();
                    \\  var frames = 0;
                    \\  function updateFpsHud() {
                    \\    var now = performance.now();
                    \\    frames++;
                    \\    var delta = now - lastTime;
                    \\    if (delta >= 500) {
                    \\      var fps = Math.round((frames * 1000) / delta);
                    \\      var valEl = document.getElementById('nanoshell-fps-val');
                    \\      if (valEl) valEl.innerText = fps;
                    \\      frames = 0;
                    \\      lastTime = now;
                    \\    }
                    \\    requestAnimationFrame(updateFpsHud);
                    \\  }
                    \\  requestAnimationFrame(updateFpsHud);
                    \\})();
                ;
                const script_str = c.ulCreateStringUTF8(fps_js_code.ptr, fps_js_code.len);
                defer c.ulDestroyString(script_str);
                _ = c.ulViewEvaluateScript(view, script_str, null);
                std.log.info("⚡ Real-Time Floating FPS Debugger HUD Injected into Window!", .{});
            }
        }
    }

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, cfg: UltralightConfig) !*UltralightBridge {
        // Resolve absolute directory of current executable (e.g. C:\Program Files\MyApp\)
        var exe_path_buf: [1024]u8 = undefined;
        const raw_len = c.GetModuleFileNameA(null, &exe_path_buf, 1024);
        var base_dir_str: []const u8 = "./";
        if (raw_len > 0 and raw_len < 1024) {
            const exe_full = exe_path_buf[0..raw_len];
            if (std.mem.lastIndexOfScalar(u8, exe_full, '\\')) |last_slash| {
                base_dir_str = exe_full[0 .. last_slash + 1];
            }
        }

        var base_dir_c_buf: [1024]u8 = undefined;
        const base_dir_c = std.fmt.bufPrintZ(&base_dir_c_buf, "{s}", .{base_dir_str}) catch "./";

        const base_dir = c.ulCreateString(base_dir_c.ptr);
        defer c.ulDestroyString(base_dir);

        var log_path_buf: [1024]u8 = undefined;
        const log_path = std.fmt.bufPrintZ(&log_path_buf, "{s}ultralight.log", .{base_dir_str}) catch "ultralight.log";
        const log_path_str = c.ulCreateString(log_path.ptr);
        defer c.ulDestroyString(log_path_str);

        c.ulEnableDefaultLogger(log_path_str);
        c.ulEnablePlatformFileSystem(base_dir);
        c.ulEnablePlatformFontLoader();

        // Ultra-low memory configuration for JavaScriptCore & WebKit
        const ul_cfg = c.ulCreateConfig();
        defer c.ulDestroyConfig(ul_cfg);

        c.ulConfigSetMemoryCacheSize(ul_cfg, 16 * 1024 * 1024);
        c.ulConfigSetMinLargeHeapSize(ul_cfg, 16 * 1024 * 1024);
        c.ulConfigSetMinSmallHeapSize(ul_cfg, 4 * 1024 * 1024);
        c.ulConfigSetOverrideRAMSize(ul_cfg, 128 * 1024 * 1024); // 128MB Virtual RAM target
        c.ulConfigSetRecycleDelay(ul_cfg, 0.2); // 0.2-second aggressive memory recycler

        const app_settings = c.ulCreateSettings();
        defer c.ulDestroySettings(app_settings);

        c.ulSettingsSetForceCPURenderer(app_settings, !cfg.enable_gpu);

        const app = c.ulCreateApp(app_settings, ul_cfg);
        if (app == null) {
            return error.AppCreationFailed;
        }

        const monitor = c.ulAppGetMainMonitor(app);
        if (monitor == null) {
            c.ulDestroyApp(app);
            return error.MainMonitorUnavailable;
        }
        const scale = c.ulMonitorGetScale(monitor);

        const window_flags = c.kWindowFlags_Titled | c.kWindowFlags_Resizable | c.kWindowFlags_Maximizable;
        const window = c.ulCreateWindow(monitor, width, height, false, window_flags);
        if (window == null) {
            c.ulDestroyApp(app);
            return error.WindowCreationFailed;
        }

        c.ulWindowSetTitle(window, "ZeroUI Cyber System Control Center (100% Chrome Engine)");
        c.ulWindowMoveToCenter(window);
        c.ulWindowShow(window);

        const real_w = c.ulWindowGetWidth(window);
        const real_h = c.ulWindowGetHeight(window);

        const overlay = c.ulCreateOverlay(window, real_w, real_h, 0, 0);
        if (overlay == null) {
            c.ulDestroyWindow(window);
            c.ulDestroyApp(app);
            return error.OverlayCreationFailed;
        }
        const view = c.ulOverlayGetView(overlay);
        if (view == null) {
            c.ulDestroyOverlay(overlay);
            c.ulDestroyWindow(window);
            c.ulDestroyApp(app);
            return error.ViewCreationFailed;
        }

        c.ulViewSetDeviceScale(view, scale);
        c.ulOverlayShow(overlay);
        c.ulOverlayFocus(overlay);

        c.ulWindowSetResizeCallback(window, onResize, @ptrCast(overlay));
        c.ulWindowSetCloseCallback(window, onClose, @ptrCast(app));

        const self = try allocator.create(UltralightBridge);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .width = real_w,
            .height = real_h,
            .app = app,
            .window = window,
            .overlay = overlay,
            .view = view,
            .update_counter = 0,
            .config = cfg,
            .last_app_mtime = 0,
        };

        c.ulAppSetUpdateCallback(app, onUpdate, @ptrCast(self));
        c.ulViewSetWindowObjectReadyCallback(view, onWindowObjectReady, @ptrCast(self));
        c.ulViewSetChangeCursorCallback(view, onChangeCursor, @ptrCast(window));

        global_bridge_instance = self;

        return self;
    }

    fn readFileBytes(allocator: std.mem.Allocator, file_path_c: [*:0]const u8) ![]u8 {
        const f = c.fopen(file_path_c, "rb");
        if (f == null) return error.FileNotFound;
        defer _ = c.fclose(f);

        _ = c.fseek(f, 0, c.SEEK_END);
        const size_long = c.ftell(f);
        if (size_long <= 0) return error.EmptyFile;
        const size: usize = @intCast(size_long);
        _ = c.fseek(f, 0, c.SEEK_SET);

        const buf = try allocator.alloc(u8, size);
        errdefer allocator.free(buf);

        const bytes_read = c.fread(buf.ptr, 1, size, f);
        if (bytes_read == 0) return error.ReadError;

        return buf[0..bytes_read];
    }

    // ZeroUI Core Engine - Precise Dynamic CSS Gap Transformer
    fn processCSSDynamically(allocator: std.mem.Allocator, raw_css: []const u8) ![]u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        try list.appendSlice(allocator, raw_css);
        try list.appendSlice(allocator, "\n\n/* ZeroUI Native Engine - Dynamic Flex Gap Polyfill */\n");

        var block_iter = std.mem.splitSequence(u8, raw_css, "{");
        var prev_selector: ?[]const u8 = null;

        while (block_iter.next()) |chunk| {
            if (prev_selector) |selector_raw| {
                if (std.mem.indexOfScalar(u8, chunk, '}')) |close_idx| {
                    const block_body = chunk[0..close_idx];
                    const trimmed_selector = std.mem.trim(u8, selector_raw, " \t\r\n");

                    const is_grid = std.mem.indexOf(u8, block_body, "display: grid") != null or
                        std.mem.indexOf(u8, block_body, "display:grid") != null;

                    if (!is_grid) {
                        if (std.mem.indexOf(u8, block_body, "gap:")) |gap_idx| {
                            const after_gap = block_body[gap_idx + 4 ..];
                            if (std.mem.indexOfScalar(u8, after_gap, ';')) |semi_idx| {
                                const gap_val = std.mem.trim(u8, after_gap[0..semi_idx], " \t\r\n");
                                const is_column = std.mem.indexOf(u8, block_body, "flex-direction: column") != null or
                                    std.mem.indexOf(u8, block_body, "flex-direction:column") != null or
                                    std.mem.eql(u8, trimmed_selector, ".content-area");

                                const prop_name = if (is_column) "margin-bottom" else "margin-right";

                                const generated_rule = try std.fmt.allocPrint(
                                    allocator,
                                    "{s} > * {{ {s}: {s}; }}\n{s} > *:last-child {{ {s}: 0; }}\n",
                                    .{ trimmed_selector, prop_name, gap_val, trimmed_selector, prop_name },
                                );
                                defer allocator.free(generated_rule);

                                try list.appendSlice(allocator, generated_rule);
                            }
                        }
                    }

                    if (close_idx + 1 < chunk.len) {
                        prev_selector = chunk[close_idx + 1 ..];
                    } else {
                        prev_selector = null;
                    }
                } else {
                    prev_selector = null;
                }
            } else {
                prev_selector = chunk;
            }
        }

        return list.toOwnedSlice(allocator);
    }

    pub fn loadFile(self: *UltralightBridge, html_path: []const u8) !void {
        _ = html_path;

        // Resolve absolute executable directory
        var exe_path_buf: [1024]u8 = undefined;
        const raw_len = c.GetModuleFileNameA(null, &exe_path_buf, 1024);
        var base_dir: []const u8 = "";
        var parent_dir: []const u8 = "";
        if (raw_len > 0 and raw_len < 1024) {
            const exe_full = exe_path_buf[0..raw_len];
            if (std.mem.lastIndexOfScalar(u8, exe_full, '\\')) |last_slash| {
                base_dir = exe_full[0 .. last_slash + 1];
                // Also resolve parent directory (one level up from bin/)
                const base_no_trail = exe_full[0..last_slash];
                if (std.mem.lastIndexOfScalar(u8, base_no_trail, '\\')) |parent_slash| {
                    parent_dir = exe_full[0 .. parent_slash + 1];
                }
            }
        }

        // Try reading index.html - search both exe dir and parent dir (project root)
        const html_sub_paths = [_][]const u8{
            "app/index.html",
            "app\\index.html",
            "assets/index.html",
            "assets\\index.html",
            "index.html",
        };

        var html_bytes_opt: ?[]u8 = null;
        // Search in base_dir (exe location) first, then parent_dir (project root)
        const search_dirs = [_][]const u8{ base_dir, parent_dir };
        outer: for (search_dirs) |search_dir| {
            if (search_dir.len == 0) continue;
            for (html_sub_paths) |sub| {
                var full_p_buf: [1024]u8 = undefined;
                if (std.fmt.bufPrintZ(&full_p_buf, "{s}{s}", .{ search_dir, sub })) |abs_path| {
                    if (readFileBytes(self.allocator, abs_path.ptr)) |bytes| {
                        html_bytes_opt = bytes;
                        // Update base_dir to wherever we found the html so CSS is found too
                        base_dir = search_dir;
                        break :outer;
                    } else |_| {}
                } else |_| {}
            }
        }

        const html_bytes = html_bytes_opt orelse {
            std.log.err("UltralightBridge: Failed to locate index.html in base '{s}'", .{base_dir});
            return;
        };
        defer self.allocator.free(html_bytes);

        // Try reading styles.css - search base_dir (already resolved to wherever html was found)
        const css_sub_paths = [_][]const u8{
            "app/styles.css",
            "app\\styles.css",
            "assets/styles.css",
            "assets\\styles.css",
            "styles.css",
        };
        var css_bytes_raw: ?[]u8 = null;
        for (css_sub_paths) |sub| {
            var full_p_buf: [1024]u8 = undefined;
            if (std.fmt.bufPrintZ(&full_p_buf, "{s}{s}", .{ base_dir, sub })) |abs_path| {
                if (readFileBytes(self.allocator, abs_path.ptr)) |bytes| {
                    css_bytes_raw = bytes;
                    break;
                } else |_| {}
            } else |_| {}
        }
        defer if (css_bytes_raw) |cb| self.allocator.free(cb);

        const css_bytes = if (css_bytes_raw) |cb| try processCSSDynamically(self.allocator, cb) else null;
        defer if (css_bytes) |cb| self.allocator.free(cb);

        // 3. Inject pre-parsed CSS dynamically into HTML document
        const total_len = html_bytes.len + (if (css_bytes) |cb| cb.len + 30 else 30);
        const full_html = try self.allocator.alloc(u8, total_len);
        defer self.allocator.free(full_html);

        const head_tag = "</head>";
        if (std.mem.indexOf(u8, html_bytes, head_tag)) |idx| {
            const p1 = html_bytes[0..idx];
            const style_prefix = "<style>\n";
            const style_suffix = "\n</style>\n";
            const p2 = html_bytes[idx..];

            var pos: usize = 0;
            @memcpy(full_html[pos..pos + p1.len], p1); pos += p1.len;
            @memcpy(full_html[pos..pos + style_prefix.len], style_prefix); pos += style_prefix.len;
            if (css_bytes) |cb| {
                @memcpy(full_html[pos..pos + cb.len], cb); pos += cb.len;
            }
            @memcpy(full_html[pos..pos + style_suffix.len], style_suffix); pos += style_suffix.len;
            @memcpy(full_html[pos..pos + p2.len], p2); pos += p2.len;

            const html_str = c.ulCreateStringUTF8(full_html.ptr, pos);
            defer c.ulDestroyString(html_str);

            c.ulViewLoadHTML(self.view, html_str);

            const renderer = c.ulAppGetRenderer(self.app);
            c.ulPurgeMemory(renderer);

            std.log.info("UltralightBridge: Continuous RAM Trimming Active ({d} bytes)!", .{pos});
            return;
        }

        const html_str = c.ulCreateStringUTF8(html_bytes.ptr, html_bytes.len);
        defer c.ulDestroyString(html_str);

        c.ulViewLoadHTML(self.view, html_str);

        const renderer = c.ulAppGetRenderer(self.app);
        c.ulPurgeMemory(renderer);

        std.log.info("UltralightBridge: Continuous RAM Trimming Active ({d} bytes)!", .{html_bytes.len});
    }

    pub fn run(self: *UltralightBridge) void {
        c.ulAppRun(self.app);
    }

    pub fn deinit(self: *UltralightBridge) void {
        c.ulDestroyOverlay(self.overlay);
        c.ulDestroyWindow(self.window);
        c.ulDestroyApp(self.app);
        self.allocator.destroy(self);
    }
};
