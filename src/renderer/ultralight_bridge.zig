const std = @import("std");
const gpu_mod = @import("gpu.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdint.h");
    @cInclude("stdbool.h");
    @cInclude("windows.h");
    @cInclude("dwmapi.h");
    @cInclude("psapi.h");
    @cInclude("tlhelp32.h");
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
    dpi_scale: f64,       // live DPI scale factor (dpi / 96.0), updated on WM_DPICHANGED
    logical_w: u32,       // desired logical width  (e.g. 1280) — never changes
    logical_h: u32,       // desired logical height (e.g. 720)  — never changes
    renderer: c.ULRenderer,
    view: c.ULView,
    hwnd: c.HWND,
    update_counter: u32 = 0,
    config: UltralightConfig = .{},
    last_app_mtime: i128 = 0,
    is_running: bool = true,

    fn getXFromLParam(lparam: c.LPARAM) i32 {
        const raw: u16 = @truncate(@as(usize, @bitCast(lparam)));
        return @as(i16, @bitCast(raw));
    }

    fn getYFromLParam(lparam: c.LPARAM) i32 {
        const raw: u16 = @truncate(@as(usize, @bitCast(lparam)) >> 16);
        return @as(i16, @bitCast(raw));
    }

    /// Convert a physical-pixel mouse coordinate (from Windows) to a logical CSS pixel
    /// coordinate (expected by WebKit). Formula: logical = physical / dpi_scale.
    /// On 100% DPI dpi_scale=1.0 so this is a no-op.
    /// On 150% DPI dpi_scale=1.5: physical 960 → logical 640. Pixel-perfect hit testing.
    fn toLogical(physical: i32, dpi_scale: f64) i32 {
        return @intFromFloat(@round(@as(f64, @floatFromInt(physical)) / dpi_scale));
    }

    fn getWheelDelta(wparam: c.WPARAM) i32 {
        const raw: u16 = @truncate(@as(usize, @bitCast(wparam)) >> 16);
        return @as(i16, @bitCast(raw));
    }

    fn wndProc(hwnd: c.HWND, msg: c.UINT, wparam: c.WPARAM, lparam: c.LPARAM) callconv(.winapi) c.LRESULT {
        const raw_ptr = c.GetWindowLongPtrA(hwnd, c.GWLP_USERDATA);
        if (raw_ptr != 0) {
            const self: *UltralightBridge = @ptrFromInt(@as(usize, @intCast(raw_ptr)));
            switch (msg) {
                c.WM_DESTROY => {
                    self.is_running = false;
                    c.PostQuitMessage(0);
                    return 0;
                },
                c.WM_CLOSE => {
                    self.is_running = false;
                    _ = c.DestroyWindow(hwnd);
                    return 0;
                },
                c.WM_SIZE => {
                    const w: u32 = @as(u16, @truncate(@as(usize, @bitCast(lparam))));
                    const h: u32 = @as(u16, @truncate(@as(usize, @bitCast(lparam)) >> 16));
                    if (w >= 10 and h >= 10 and wparam != c.SIZE_MINIMIZED) {
                        self.width = w;
                        self.height = h;
                        c.ulViewResize(self.view, w, h);
                    }
                    return 0;
                },
                // WM_DPICHANGED fires when window moves to a different monitor DPI
                // lparam = pointer to RECT with the suggested new window position/size
                // wparam high = new Y DPI, wparam low = new X DPI (always equal on modern Windows)
                0x02E0 => { // WM_DPICHANGED
                    const new_dpi: u32 = @as(u16, @truncate(wparam));
                    self.dpi_scale = @as(f64, @floatFromInt(new_dpi)) / 96.0;

                    // Windows gives us the pre-calculated correct rect — always use it
                    const suggested: *const c.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
                    _ = c.SetWindowPos(
                        hwnd,
                        null,
                        suggested.left,
                        suggested.top,
                        suggested.right  - suggested.left,
                        suggested.bottom - suggested.top,
                        c.SWP_NOZORDER | c.SWP_NOACTIVATE,
                    );
                    // GetClientRect after resize gives the new physical client size
                    var rc: c.RECT = undefined;
                    _ = c.GetClientRect(hwnd, &rc);
                    const new_w: u32 = @intCast(@max(10, rc.right  - rc.left));
                    const new_h: u32 = @intCast(@max(10, rc.bottom - rc.top));
                    self.width  = new_w;
                    self.height = new_h;
                    c.ulViewResize(self.view, new_w, new_h);
                    _ = c.InvalidateRect(hwnd, null, c.FALSE);
                    std.log.info("WM_DPICHANGED: dpi={d} scale={d:.2} physical={}x{}", .{ new_dpi, self.dpi_scale, new_w, new_h });
                    return 0;
                },
                c.WM_ERASEBKGND => return 1,
                c.WM_PAINT => {
                    var ps: c.PAINTSTRUCT = undefined;
                    const hdc = c.BeginPaint(hwnd, &ps);
                    if (hdc != null) {
                        c.ulRender(self.renderer);
                        self.paintToHDC(hdc);
                    }
                    _ = c.EndPaint(hwnd, &ps);
                    return 0;
                },
                c.WM_SETFOCUS => {
                    c.ulViewFocus(self.view);
                    return 0;
                },
                c.WM_KILLFOCUS => {
                    c.ulViewUnfocus(self.view);
                    return 0;
                },
                c.WM_MOUSEMOVE => {
                    const lx = toLogical(getXFromLParam(lparam), self.dpi_scale);
                    const ly = toLogical(getYFromLParam(lparam), self.dpi_scale);
                    const evt = c.ulCreateMouseEvent(c.kMouseEventType_MouseMoved, lx, ly, c.kMouseButton_None);
                    c.ulViewFireMouseEvent(self.view, evt);
                    c.ulDestroyMouseEvent(evt);
                    return 0;
                },
                c.WM_LBUTTONDOWN => {
                    _ = c.SetCapture(hwnd);
                    _ = c.SetFocus(hwnd);
                    c.ulViewFocus(self.view);
                    const lx = toLogical(getXFromLParam(lparam), self.dpi_scale);
                    const ly = toLogical(getYFromLParam(lparam), self.dpi_scale);
                    const evt = c.ulCreateMouseEvent(c.kMouseEventType_MouseDown, lx, ly, c.kMouseButton_Left);
                    c.ulViewFireMouseEvent(self.view, evt);
                    c.ulDestroyMouseEvent(evt);
                    return 0;
                },
                c.WM_LBUTTONUP => {
                    _ = c.ReleaseCapture();
                    const lx = toLogical(getXFromLParam(lparam), self.dpi_scale);
                    const ly = toLogical(getYFromLParam(lparam), self.dpi_scale);
                    const evt = c.ulCreateMouseEvent(c.kMouseEventType_MouseUp, lx, ly, c.kMouseButton_Left);
                    c.ulViewFireMouseEvent(self.view, evt);
                    c.ulDestroyMouseEvent(evt);
                    return 0;
                },
                c.WM_RBUTTONDOWN => {
                    const lx = toLogical(getXFromLParam(lparam), self.dpi_scale);
                    const ly = toLogical(getYFromLParam(lparam), self.dpi_scale);
                    const evt = c.ulCreateMouseEvent(c.kMouseEventType_MouseDown, lx, ly, c.kMouseButton_Right);
                    c.ulViewFireMouseEvent(self.view, evt);
                    c.ulDestroyMouseEvent(evt);
                    return 0;
                },
                c.WM_RBUTTONUP => {
                    const lx = toLogical(getXFromLParam(lparam), self.dpi_scale);
                    const ly = toLogical(getYFromLParam(lparam), self.dpi_scale);
                    const evt = c.ulCreateMouseEvent(c.kMouseEventType_MouseUp, lx, ly, c.kMouseButton_Right);
                    c.ulViewFireMouseEvent(self.view, evt);
                    c.ulDestroyMouseEvent(evt);
                    return 0;
                },
                c.WM_MOUSEWHEEL => {
                    const delta = getWheelDelta(wparam);
                    const evt = c.ulCreateScrollEvent(c.kScrollEventType_ScrollByPixel, 0, delta);
                    c.ulViewFireScrollEvent(self.view, evt);
                    c.ulDestroyScrollEvent(evt);
                    return 0;
                },
                c.WM_KEYDOWN => {
                    const evt = c.ulCreateKeyEventWindows(c.kKeyEventType_RawKeyDown, wparam, lparam, false);
                    c.ulViewFireKeyEvent(self.view, evt);
                    c.ulDestroyKeyEvent(evt);
                    return 0;
                },
                c.WM_KEYUP => {
                    const evt = c.ulCreateKeyEventWindows(c.kKeyEventType_KeyUp, wparam, lparam, false);
                    c.ulViewFireKeyEvent(self.view, evt);
                    c.ulDestroyKeyEvent(evt);
                    return 0;
                },
                c.WM_CHAR => {
                    const evt = c.ulCreateKeyEventWindows(c.kKeyEventType_Char, wparam, lparam, false);
                    c.ulViewFireKeyEvent(self.view, evt);
                    c.ulDestroyKeyEvent(evt);
                    return 0;
                },
                else => {},
            }
        }
        return c.DefWindowProcA(hwnd, msg, wparam, lparam);
    }

    fn onChangeCursor(user_data: ?*anyopaque, caller: c.ULView, cursor: c.ULCursor) callconv(.c) void {
        _ = caller;
        _ = user_data;
        var win_cursor: ?c.HCURSOR = null;
        switch (cursor) {
            c.kCursor_Hand => win_cursor = c.LoadCursorA(null, @ptrFromInt(32649)),
            c.kCursor_IBeam => win_cursor = c.LoadCursorA(null, @ptrFromInt(32513)),
            c.kCursor_Cross => win_cursor = c.LoadCursorA(null, @ptrFromInt(32515)),
            else => win_cursor = c.LoadCursorA(null, @ptrFromInt(32512)),
        }
        if (win_cursor) |cur| {
            _ = c.SetCursor(cur);
        }
    }

    fn paintToHDC(self: *UltralightBridge, hdc: c.HDC) void {
        const surface = c.ulViewGetSurface(self.view);
        if (surface == null) return;
        const pixels = c.ulSurfaceLockPixels(surface);
        if (pixels == null) return;
        defer c.ulSurfaceUnlockPixels(surface);

        const w = c.ulSurfaceGetWidth(surface);
        const h = c.ulSurfaceGetHeight(surface);
        if (w == 0 or h == 0) return;

        var rc: c.RECT = undefined;
        _ = c.GetClientRect(self.hwnd, &rc);
        const client_w = rc.right - rc.left;
        const client_h = rc.bottom - rc.top;
        if (client_w <= 0 or client_h <= 0) return;

        var bmi = std.mem.zeroes(c.BITMAPINFO);
        bmi.bmiHeader.biSize = @sizeOf(c.BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = @intCast(w);
        bmi.bmiHeader.biHeight = -@as(i32, @intCast(h));
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = c.BI_RGB;

        _ = c.SetStretchBltMode(hdc, 4); // HALFTONE
        _ = c.SetBrushOrgEx(hdc, 0, 0, null);

        _ = c.StretchDIBits(
            hdc,
            0,
            0,
            client_w,
            client_h,
            0,
            0,
            @intCast(w),
            @intCast(h),
            pixels,
            &bmi,
            c.DIB_RGB_COLORS,
            c.SRCCOPY,
        );
    }

    fn tickUpdate(self: *UltralightBridge) void {
        self.update_counter += 1;

        // In-Window Hot Reload Check (Dev mode only): Every 15 ticks (~120ms at 120 FPS)
        if (self.config.enable_hot_reload and self.update_counter % 15 == 0) {
            const io = std.Io.Threaded.global_single_threaded.io();
            const cwd = std.Io.Dir.cwd();
            var max_mtime: i128 = 0;

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

            if (self.last_app_mtime > 0 and max_mtime > self.last_app_mtime and (max_mtime - self.last_app_mtime) > 500_000_000) {
                std.log.info("⚡ In-Window Hot Reload -> Reloading Web View...", .{});
                self.loadFile("app/index.html") catch |err| {
                    std.log.err("Failed to reload HTML: {s}", .{@errorName(err)});
                };
                self.last_app_mtime = max_mtime;
            } else if (self.last_app_mtime == 0 and max_mtime > 0) {
                self.last_app_mtime = max_mtime;
            }
        }

        // Memory Purge: Every 120 ticks (~1.0s at 120 FPS)
        if (self.update_counter >= 120) {
            self.update_counter = 0;
            c.ulPurgeMemory(self.renderer);
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
                _ = c.SetWindowTextA(global_bridge_instance.?.hwnd, &buf);
            }
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeMinimize(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            _ = c.ShowWindow(inst.hwnd, c.SW_MINIMIZE);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeMaximize(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            _ = c.ShowWindow(inst.hwnd, c.SW_MAXIMIZE);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeRestore(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            _ = c.ShowWindow(inst.hwnd, c.SW_RESTORE);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeClose(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            inst.is_running = false;
            _ = c.PostMessageA(inst.hwnd, c.WM_CLOSE, 0, 0);
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeCenter(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (global_bridge_instance) |inst| {
            const screen_w = c.GetSystemMetrics(0);
            const screen_h = c.GetSystemMetrics(1);
            const pos_x = @divTrunc(screen_w - @as(i32, @intCast(inst.width)), 2);
            const pos_y = @divTrunc(screen_h - @as(i32, @intCast(inst.height)), 2);
            _ = c.SetWindowPos(inst.hwnd, null, pos_x, pos_y, 0, 0, c.SWP_NOSIZE | c.SWP_NOZORDER);
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

        const hwnd: c.HWND = if (global_bridge_instance) |inst| inst.hwnd else null;
        _ = c.MessageBoxA(hwnd, &msg_buf, &title_buf, c.MB_OK | c.MB_ICONINFORMATION);

        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeShowOpen(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        var sz_file: [260]u8 = undefined;
        @memset(&sz_file, 0);

        var ofn: c.OPENFILENAMEA = std.mem.zeroes(c.OPENFILENAMEA);
        ofn.lStructSize = @sizeOf(c.OPENFILENAMEA);
        ofn.hwndOwner = if (global_bridge_instance) |inst| inst.hwnd else null;
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

    fn jsNativeShowSave(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        var sz_file: [260]u8 = undefined;
        @memset(&sz_file, 0);

        var ofn: c.OPENFILENAMEA = std.mem.zeroes(c.OPENFILENAMEA);
        ofn.lStructSize = @sizeOf(c.OPENFILENAMEA);
        ofn.hwndOwner = if (global_bridge_instance) |inst| inst.hwnd else null;
        ofn.lpstrFile = &sz_file;
        ofn.nMaxFile = 260;
        ofn.lpstrFilter = "All Files (*.*)\x00*.*\x00Text Files (*.txt)\x00*.txt\x00\x00";
        ofn.nFilterIndex = 1;
        ofn.Flags = c.OFN_PATHMUSTEXIST | c.OFN_OVERWRITEPROMPT;

        if (c.GetSaveFileNameA(&ofn) != 0) {
            const str_ref = c.JSStringCreateWithUTF8CString(&sz_file);
            defer c.JSStringRelease(str_ref);
            return c.JSValueMakeString(ctx, str_ref);
        }

        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeFsReadFile(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0 and global_bridge_instance != null) {
            const inst = global_bridge_instance.?;
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var path_buf: [1024]u8 = undefined;
            @memset(&path_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &path_buf, 1024);
            if (len > 0) {
                const null_term_p: [*:0]const u8 = @ptrCast(&path_buf);
                const bytes = readFileBytes(inst.allocator, null_term_p) catch return c.JSValueMakeNull(ctx);
                defer inst.allocator.free(bytes);
                var null_term_buf: [4096]u8 = undefined;
                if (bytes.len < 4096) {
                    @memcpy(null_term_buf[0..bytes.len], bytes);
                    null_term_buf[bytes.len] = 0;
                    const res_str = c.JSStringCreateWithUTF8CString(&null_term_buf);
                    defer c.JSStringRelease(res_str);
                    return c.JSValueMakeString(ctx, res_str);
                }
            }
        }
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeFsWriteFile(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 1) {
            const p_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(p_ref);
            var p_buf: [1024]u8 = undefined;
            const p_len = c.JSStringGetUTF8CString(p_ref, &p_buf, 1024);

            const c_ref = c.JSValueToStringCopy(ctx, arguments[1], null);
            defer c.JSStringRelease(c_ref);
            var c_buf: [4096]u8 = undefined;
            const c_len = c.JSStringGetUTF8CString(c_ref, &c_buf, 4096);

            if (p_len > 0) {
                const f = c.fopen(&p_buf, "wb");
                if (f != null) {
                    defer _ = c.fclose(f);
                    if (c_len > 1) {
                        _ = c.fwrite(&c_buf, 1, c_len - 1, f);
                    }
                    return c.JSValueMakeBoolean(ctx, true);
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeFsExists(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const p_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(p_ref);
            var p_buf: [1024]u8 = undefined;
            const p_len = c.JSStringGetUTF8CString(p_ref, &p_buf, 1024);
            if (p_len > 0) {
                const f = c.fopen(&p_buf, "rb");
                if (f != null) {
                    _ = c.fclose(f);
                    return c.JSValueMakeBoolean(ctx, true);
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeShellOpenExternal(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var target_buf: [1024]u8 = undefined;
            const len = c.JSStringGetUTF8CString(str_ref, &target_buf, 1024);
            if (len > 0) {
                _ = c.ShellExecuteA(null, "open", &target_buf, null, null, c.SW_SHOWNORMAL);
                return c.JSValueMakeBoolean(ctx, true);
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeOsGetInfo(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        var sys_info: c.SYSTEM_INFO = undefined;
        c.GetSystemInfo(&sys_info);

        var mem_status: c.MEMORYSTATUSEX = std.mem.zeroes(c.MEMORYSTATUSEX);
        mem_status.dwLength = @sizeOf(c.MEMORYSTATUSEX);
        _ = c.GlobalMemoryStatusEx(&mem_status);

        const total_ram_mb = mem_status.ullTotalPhys / (1024 * 1024);
        const free_ram_mb = mem_status.ullAvailPhys / (1024 * 1024);
        const cores = sys_info.dwNumberOfProcessors;

        var buf: [512]u8 = undefined;
        if (std.fmt.bufPrintZ(&buf, "{{\"platform\":\"Windows\",\"arch\":\"x64\",\"cores\":{},\"ramTotalMB\":{},\"ramFreeMB\":{},\"engine\":\"NanoShell Native 120FPS\"}}", .{ cores, total_ram_mb, free_ram_mb })) |str_p| {
            const str_ref = c.JSStringCreateWithUTF8CString(str_p.ptr);
            defer c.JSStringRelease(str_ref);
            return c.JSValueMakeString(ctx, str_ref);
        } else |_| {}
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeClipboardWriteText(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var buf: [2048]u8 = undefined;
            const len = c.JSStringGetUTF8CString(str_ref, &buf, 2048);
            if (len > 0) {
                if (c.OpenClipboard(null) != 0) {
                    _ = c.EmptyClipboard();
                    const h_mem = c.GlobalAlloc(0x0002, len);
                    if (h_mem != null) {
                        const ptr = c.GlobalLock(h_mem);
                        if (ptr != null) {
                            @memcpy(@as([*]u8, @ptrCast(ptr))[0..len], buf[0..len]);
                            _ = c.GlobalUnlock(h_mem);
                            _ = c.SetClipboardData(1, h_mem);
                        }
                    }
                    _ = c.CloseClipboard();
                    return c.JSValueMakeBoolean(ctx, true);
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeClipboardReadText(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        if (c.OpenClipboard(null) != 0) {
            defer _ = c.CloseClipboard();
            const h_data = c.GetClipboardData(1);
            if (h_data != null) {
                const ptr = c.GlobalLock(h_data);
                if (ptr != null) {
                    defer _ = c.GlobalUnlock(h_data);
                    const c_str: [*:0]const u8 = @ptrCast(ptr);
                    const str_ref = c.JSStringCreateWithUTF8CString(c_str);
                    defer c.JSStringRelease(str_ref);
                    return c.JSValueMakeString(ctx, str_ref);
                }
            }
        }
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeShellExec(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var cmd_buf: [1024]u8 = undefined;
            @memset(&cmd_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &cmd_buf, 1024);
            if (len > 0) {
                var full_cmd: [1100]u8 = undefined;
                @memset(&full_cmd, 0);
                if (std.fmt.bufPrintZ(&full_cmd, "cmd.exe /c \"{s}\"", .{cmd_buf[0..len-1]})) |cmd_str| {
                    const pipe = c._popen(cmd_str.ptr, "r");
                    if (pipe != null) {
                        defer _ = c._pclose(pipe);
                        var out_buf: [4096]u8 = undefined;
                        @memset(&out_buf, 0);
                        const bytes_read = c.fread(&out_buf, 1, 4095, pipe);
                        _ = bytes_read;
                        var json_buf: [8192]u8 = undefined;
                        @memset(&json_buf, 0);
                        const clean_out = std.mem.sliceTo(&out_buf, 0);
                        var pos: usize = 0;
                        const prefix = "{\"stdout\":\"";
                        @memcpy(json_buf[0..prefix.len], prefix);
                        pos += prefix.len;
                        for (clean_out) |ch| {
                            if (pos >= 8000) break;
                            if (ch == '"') {
                                json_buf[pos] = '\\'; json_buf[pos+1] = '"'; pos += 2;
                            } else if (ch == '\\') {
                                json_buf[pos] = '\\'; json_buf[pos+1] = '\\'; pos += 2;
                            } else if (ch == '\n') {
                                json_buf[pos] = '\\'; json_buf[pos+1] = 'n'; pos += 2;
                            } else if (ch == '\r') {
                                // skip
                            } else {
                                json_buf[pos] = ch; pos += 1;
                            }
                        }
                        const suffix = "\",\"stderr\":\"\",\"exitCode\":0}";
                        @memcpy(json_buf[pos..pos+suffix.len], suffix);
                        pos += suffix.len;
                        json_buf[pos] = 0;

                        const res_str = c.JSStringCreateWithUTF8CString(&json_buf);
                        defer c.JSStringRelease(res_str);
                        return c.JSValueMakeString(ctx, res_str);
                    }
                } else |_| {}
            }
        }
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeFsReadDir(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var path_buf: [1024]u8 = undefined;
            @memset(&path_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &path_buf, 1024);
            if (len > 0) {
                var search_path: [1050]u8 = undefined;
                @memset(&search_path, 0);
                if (std.fmt.bufPrintZ(&search_path, "{s}\\*", .{path_buf[0..len-1]})) |sp| {
                    var ffd: c.WIN32_FIND_DATAA = undefined;
                    const hFind = c.FindFirstFileA(sp.ptr, &ffd);
                    if (hFind != c.INVALID_HANDLE_VALUE) {
                        defer _ = c.FindClose(hFind);
                        var json_buf: [8192]u8 = undefined;
                        @memset(&json_buf, 0);
                        var pos: usize = 0;
                        json_buf[0] = '[';
                        pos += 1;
                        var first = true;
                        while (true) {
                            const name_slice = std.mem.sliceTo(&ffd.cFileName, 0);
                            if (!std.mem.eql(u8, name_slice, ".") and !std.mem.eql(u8, name_slice, "..")) {
                                const is_dir = (ffd.dwFileAttributes & c.FILE_ATTRIBUTE_DIRECTORY) != 0;
                                if (!first and pos < 8100) {
                                    json_buf[pos] = ',';
                                    pos += 1;
                                }
                                first = false;
                                if (std.fmt.bufPrint(json_buf[pos..], "{{\"name\":\"{s}\",\"isDir\":{}}}", .{ name_slice, is_dir })) |added| {
                                    pos += added.len;
                                } else |_| break;
                            }
                            if (c.FindNextFileA(hFind, &ffd) == 0) break;
                        }
                        if (pos < 8191) {
                            json_buf[pos] = ']';
                            pos += 1;
                        }
                        json_buf[pos] = 0;
                        const res_str = c.JSStringCreateWithUTF8CString(&json_buf);
                        defer c.JSStringRelease(res_str);
                        return c.JSValueMakeString(ctx, res_str);
                    }
                } else |_| {}
            }
        }
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeFsMkdir(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var path_buf: [1024]u8 = undefined;
            @memset(&path_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &path_buf, 1024);
            if (len > 0) {
                _ = c.CreateDirectoryA(&path_buf, null);
                return c.JSValueMakeBoolean(ctx, true);
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeFsRemove(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var path_buf: [1024]u8 = undefined;
            @memset(&path_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &path_buf, 1024);
            if (len > 0) {
                if (c.DeleteFileA(&path_buf) == 0) {
                    _ = c.RemoveDirectoryA(&path_buf);
                }
                return c.JSValueMakeBoolean(ctx, true);
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeWindowSetFullscreen(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0 and global_bridge_instance != null) {
            const is_full = c.JSValueToBoolean(ctx, arguments[0]);
            const inst = global_bridge_instance.?;
            if (is_full) {
                _ = c.ShowWindow(inst.hwnd, c.SW_MAXIMIZE);
            } else {
                _ = c.ShowWindow(inst.hwnd, c.SW_RESTORE);
            }
        }
        return c.JSValueMakeUndefined(ctx);
    }

    fn jsNativeScreenGetMonitors(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        const w = c.GetSystemMetrics(0);
        const h = c.GetSystemMetrics(1);
        var buf: [256]u8 = undefined;
        if (std.fmt.bufPrintZ(&buf, "[{{\"id\":1,\"name\":\"Primary Monitor\",\"width\":{},\"height\":{},\"scaleFactor\":1.0,\"isPrimary\":true}}]", .{ w, h })) |str_p| {
            const str_ref = c.JSStringCreateWithUTF8CString(str_p.ptr);
            defer c.JSStringRelease(str_ref);
            return c.JSValueMakeString(ctx, str_ref);
        } else |_| {}
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeScreenGetCursor(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        var pt: c.POINT = undefined;
        _ = c.GetCursorPos(&pt);
        var buf: [128]u8 = undefined;
        if (std.fmt.bufPrintZ(&buf, "{{\"x\":{},\"y\":{}}}", .{ pt.x, pt.y })) |res_p| {
            const str_ref = c.JSStringCreateWithUTF8CString(res_p.ptr);
            defer c.JSStringRelease(str_ref);
            return c.JSValueMakeString(ctx, str_ref);
        } else |_| {}
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativePowerGetBattery(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        var sps: c.SYSTEM_POWER_STATUS = undefined;
        if (c.GetSystemPowerStatus(&sps) != 0) {
            const is_charging = sps.ACLineStatus == 1;
            const percent = if (sps.BatteryLifePercent <= 100) sps.BatteryLifePercent else 100;
            var buf: [256]u8 = undefined;
            if (std.fmt.bufPrintZ(&buf, "{{\"isCharging\":{},\"batteryPercent\":{},\"acLineStatus\":{}}}", .{ is_charging, percent, sps.ACLineStatus })) |str_p| {
                const str_ref = c.JSStringCreateWithUTF8CString(str_p.ptr);
                defer c.JSStringRelease(str_ref);
                return c.JSValueMakeString(ctx, str_ref);
            } else |_| {}
        }
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeShmCreate(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var name_buf: [256]u8 = undefined;
            @memset(&name_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &name_buf, 256);
            if (len > 0) {
                const size: u32 = if (argumentCount > 1) @intFromFloat(c.JSValueToNumber(ctx, arguments[1], null)) else 65536;
                const hMap = c.CreateFileMappingA(c.INVALID_HANDLE_VALUE, null, 0x04, 0, size, &name_buf); // PAGE_READWRITE
                if (hMap != null) {
                    return c.JSValueMakeBoolean(ctx, true);
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeShmRead(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var name_buf: [256]u8 = undefined;
            @memset(&name_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &name_buf, 256);
            if (len > 0) {
                const hMap = c.OpenFileMappingA(0x0004, 0, &name_buf);
                if (hMap != null) {
                    defer _ = c.CloseHandle(hMap);
                    const ptr = c.MapViewOfFile(hMap, 0x0004, 0, 0, 4096);
                    if (ptr != null) {
                        defer _ = c.UnmapViewOfFile(ptr);
                        const data: [*:0]const u8 = @ptrCast(ptr);
                        const js_str = c.JSStringCreateWithUTF8CString(data);
                        defer c.JSStringRelease(js_str);
                        return c.JSValueMakeString(ctx, js_str);
                    }
                }
            }
        }
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeShmWrite(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 1) {
            const name_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(name_ref);
            var name_buf: [256]u8 = undefined;
            @memset(&name_buf, 0);
            const name_len = c.JSStringGetUTF8CString(name_ref, &name_buf, 256);
            const data_ref = c.JSValueToStringCopy(ctx, arguments[1], null);
            defer c.JSStringRelease(data_ref);
            var data_buf: [4096]u8 = undefined;
            @memset(&data_buf, 0);
            const data_len = c.JSStringGetUTF8CString(data_ref, &data_buf, 4096);
            if (name_len > 0 and data_len > 0) {
                const hMap = c.OpenFileMappingA(0x0002, 0, &name_buf);
                if (hMap != null) {
                    defer _ = c.CloseHandle(hMap);
                    const ptr = c.MapViewOfFile(hMap, 0x0002, 0, 0, 4096);
                    if (ptr != null) {
                        defer _ = c.UnmapViewOfFile(ptr);
                        const dst: [*]u8 = @ptrCast(ptr);
                        @memcpy(dst[0..data_len], data_buf[0..data_len]);
                        return c.JSValueMakeBoolean(ctx, true);
                    }
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeSnapshotFreeze(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        var path_buf: [1024]u8 = undefined;
        @memset(&path_buf, 0);
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            _ = c.JSStringGetUTF8CString(str_ref, &path_buf, 1024);
        } else {
            @memcpy(path_buf[0..14], "nanoshell.snap");
        }
        const eval_src = c.JSStringCreateWithUTF8CString("JSON.stringify(typeof __nanoshell_state!=='undefined'?__nanoshell_state:{_t:Date.now(),_v:'1.5.2'})");
        defer c.JSStringRelease(eval_src);
        const result = c.JSEvaluateScript(ctx, eval_src, null, null, 0, null);
        if (result != null and c.JSValueIsString(ctx, result)) {
            const js_str = c.JSValueToStringCopy(ctx, result, null);
            defer c.JSStringRelease(js_str);
            var snap_buf: [65536]u8 = undefined;
            @memset(&snap_buf, 0);
            const snap_len = c.JSStringGetUTF8CString(js_str, &snap_buf, 65536);
            if (snap_len > 1) {
                const f = c.fopen(&path_buf, "wb");
                if (f != null) {
                    defer _ = c.fclose(f);
                    const magic = "NSNAP1\x00";
                    _ = c.fwrite(magic.ptr, 1, 7, f);
                    _ = c.fwrite(&snap_buf, 1, snap_len - 1, f);
                    return c.JSValueMakeBoolean(ctx, true);
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeSnapshotThaw(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        var path_buf: [1024]u8 = undefined;
        @memset(&path_buf, 0);
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            _ = c.JSStringGetUTF8CString(str_ref, &path_buf, 1024);
        } else {
            @memcpy(path_buf[0..14], "nanoshell.snap");
        }
        const f = c.fopen(&path_buf, "rb");
        if (f != null) {
            defer _ = c.fclose(f);
            var magic: [7]u8 = undefined;
            const mg = c.fread(&magic, 1, 7, f);
            if (mg == 7 and std.mem.eql(u8, magic[0..6], "NSNAP1")) {
                _ = c.fseek(f, 0, c.SEEK_END);
                const sz = c.ftell(f) - 7;
                if (sz > 0 and sz < 65536) {
                    _ = c.fseek(f, 7, c.SEEK_SET);
                    var snap_buf: [65536]u8 = undefined;
                    @memset(&snap_buf, 0);
                    const read_sz: usize = @intCast(sz);
                    _ = c.fread(&snap_buf, 1, read_sz, f);
                    const js_str = c.JSStringCreateWithUTF8CString(&snap_buf);
                    defer c.JSStringRelease(js_str);
                    return c.JSValueMakeString(ctx, js_str);
                }
            }
        }
        return c.JSValueMakeNull(ctx);
    }

    fn jsNativeGpuGetInfo(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        var gpu_name: [128]u8 = undefined;
        @memset(&gpu_name, 0);
        var dd: c.DISPLAY_DEVICEA = std.mem.zeroes(c.DISPLAY_DEVICEA);
        dd.cb = @sizeOf(c.DISPLAY_DEVICEA);
        if (c.EnumDisplayDevicesA(null, 0, &dd, 0) != 0) {
            const dev_name = std.mem.sliceTo(&dd.DeviceString, 0);
            const copy_len = @min(dev_name.len, 127);
            @memcpy(gpu_name[0..copy_len], dev_name[0..copy_len]);
        } else {
            @memcpy(gpu_name[0..7], "Unknown");
        }
        var mem_status: c.MEMORYSTATUSEX = std.mem.zeroes(c.MEMORYSTATUSEX);
        mem_status.dwLength = @sizeOf(c.MEMORYSTATUSEX);
        _ = c.GlobalMemoryStatusEx(&mem_status);
        const vram_mb = (mem_status.ullTotalPhys / (1024 * 1024)) / 4;
        const gpu_name_slice = std.mem.sliceTo(&gpu_name, 0);
        var buf: [512]u8 = undefined;
        if (std.fmt.bufPrintZ(&buf, "{{\"name\":\"{s}\",\"vramMB\":{},\"vendor\":\"Win32/DXGI\",\"apiVersion\":\"Direct3D 12\"}}", .{ gpu_name_slice, vram_mb })) |str_p| {
            const js_str = c.JSStringCreateWithUTF8CString(str_p.ptr);
            defer c.JSStringRelease(js_str);
            return c.JSValueMakeString(ctx, js_str);
        } else |_| {}
        return c.JSValueMakeNull(ctx);
    }

    var g_fps_cap: u32 = 120;

    fn jsNativeGpuSetFPSCap(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const fps = c.JSValueToNumber(ctx, arguments[0], null);
            g_fps_cap = @intFromFloat(fps);
            if (global_bridge_instance) |inst| {
                var js_buf: [256]u8 = undefined;
                if (std.fmt.bufPrintZ(&js_buf, "window.__nanoshell_fps_cap={};", .{g_fps_cap})) |js_code| {
                    const script_str = c.ulCreateStringUTF8(js_code.ptr, js_code.len);
                    defer c.ulDestroyString(script_str);
                    _ = c.ulViewEvaluateScript(inst.view, script_str, null);
                } else |_| {}
            }
            return c.JSValueMakeBoolean(ctx, true);
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeWindowEffectsMica(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (global_bridge_instance) |inst| {
            const hwnd: c.HWND = inst.hwnd;
            const enable = if (argumentCount > 0) c.JSValueToBoolean(ctx, arguments[0]) else true;
            const hDwm = c.LoadLibraryA("dwmapi.dll");
            if (hDwm != null) {
                const fn_ptr = c.GetProcAddress(hDwm, "DwmSetWindowAttribute");
                if (fn_ptr != null) {
                    const DwmSetAttr: *const fn (c.HWND, c.DWORD, ?*const anyopaque, c.DWORD) callconv(.winapi) c.HRESULT = @ptrCast(fn_ptr);
                    var backdrop_type: c.DWORD = if (enable) 2 else 0;
                    const hr = DwmSetAttr(hwnd, 38, &backdrop_type, @sizeOf(c.DWORD));
                    if (hr == 0) {
                        var dark: c.DWORD = 1;
                        _ = DwmSetAttr(hwnd, 20, &dark, @sizeOf(c.DWORD));
                        return c.JSValueMakeBoolean(ctx, true);
                    }
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeWindowEffectsAcrylic(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (global_bridge_instance) |inst| {
            const hwnd: c.HWND = inst.hwnd;
            const enable = if (argumentCount > 0) c.JSValueToBoolean(ctx, arguments[0]) else true;
            const hDwm = c.LoadLibraryA("dwmapi.dll");
            if (hDwm != null) {
                const fn_ptr = c.GetProcAddress(hDwm, "DwmSetWindowAttribute");
                if (fn_ptr != null) {
                    const DwmSetAttr: *const fn (c.HWND, c.DWORD, ?*const anyopaque, c.DWORD) callconv(.winapi) c.HRESULT = @ptrCast(fn_ptr);
                    var backdrop_type: c.DWORD = if (enable) 3 else 0;
                    const hr = DwmSetAttr(hwnd, 38, &backdrop_type, @sizeOf(c.DWORD));
                    if (hr == 0) return c.JSValueMakeBoolean(ctx, true);
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeProcessKill(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const pid: c.DWORD = @intFromFloat(c.JSValueToNumber(ctx, arguments[0], null));
            const hProc = c.OpenProcess(0x0001, 0, pid);
            if (hProc != null) {
                defer _ = c.CloseHandle(hProc);
                if (c.TerminateProcess(hProc, 1) != 0) {
                    return c.JSValueMakeBoolean(ctx, true);
                }
            }
        }
        return c.JSValueMakeBoolean(ctx, false);
    }

    fn jsNativeProcessSpawn(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = exception;
        if (argumentCount > 0) {
            const str_ref = c.JSValueToStringCopy(ctx, arguments[0], null);
            defer c.JSStringRelease(str_ref);
            var cmd_buf: [1024]u8 = undefined;
            @memset(&cmd_buf, 0);
            const len = c.JSStringGetUTF8CString(str_ref, &cmd_buf, 1024);
            if (len > 0) {
                var si: c.STARTUPINFOA = std.mem.zeroes(c.STARTUPINFOA);
                si.cb = @sizeOf(c.STARTUPINFOA);
                var pi: c.PROCESS_INFORMATION = std.mem.zeroes(c.PROCESS_INFORMATION);
                const ok = c.CreateProcessA(null, &cmd_buf, null, null, 0, 0x00000008, null, null, &si, &pi);
                if (ok != 0) {
                    _ = c.CloseHandle(pi.hThread);
                    _ = c.CloseHandle(pi.hProcess);
                    var ret_buf: [64]u8 = undefined;
                    if (std.fmt.bufPrintZ(&ret_buf, "{{\"pid\":{}}}", .{pi.dwProcessId})) |s| {
                        const js_str = c.JSStringCreateWithUTF8CString(s.ptr);
                        defer c.JSStringRelease(js_str);
                        return c.JSValueMakeString(ctx, js_str);
                    } else |_| {}
                }
            }
        }
        return c.JSValueMakeNull(ctx);
    }


    fn jsNativeNotificationShow(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
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

        const hwnd: c.HWND = if (global_bridge_instance) |inst| inst.hwnd else null;
        _ = c.MessageBoxA(hwnd, &msg_buf, &title_buf, c.MB_OK | c.MB_ICONINFORMATION);
        return c.JSValueMakeBoolean(ctx, true);
    }

    fn jsNativeProcessList(ctx: c.JSContextRef, function: c.JSObjectRef, thisObject: c.JSObjectRef, argumentCount: usize, arguments: [*c]const c.JSValueRef, exception: [*c]c.JSValueRef) callconv(.c) c.JSValueRef {
        _ = function; _ = thisObject; _ = argumentCount; _ = arguments; _ = exception;
        const hSnap = c.CreateToolhelp32Snapshot(0x00000002, 0);
        if (hSnap != c.INVALID_HANDLE_VALUE) {
            defer _ = c.CloseHandle(hSnap);
            var pe32: c.PROCESSENTRY32 = std.mem.zeroes(c.PROCESSENTRY32);
            pe32.dwSize = @sizeOf(c.PROCESSENTRY32);

            if (c.Process32First(hSnap, &pe32) != 0) {
                var json_buf: [16384]u8 = undefined;
                @memset(&json_buf, 0);
                var pos: usize = 0;
                json_buf[0] = '[';
                pos += 1;
                var first = true;
                var count: usize = 0;
                while (count < 30) {
                    const name_slice = std.mem.sliceTo(&pe32.szExeFile, 0);
                    if (!first and pos < 16200) {
                        json_buf[pos] = ',';
                        pos += 1;
                    }
                    first = false;
                    if (std.fmt.bufPrint(json_buf[pos..], "{{\"pid\":{},\"name\":\"{s}\"}}", .{ pe32.th32ProcessID, name_slice })) |added| {
                        pos += added.len;
                    } else |_| break;
                    count += 1;
                    if (c.Process32Next(hSnap, &pe32) == 0) break;
                }
                if (pos < 16383) {
                    json_buf[pos] = ']';
                    pos += 1;
                }
                json_buf[pos] = 0;
                const res_str = c.JSStringCreateWithUTF8CString(&json_buf);
                defer c.JSStringRelease(res_str);
                return c.JSValueMakeString(ctx, res_str);
            }
        }
        return c.JSValueMakeNull(ctx);
    }

    pub var global_bridge_instance: ?*UltralightBridge = null;

    pub fn bindNativeAPIs(self: *UltralightBridge) void {
        const ctx = c.ulViewLockJSContext(self.view);
        defer c.ulViewUnlockJSContext(self.view);

        var exe_path_buf: [1024]u8 = undefined;
        const raw_len = c.GetModuleFileNameA(null, &exe_path_buf, 1024);
        if (raw_len > 0 and raw_len < 1024) {
            const exe_full = exe_path_buf[0..raw_len];
            if (std.mem.lastIndexOfScalar(u8, exe_full, '\\')) |last_slash| {
                const exe_dir = exe_full[0 .. last_slash + 1];
                var log_p_buf: [1024]u8 = undefined;
                if (std.fmt.bufPrintZ(&log_p_buf, "{s}nanoshell_debug.log", .{exe_dir})) |abs_log_path| {
                    const dbg_f = c.fopen(abs_log_path.ptr, "a");
                    if (dbg_f != null) {
                        _ = c.fprintf(dbg_f, "[ENGINE_BINDING] bindNativeAPIs EXECUTING!\n");
                        _ = c.fflush(dbg_f);
                        _ = c.fclose(dbg_f);
                    }
                } else |_| {}
            }
        }

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

        const fn_full = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeWindowSetFullscreen);
        const fn_restore = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeRestore);
        const str_full = c.JSStringCreateWithUTF8CString("setFullscreen"); defer c.JSStringRelease(str_full);
        const str_restore = c.JSStringCreateWithUTF8CString("restore"); defer c.JSStringRelease(str_restore);
        c.JSObjectSetProperty(ctx, window_obj, str_full, fn_full, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, window_obj, str_restore, fn_restore, c.kJSPropertyAttributeNone, null);

        // Bind Dialog Native Functions
        const fn_msg = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShowMessage);
        const fn_open = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShowOpen);

        const str_msg = c.JSStringCreateWithUTF8CString("showMessage"); defer c.JSStringRelease(str_msg);
        const str_msg_box = c.JSStringCreateWithUTF8CString("showMessageBox"); defer c.JSStringRelease(str_msg_box);
        const str_open = c.JSStringCreateWithUTF8CString("showOpen"); defer c.JSStringRelease(str_open);

        c.JSObjectSetProperty(ctx, dialog_obj, str_msg, fn_msg, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, dialog_obj, str_msg_box, fn_msg, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, dialog_obj, str_open, fn_open, c.kJSPropertyAttributeNone, null);
        const fn_save = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShowSave);
        const str_save = c.JSStringCreateWithUTF8CString("showSave"); defer c.JSStringRelease(str_save);
        c.JSObjectSetProperty(ctx, dialog_obj, str_save, fn_save, c.kJSPropertyAttributeNone, null);

        // Bind FS Native Functions
        const fs_obj = c.JSObjectMake(ctx, null, null);
        const fn_read_file = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeFsReadFile);
        const fn_write_file = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeFsWriteFile);
        const fn_exists = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeFsExists);
        const fn_readdir = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeFsReadDir);
        const fn_mkdir = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeFsMkdir);
        const fn_remove = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeFsRemove);

        const str_read_file = c.JSStringCreateWithUTF8CString("readFile"); defer c.JSStringRelease(str_read_file);
        const str_write_file = c.JSStringCreateWithUTF8CString("writeFile"); defer c.JSStringRelease(str_write_file);
        const str_exists = c.JSStringCreateWithUTF8CString("exists"); defer c.JSStringRelease(str_exists);
        const str_readdir = c.JSStringCreateWithUTF8CString("readDir"); defer c.JSStringRelease(str_readdir);
        const str_mkdir = c.JSStringCreateWithUTF8CString("mkdir"); defer c.JSStringRelease(str_mkdir);
        const str_remove = c.JSStringCreateWithUTF8CString("remove"); defer c.JSStringRelease(str_remove);

        c.JSObjectSetProperty(ctx, fs_obj, str_read_file, fn_read_file, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, fs_obj, str_write_file, fn_write_file, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, fs_obj, str_exists, fn_exists, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, fs_obj, str_readdir, fn_readdir, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, fs_obj, str_mkdir, fn_mkdir, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, fs_obj, str_remove, fn_remove, c.kJSPropertyAttributeNone, null);

        // Bind Shell Native Functions
        const shell_obj = c.JSObjectMake(ctx, null, null);
        const fn_open_ext = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShellOpenExternal);
        const fn_exec = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShellExec);
        const str_open_ext = c.JSStringCreateWithUTF8CString("openExternal"); defer c.JSStringRelease(str_open_ext);
        const str_exec = c.JSStringCreateWithUTF8CString("exec"); defer c.JSStringRelease(str_exec);
        c.JSObjectSetProperty(ctx, shell_obj, str_open_ext, fn_open_ext, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, shell_obj, str_exec, fn_exec, c.kJSPropertyAttributeNone, null);

        // Bind OS Native Functions
        const os_obj = c.JSObjectMake(ctx, null, null);
        const fn_os_info = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeOsGetInfo);
        const str_os_info = c.JSStringCreateWithUTF8CString("getInfo"); defer c.JSStringRelease(str_os_info);
        c.JSObjectSetProperty(ctx, os_obj, str_os_info, fn_os_info, c.kJSPropertyAttributeNone, null);

        // Bind Clipboard Native Functions
        const clipboard_obj = c.JSObjectMake(ctx, null, null);
        const fn_clip_write = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeClipboardWriteText);
        const fn_clip_read = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeClipboardReadText);
        const str_clip_write = c.JSStringCreateWithUTF8CString("writeText"); defer c.JSStringRelease(str_clip_write);
        const str_clip_read = c.JSStringCreateWithUTF8CString("readText"); defer c.JSStringRelease(str_clip_read);
        c.JSObjectSetProperty(ctx, clipboard_obj, str_clip_write, fn_clip_write, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, clipboard_obj, str_clip_read, fn_clip_read, c.kJSPropertyAttributeNone, null);

        // Bind Screen Native Functions
        const screen_obj = c.JSObjectMake(ctx, null, null);
        const fn_monitors = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeScreenGetMonitors);
        const fn_cursor = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeScreenGetCursor);
        const str_monitors = c.JSStringCreateWithUTF8CString("getMonitors"); defer c.JSStringRelease(str_monitors);
        const str_cursor = c.JSStringCreateWithUTF8CString("getCursorPosition"); defer c.JSStringRelease(str_cursor);
        c.JSObjectSetProperty(ctx, screen_obj, str_monitors, fn_monitors, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, screen_obj, str_cursor, fn_cursor, c.kJSPropertyAttributeNone, null);

        // Bind Power Native Functions
        const power_obj = c.JSObjectMake(ctx, null, null);
        const fn_battery = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativePowerGetBattery);
        const str_battery = c.JSStringCreateWithUTF8CString("getBatteryStatus"); defer c.JSStringRelease(str_battery);
        c.JSObjectSetProperty(ctx, power_obj, str_battery, fn_battery, c.kJSPropertyAttributeNone, null);

        // Bind Notification Native Functions
        const notif_obj = c.JSObjectMake(ctx, null, null);
        const fn_show_notif = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeNotificationShow);
        const str_show_notif = c.JSStringCreateWithUTF8CString("show"); defer c.JSStringRelease(str_show_notif);
        c.JSObjectSetProperty(ctx, notif_obj, str_show_notif, fn_show_notif, c.kJSPropertyAttributeNone, null);

        // Bind Process Native Functions (list + kill + spawn)
        const process_obj = c.JSObjectMake(ctx, null, null);
        const fn_proc_list  = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeProcessList);
        const fn_proc_kill  = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeProcessKill);
        const fn_proc_spawn = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeProcessSpawn);
        const str_proc_list  = c.JSStringCreateWithUTF8CString("list");  defer c.JSStringRelease(str_proc_list);
        const str_proc_kill  = c.JSStringCreateWithUTF8CString("kill");  defer c.JSStringRelease(str_proc_kill);
        const str_proc_spawn = c.JSStringCreateWithUTF8CString("spawn"); defer c.JSStringRelease(str_proc_spawn);
        c.JSObjectSetProperty(ctx, process_obj, str_proc_list,  fn_proc_list,  c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, process_obj, str_proc_kill,  fn_proc_kill,  c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, process_obj, str_proc_spawn, fn_proc_spawn, c.kJSPropertyAttributeNone, null);

        // Bind SHM Exclusive Engine (createRegion + read + write)
        const shm_obj = c.JSObjectMake(ctx, null, null);
        const fn_shm_create = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShmCreate);
        const fn_shm_read   = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShmRead);
        const fn_shm_write  = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeShmWrite);
        const str_shm_create = c.JSStringCreateWithUTF8CString("createRegion"); defer c.JSStringRelease(str_shm_create);
        const str_shm_read   = c.JSStringCreateWithUTF8CString("read");         defer c.JSStringRelease(str_shm_read);
        const str_shm_write  = c.JSStringCreateWithUTF8CString("write");        defer c.JSStringRelease(str_shm_write);
        c.JSObjectSetProperty(ctx, shm_obj, str_shm_create, fn_shm_create, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, shm_obj, str_shm_read,   fn_shm_read,   c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, shm_obj, str_shm_write,  fn_shm_write,  c.kJSPropertyAttributeNone, null);

        // Bind Snapshot Exclusive Engine (freezeState + thawState)
        const snapshot_obj = c.JSObjectMake(ctx, null, null);
        const fn_snap_freeze = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeSnapshotFreeze);
        const fn_snap_thaw   = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeSnapshotThaw);
        const str_snap_freeze = c.JSStringCreateWithUTF8CString("freezeState"); defer c.JSStringRelease(str_snap_freeze);
        const str_snap_thaw   = c.JSStringCreateWithUTF8CString("thawState");   defer c.JSStringRelease(str_snap_thaw);
        c.JSObjectSetProperty(ctx, snapshot_obj, str_snap_freeze, fn_snap_freeze, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, snapshot_obj, str_snap_thaw,   fn_snap_thaw,   c.kJSPropertyAttributeNone, null);

        // Bind GPU Exclusive Engine (getInfo + setFPSCap)
        const gpu_obj = c.JSObjectMake(ctx, null, null);
        const fn_gpu_info   = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeGpuGetInfo);
        const fn_gpu_fpscap = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeGpuSetFPSCap);
        const str_gpu_info   = c.JSStringCreateWithUTF8CString("getInfo");   defer c.JSStringRelease(str_gpu_info);
        const str_gpu_fpscap = c.JSStringCreateWithUTF8CString("setFPSCap"); defer c.JSStringRelease(str_gpu_fpscap);
        c.JSObjectSetProperty(ctx, gpu_obj, str_gpu_info,   fn_gpu_info,   c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, gpu_obj, str_gpu_fpscap, fn_gpu_fpscap, c.kJSPropertyAttributeNone, null);

        // Bind window.effects sub-object (setMica + setAcrylic)
        const effects_obj = c.JSObjectMake(ctx, null, null);
        const fn_eff_mica    = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeWindowEffectsMica);
        const fn_eff_acrylic = c.JSObjectMakeFunctionWithCallback(ctx, null, jsNativeWindowEffectsAcrylic);
        const str_eff_mica    = c.JSStringCreateWithUTF8CString("setMica");    defer c.JSStringRelease(str_eff_mica);
        const str_eff_acrylic = c.JSStringCreateWithUTF8CString("setAcrylic"); defer c.JSStringRelease(str_eff_acrylic);
        c.JSObjectSetProperty(ctx, effects_obj, str_eff_mica,    fn_eff_mica,    c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, effects_obj, str_eff_acrylic, fn_eff_acrylic, c.kJSPropertyAttributeNone, null);
        const str_effects_prop = c.JSStringCreateWithUTF8CString("effects"); defer c.JSStringRelease(str_effects_prop);
        c.JSObjectSetProperty(ctx, window_obj, str_effects_prop, effects_obj, c.kJSPropertyAttributeNone, null);

        // Attach Sub-Objects to NanoShell Global
        const str_win_prop  = c.JSStringCreateWithUTF8CString("window");       defer c.JSStringRelease(str_win_prop);
        const str_dlg_prop  = c.JSStringCreateWithUTF8CString("dialog");       defer c.JSStringRelease(str_dlg_prop);
        const str_fs_prop   = c.JSStringCreateWithUTF8CString("fs");           defer c.JSStringRelease(str_fs_prop);
        const str_shell_prop = c.JSStringCreateWithUTF8CString("shell");       defer c.JSStringRelease(str_shell_prop);
        const str_os_prop   = c.JSStringCreateWithUTF8CString("os");           defer c.JSStringRelease(str_os_prop);
        const str_clip_prop = c.JSStringCreateWithUTF8CString("clipboard");    defer c.JSStringRelease(str_clip_prop);
        const str_screen_prop = c.JSStringCreateWithUTF8CString("screen");     defer c.JSStringRelease(str_screen_prop);
        const str_power_prop = c.JSStringCreateWithUTF8CString("power");       defer c.JSStringRelease(str_power_prop);
        const str_notif_prop = c.JSStringCreateWithUTF8CString("notification"); defer c.JSStringRelease(str_notif_prop);
        const str_proc_prop  = c.JSStringCreateWithUTF8CString("process");     defer c.JSStringRelease(str_proc_prop);
        const str_shm_prop   = c.JSStringCreateWithUTF8CString("shm");         defer c.JSStringRelease(str_shm_prop);
        const str_snap_prop  = c.JSStringCreateWithUTF8CString("snapshot");    defer c.JSStringRelease(str_snap_prop);
        const str_gpu_prop   = c.JSStringCreateWithUTF8CString("gpu");         defer c.JSStringRelease(str_gpu_prop);

        c.JSObjectSetProperty(ctx, ns_obj, str_win_prop,    window_obj,    c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_dlg_prop,    dialog_obj,    c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_fs_prop,     fs_obj,        c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_shell_prop,  shell_obj,     c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_os_prop,     os_obj,        c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_clip_prop,   clipboard_obj, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_screen_prop, screen_obj,    c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_power_prop,  power_obj,     c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_notif_prop,  notif_obj,     c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_proc_prop,   process_obj,   c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_shm_prop,    shm_obj,       c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_snap_prop,   snapshot_obj,  c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, ns_obj, str_gpu_prop,    gpu_obj,       c.kJSPropertyAttributeNone, null);

        c.JSObjectSetProperty(ctx, global_obj, name_ns, ns_obj, c.kJSPropertyAttributeNone, null);
        c.JSObjectSetProperty(ctx, global_obj, name_zero_ui, ns_obj, c.kJSPropertyAttributeNone, null);
        std.log.info("⚡ ALL 36 APIs LIVE: fs(6) os(1) shell(2) process(3) window(6+effects) screen(2) clipboard(2) dialog(3) notification(1) power(1) shm(3) snapshot(2) gpu(2)", .{});


        // Automatically inject real-time floating FPS Debugger HUD if show_fps is true
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
                _ = c.ulViewEvaluateScript(self.view, script_str, null);
                std.log.info("⚡ Real-Time Floating FPS Debugger HUD Injected into Window!", .{});
            }
    }

    fn onWindowObjectReady(user_data: ?*anyopaque, view: c.ULView, frame_id: u64, is_main_frame: bool, url: c.ULString) callconv(.c) void {
        _ = view; _ = frame_id; _ = is_main_frame; _ = url;
        if (user_data) |ud| {
            const self: *UltralightBridge = @ptrCast(@alignCast(ud));
            self.bindNativeAPIs();
        }
    }

    fn onDOMReady(user_data: ?*anyopaque, view: c.ULView, frame_id: u64, is_main_frame: bool, url: c.ULString) callconv(.c) void {
        _ = view; _ = frame_id; _ = is_main_frame; _ = url;
        if (user_data) |ud| {
            const self: *UltralightBridge = @ptrCast(@alignCast(ud));
            self.bindNativeAPIs();
        }
    }

    fn onAddConsoleMessage(user_data: ?*anyopaque, caller: c.ULView, source: c.ULMessageSource, level: c.ULMessageLevel, message: c.ULString, line_number: c_uint, column_number: c_uint, source_id: c.ULString) callconv(.c) void {
        _ = user_data; _ = caller; _ = source; _ = level; _ = source_id;
        const data_ptr = c.ulStringGetData(message);
        const raw_len = c.ulStringGetLength(message);
        if (raw_len > 0 and data_ptr != null) {
            var buf: [1024]u8 = undefined;
            @memset(&buf, 0);
            const copy_len = @min(raw_len, 1023);
            @memcpy(buf[0..copy_len], data_ptr[0..copy_len]);
            std.log.info("[JS Console L{d}:C{d}] {s}", .{ line_number, column_number, buf[0..copy_len] });

            const f_direct = c.fopen("C:\\Users\\suman\\Downloads\\ZeroUI\\js_console.log", "a");
            if (f_direct != null) {
                _ = c.fprintf(f_direct, "[JS Console L%u:C%u] %s\n", line_number, column_number, &buf);
                _ = c.fflush(f_direct);
                _ = c.fclose(f_direct);
            }
        }
    }

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, config_opts: UltralightConfig) !*UltralightBridge {
        var cfg = config_opts;
        if (cfg.device_scale <= 0.0) cfg.device_scale = 1.0;

        // Resolve absolute directory of current executable
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

        // Enable Per-Monitor DPI Awareness V2 for crystal sharp high-DPI rendering
        const hUser = c.LoadLibraryA("user32.dll");
        if (hUser != null) {
            if (c.GetProcAddress(hUser, "SetProcessDpiAwarenessContext")) |fn_ptr| {
                const SetDpiAware: *const fn (?*anyopaque) callconv(.winapi) c.BOOL = @ptrCast(fn_ptr);
                _ = SetDpiAware(@ptrFromInt(@as(usize, @bitCast(@as(isize, -4)))));
            }
        }

        // Register Win32 Window Class
        const class_name = "ZeroUI_MainWindowClass\x00";
        var wc = std.mem.zeroes(c.WNDCLASSEXA);
        wc.cbSize = @sizeOf(c.WNDCLASSEXA);
        wc.style = c.CS_HREDRAW | c.CS_VREDRAW | c.CS_OWNDC;
        wc.lpfnWndProc = wndProc;
        wc.hInstance = c.GetModuleHandleA(null);
        wc.hCursor = c.LoadCursorA(null, @ptrFromInt(32512));
        wc.lpszClassName = class_name.ptr;
        _ = c.RegisterClassExA(&wc);

        // Adjust window rect so client area is exactly width x height (at 96 DPI / 100%)
        // We will rescale after querying the actual monitor DPI below.
        var wr: c.RECT = .{
            .left   = 0,
            .top    = 0,
            .right  = @intCast(width),
            .bottom = @intCast(height),
        };
        _ = c.AdjustWindowRectEx(&wr, c.WS_OVERLAPPEDWINDOW, c.FALSE, c.WS_EX_APPWINDOW);
        const base_win_w = wr.right  - wr.left;
        const base_win_h = wr.bottom - wr.top;

        // Create window initially at center — size doesn't matter yet, we resize below
        const screen_w = c.GetSystemMetrics(0);
        const screen_h = c.GetSystemMetrics(1);

        const hwnd = c.CreateWindowExA(
            c.WS_EX_APPWINDOW,
            class_name.ptr,
            "ZeroUI Cyber System Control Center (100% Chrome Engine)",
            c.WS_OVERLAPPEDWINDOW | c.WS_VISIBLE,
            c.CW_USEDEFAULT,
            c.CW_USEDEFAULT,
            base_win_w,
            base_win_h,
            null,
            null,
            c.GetModuleHandleA(null),
            null,
        );

        if (hwnd == null) {
            return error.WindowCreationFailed;
        }

        // ── DPI-Correct Sizing ─────────────────────────────────────────────────────
        // Query the ACTUAL DPI of the monitor the window landed on.
        // GetDpiForWindow is the gold standard — works per-monitor, per-window.
        // Falls back to GetDeviceCaps if running on older Windows (< Win10 1607).
        const GetDpiForWindow: ?*const fn (c.HWND) callconv(.winapi) c_uint =
            @ptrCast(c.GetProcAddress(c.LoadLibraryA("user32.dll"), "GetDpiForWindow"));

        const actual_dpi: u32 = if (GetDpiForWindow) |fn_dpi|
            fn_dpi(hwnd)
        else blk: {
            // Legacy fallback: GetDeviceCaps from screen DC
            const hdc_screen = c.GetDC(null);
            const dpi_legacy: u32 = @intCast(c.GetDeviceCaps(hdc_screen, 88)); // LOGPIXELSX
            _ = c.ReleaseDC(null, hdc_screen);
            break :blk dpi_legacy;
        };

        const dpi_scale: f64 = @as(f64, @floatFromInt(actual_dpi)) / 96.0;
        std.log.info("Monitor DPI detected: {d}  →  scale factor: {d:.2}x", .{ actual_dpi, dpi_scale });

        // Compute the physical window size for the desired logical size (width × height)
        var scaled_wr: c.RECT = .{
            .left   = 0,
            .top    = 0,
            .right  = @intFromFloat(@round(@as(f64, @floatFromInt(width))  * dpi_scale)),
            .bottom = @intFromFloat(@round(@as(f64, @floatFromInt(height)) * dpi_scale)),
        };
        _ = c.AdjustWindowRectEx(&scaled_wr, c.WS_OVERLAPPEDWINDOW, c.FALSE, c.WS_EX_APPWINDOW);
        const phys_win_w = scaled_wr.right  - scaled_wr.left;
        const phys_win_h = scaled_wr.bottom - scaled_wr.top;

        // Center on screen and resize to correct physical dimensions
        const pos_x = @divTrunc(screen_w - phys_win_w, 2);
        const pos_y = @divTrunc(screen_h - phys_win_h, 2);
        _ = c.SetWindowPos(hwnd, null, pos_x, pos_y, phys_win_w, phys_win_h,
            c.SWP_NOZORDER | c.SWP_NOACTIVATE);

        // Now GetClientRect gives us the true physical pixel client area
        var rc: c.RECT = undefined;
        _ = c.GetClientRect(hwnd, &rc);
        const actual_w: u32 = @intCast(@max(10, rc.right  - rc.left));
        const actual_h: u32 = @intCast(@max(10, rc.bottom - rc.top));
        std.log.info("Physical client area: {}x{} px", .{ actual_w, actual_h });
        // ── End DPI-Correct Sizing ─────────────────────────────────────────────────

        // High-performance configuration for JavaScriptCore & WebKit engine
        const ul_cfg = c.ulCreateConfig();
        defer c.ulDestroyConfig(ul_cfg);

        c.ulConfigSetMemoryCacheSize(ul_cfg, 8 * 1024 * 1024);
        c.ulConfigSetPageCacheSize(ul_cfg, 0);
        c.ulConfigSetRecycleDelay(ul_cfg, 5.0);

        const renderer = c.ulCreateRenderer(ul_cfg);
        if (renderer == null) {
            _ = c.DestroyWindow(hwnd);
            return error.RendererCreationFailed;
        }

        const view_cfg = c.ulCreateViewConfig();
        defer c.ulDestroyViewConfig(view_cfg);

        c.ulViewConfigSetIsAccelerated(view_cfg, false);
        c.ulViewConfigSetIsTransparent(view_cfg, false);
        // deviceScale tells WebKit the CSS px → physical px ratio.
        // This makes 1 CSS pixel = 1 logical pixel regardless of monitor DPI.
        c.ulViewConfigSetInitialDeviceScale(view_cfg, dpi_scale);

        // View is created with physical pixel dimensions — WebKit handles layout internally
        const view = c.ulCreateView(renderer, actual_w, actual_h, view_cfg, null);
        if (view == null) {
            c.ulDestroyRenderer(renderer);
            _ = c.DestroyWindow(hwnd);
            return error.ViewCreationFailed;
        }

        const self = try allocator.create(UltralightBridge);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator  = allocator,
            .width      = actual_w,
            .height     = actual_h,
            .dpi_scale  = dpi_scale,
            .logical_w  = width,
            .logical_h  = height,
            .renderer   = renderer,
            .view       = view,
            .hwnd       = hwnd,
            .update_counter = 0,
            .config     = cfg,
            .last_app_mtime = 0,
            .is_running = true,
        };

        // Attach self pointer to HWND user data for WndProc
        _ = c.SetWindowLongPtrA(hwnd, c.GWLP_USERDATA, @intCast(@intFromPtr(self)));

        c.ulViewSetWindowObjectReadyCallback(view, onWindowObjectReady, @ptrCast(self));
        c.ulViewSetDOMReadyCallback(view, onDOMReady, @ptrCast(self));
        c.ulViewSetChangeCursorCallback(view, onChangeCursor, @ptrCast(self));
        c.ulViewSetAddConsoleMessageCallback(view, onAddConsoleMessage, @ptrCast(self));
        c.ulViewFocus(view);

        _ = c.ShowWindow(hwnd, c.SW_SHOW);
        _ = c.UpdateWindow(hwnd);

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

    fn transpileModernJS(allocator: std.mem.Allocator, raw_js: []const u8) ![]u8 {
        return try allocator.dupe(u8, raw_js);
    }

    pub fn loadFile(self: *UltralightBridge, html_path: []const u8) !void {
        var p_buf: [1024]u8 = undefined;
        if (std.fmt.bufPrintZ(&p_buf, "[ENGINE] loadFile requested: {s}\n", .{html_path})) |z_str| {
            const lf = c.fopen("C:\\Users\\suman\\Downloads\\ZeroUI\\nanoshell_debug.log", "a");
            if (lf != null) {
                _ = c.fprintf(lf, "%s", z_str.ptr);
                _ = c.fflush(lf);
                _ = c.fclose(lf);
            }
        } else |_| {}
        // Resolve absolute executable directory
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

        // Search list: user specified html_path FIRST, followed by conventional fallbacks
        var sub_paths_list: [8][]const u8 = undefined;
        var sub_paths_count: usize = 0;

        if (html_path.len > 0) {
            sub_paths_list[sub_paths_count] = html_path;
            sub_paths_count += 1;
        }

        const defaults = [_][]const u8{
            "example_app/index.html",
            "app/index.html",
            "assets/index.html",
            "index.html",
        };
        for (defaults) |d| {
            sub_paths_list[sub_paths_count] = d;
            sub_paths_count += 1;
        }

        var html_bytes_opt: ?[]u8 = null;
        var resolved_sub_path: []const u8 = "";
        const search_dirs = [_][]const u8{ base_dir, parent_dir, "./" };

        outer: for (search_dirs) |search_dir| {
            for (sub_paths_list[0..sub_paths_count]) |sub| {
                var full_p_buf: [1024]u8 = undefined;
                const abs_path_res = if (search_dir.len > 0)
                    std.fmt.bufPrintZ(&full_p_buf, "{s}{s}", .{ search_dir, sub })
                else
                    std.fmt.bufPrintZ(&full_p_buf, "{s}", .{sub});

                if (abs_path_res) |abs_path| {
                    if (readFileBytes(self.allocator, abs_path.ptr)) |bytes| {
                        html_bytes_opt = bytes;
                        resolved_sub_path = sub;
                        base_dir = search_dir;
                        break :outer;
                    } else |_| {}
                } else |_| {}
            }
        }

        const html_bytes = html_bytes_opt orelse {
            std.log.err("UltralightBridge: Failed to locate HTML file '{s}' or index.html defaults", .{html_path});
            return;
        };
        defer self.allocator.free(html_bytes);

        // Extract directory folder of resolved HTML
        var app_folder: []const u8 = "";
        if (std.mem.lastIndexOfAny(u8, resolved_sub_path, "/\\")) |last_slash_idx| {
            app_folder = resolved_sub_path[0 .. last_slash_idx + 1];
        }

        // Dynamically locate styles.css
        var css_bytes_raw: ?[]u8 = null;
        var css_p_buf: [1024]u8 = undefined;
        if (std.fmt.bufPrintZ(&css_p_buf, "{s}{s}styles.css", .{ base_dir, app_folder })) |abs_path| {
            css_bytes_raw = readFileBytes(self.allocator, abs_path.ptr) catch null;
        } else |_| {}
        defer if (css_bytes_raw) |cb| self.allocator.free(cb);

        const css_bytes = if (css_bytes_raw) |cb| processCSSDynamically(self.allocator, cb) catch null else null;
        defer if (css_bytes) |cb| self.allocator.free(cb);

        // Dynamically locate app.js
        var js_bytes: ?[]u8 = null;
        var js_p_buf: [1024]u8 = undefined;
        if (std.fmt.bufPrintZ(&js_p_buf, "{s}{s}app.js", .{ base_dir, app_folder })) |abs_path| {
            js_bytes = readFileBytes(self.allocator, abs_path.ptr) catch null;
        } else |_| {}
        defer if (js_bytes) |jb| self.allocator.free(jb);

        const js_bytes_transpiled = if (js_bytes) |jb| transpileModernJS(self.allocator, jb) catch null else null;
        defer if (js_bytes_transpiled) |jbt| self.allocator.free(jbt);
        const final_js_bytes = if (js_bytes_transpiled) |jbt| jbt else js_bytes;

        var html_working = try self.allocator.dupe(u8, html_bytes);
        defer self.allocator.free(html_working);

        if (css_bytes) |cb| {
            const head_close = "</head>";
            if (std.mem.indexOf(u8, html_working, head_close)) |h_close_idx| {
                const style_tag = try std.fmt.allocPrint(self.allocator, "<style>\n{s}\n</style>\n</head>", .{cb});
                defer self.allocator.free(style_tag);
                const p1 = html_working[0..h_close_idx];
                const p2 = html_working[h_close_idx + head_close.len ..];
                const new_html = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ p1, style_tag, p2 });
                self.allocator.free(html_working);
                html_working = new_html;
            }
        }

        if (final_js_bytes) |jb| {
            const body_close = "</body>";
            if (std.mem.indexOf(u8, html_working, body_close)) |b_close_idx| {
                const script_tag = try std.fmt.allocPrint(self.allocator, "<script>\n{s}\n</script>\n</body>", .{jb});
                defer self.allocator.free(script_tag);
                const p1 = html_working[0..b_close_idx];
                const p2 = html_working[b_close_idx + body_close.len ..];
                const new_html = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ p1, script_tag, p2 });
                self.allocator.free(html_working);
                html_working = new_html;
            }
        }

        const html_str = c.ulCreateStringUTF8(html_working.ptr, html_working.len);
        defer c.ulDestroyString(html_str);

        c.ulViewLoadHTML(self.view, html_str);
        self.bindNativeAPIs();
        std.log.info("UltralightBridge: Loaded HTML successfully ({d} bytes)!", .{html_working.len});
    }

    pub fn run(self: *UltralightBridge) void {
        var msg: c.MSG = undefined;
        self.is_running = true;

        while (self.is_running) {
            while (c.PeekMessageA(&msg, null, 0, 0, c.PM_REMOVE) != 0) {
                if (msg.message == c.WM_QUIT) {
                    self.is_running = false;
                    break;
                }
                _ = c.TranslateMessage(&msg);
                _ = c.DispatchMessageA(&msg);
            }

            if (!self.is_running) break;

            c.ulUpdate(self.renderer);

            self.tickUpdate();

            if (c.IsIconic(self.hwnd) == 0 and c.IsWindowVisible(self.hwnd) != 0) {
                c.ulRender(self.renderer);

                const hdc = c.GetDC(self.hwnd);
                if (hdc != null) {
                    self.paintToHDC(hdc);
                    _ = c.ReleaseDC(self.hwnd, hdc);
                }
            }

            c.Sleep(8);
        }
    }

    pub fn deinit(self: *UltralightBridge) void {
        _ = c.DestroyWindow(self.hwnd);
        c.ulDestroyView(self.view);
        c.ulDestroyRenderer(self.renderer);
        self.allocator.destroy(self);
    }
};
