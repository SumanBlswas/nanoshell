const std = @import("std");
const taffy = @import("taffy_bindings.zig");

// Direct, Type-Safe Win32 FFI Bindings (Zero Header Macros Overhead)
pub const win = struct {
    pub const HANDLE = ?*anyopaque;
    pub const HWND = HANDLE;
    pub const HINSTANCE = HANDLE;
    pub const HICON = HANDLE;
    pub const HCURSOR = HANDLE;
    pub const HBRUSH = HANDLE;
    pub const HMENU = HANDLE;
    pub const LPARAM = isize;
    pub const WPARAM = usize;
    pub const LRESULT = isize;
    pub const DWORD = u32;
    pub const UINT = u32;
    pub const BOOL = i32;
    pub const ATOM = u16;

    pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

    pub const WNDCLASSEXW = extern struct {
        cbSize: UINT = @sizeOf(WNDCLASSEXW),
        style: UINT = 0,
        lpfnWndProc: WNDPROC,
        cbClsExtra: i32 = 0,
        cbWndExtra: i32 = 0,
        hInstance: HINSTANCE = null,
        hIcon: HICON = null,
        hCursor: HCURSOR = null,
        hbrBackground: HBRUSH = null,
        lpszMenuName: ?[*:0]const u16 = null,
        lpszClassName: [*:0]const u16,
        hIconSm: HICON = null,
    };

    pub const POINT = extern struct {
        x: i32,
        y: i32,
    };

    pub const MSG = extern struct {
        hwnd: HWND,
        message: UINT,
        wParam: WPARAM,
        lParam: LPARAM,
        time: DWORD,
        pt: POINT,
        lPrivate: DWORD,
    };

    // Constants
    pub const CS_VREDRAW: UINT = 0x0001;
    pub const CS_HREDRAW: UINT = 0x0002;
    pub const CS_OWNDC: UINT = 0x0020;

    pub const BITMAPINFOHEADER = extern struct {
        biSize: DWORD = @sizeOf(BITMAPINFOHEADER),
        biWidth: i32 = 0,
        biHeight: i32 = 0,
        biPlanes: u16 = 1,
        biBitCount: u16 = 32,
        biCompression: DWORD = 0,
        biSizeImage: DWORD = 0,
        biXPelsPerMeter: i32 = 0,
        biYPelsPerMeter: i32 = 0,
        biClrUsed: DWORD = 0,
        biClrImportant: DWORD = 0,
    };

    pub const RGBQUAD = extern struct {
        rgbBlue: u8 = 0,
        rgbGreen: u8 = 0,
        rgbRed: u8 = 0,
        rgbReserved: u8 = 0,
    };

    pub const BITMAPINFO = extern struct {
        bmiHeader: BITMAPINFOHEADER = .{},
        bmiColors: [1]RGBQUAD = .{.{}},
    };

    pub const BI_RGB: DWORD = 0;
    pub const DIB_RGB_COLORS: UINT = 0;
    pub const SRCCOPY: DWORD = 0x00CC0020;

    pub extern "gdi32" fn StretchDIBits(
        hdc: HANDLE,
        xDest: i32,
        yDest: i32,
        DestWidth: i32,
        DestHeight: i32,
        xSrc: i32,
        ySrc: i32,
        SrcWidth: i32,
        SrcHeight: i32,
        lpBits: ?*const anyopaque,
        lpbmi: *const BITMAPINFO,
        iUsage: UINT,
        rop: DWORD,
    ) callconv(.winapi) i32;

    pub const WS_OVERLAPPED: DWORD = 0x00000000;
    pub const WS_CAPTION: DWORD = 0x00C00000;
    pub const WS_SYSMENU: DWORD = 0x00080000;
    pub const WS_THICKFRAME: DWORD = 0x00040000;
    pub const WS_MINIMIZEBOX: DWORD = 0x00020000;
    pub const WS_MAXIMIZEBOX: DWORD = 0x00010000;
    pub const WS_OVERLAPPEDWINDOW: DWORD = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
    pub const WS_VISIBLE: DWORD = 0x10000000;

    pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

    pub const SW_SHOW: i32 = 5;

    pub const WM_DESTROY: UINT = 0x0002;
    pub const WM_SIZE: UINT = 0x0005;
    pub const WM_PAINT: UINT = 0x000F;
    pub const WM_QUIT: UINT = 0x0012;
    pub const WM_ERASEBKGND: UINT = 0x0014;
    pub const WM_DPICHANGED: UINT = 0x02E0;

    pub const PM_REMOVE: UINT = 0x0001;
    pub const GWLP_USERDATA: i32 = -21;

    pub const BLACK_BRUSH: i32 = 4;
    pub const IDC_ARROW: [*:0]const u16 = @ptrFromInt(32512);

    // Win32 System API Functions
    pub extern "user32" fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) callconv(.winapi) ATOM;
    pub extern "user32" fn CreateWindowExW(
        dwExStyle: DWORD,
        lpClassName: [*:0]const u16,
        lpWindowName: [*:0]const u16,
        dwStyle: DWORD,
        X: i32,
        Y: i32,
        nWidth: i32,
        nHeight: i32,
        hWndParent: HWND,
        hMenu: HMENU,
        hInstance: HINSTANCE,
        lpParam: ?*anyopaque,
    ) callconv(.winapi) HWND;

    pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.winapi) BOOL;
    pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
    pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
    pub extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
    pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
    pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
    pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.winapi) void;
    pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
    pub extern "user32" fn LoadCursorW(hInstance: HINSTANCE, lpCursorName: [*:0]const u16) callconv(.winapi) HCURSOR;
    pub extern "user32" fn GetDpiForWindow(hwnd: HWND) callconv(.winapi) UINT;

    pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.winapi) LONG_PTR;
    pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.winapi) LONG_PTR;
    pub extern "gdi32" fn GetStockObject(i: i32) callconv(.winapi) HBRUSH;
    pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) HINSTANCE;
    pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;

    pub const HDC = HANDLE;
    pub const HGLRC = HANDLE;
    pub const WORD = u16;
    pub const BYTE = u8;

    pub const PIXELFORMATDESCRIPTOR = extern struct {
        nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
        nVersion: WORD = 1,
        dwFlags: DWORD = 0x00000025, // PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
        iPixelType: BYTE = 0,
        cColorBits: BYTE = 32,
        cRedBits: BYTE = 0,
        cRedShift: BYTE = 0,
        cGreenBits: BYTE = 0,
        cGreenShift: BYTE = 0,
        cBlueBits: BYTE = 0,
        cBlueShift: BYTE = 0,
        cAlphaBits: BYTE = 0,
        cAlphaShift: BYTE = 0,
        cAccumBits: BYTE = 0,
        cAccumRedBits: BYTE = 0,
        cAccumGreenBits: BYTE = 0,
        cAccumBlueBits: BYTE = 0,
        cAccumAlphaBits: BYTE = 0,
        cDepthBits: BYTE = 24,
        cStencilBits: BYTE = 8,
        cAuxBuffers: BYTE = 0,
        iLayerType: BYTE = 0,
        bReserved: BYTE = 0,
        dwLayerMask: DWORD = 0,
        dwVisibleMask: DWORD = 0,
        dwDamageMask: DWORD = 0,
    };

    pub extern "user32" fn GetDC(hWnd: HWND) callconv(.winapi) HDC;
    pub extern "user32" fn ReleaseDC(hWnd: HWND, hDC: HDC) callconv(.winapi) i32;
    pub extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) i32;
    pub extern "gdi32" fn SetPixelFormat(hdc: HDC, format: i32, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) BOOL;
    pub extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) BOOL;
    pub extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) HGLRC;
    pub extern "opengl32" fn wglMakeCurrent(hdc: HDC, hglrc: HGLRC) callconv(.winapi) BOOL;
    pub extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.winapi) BOOL;
    pub extern "opengl32" fn wglGetCurrentDC() callconv(.winapi) HDC;

    pub const TRANSPARENT: i32 = 1;
    pub const FW_BOLD: i32 = 700;
    pub const DEFAULT_CHARSET: DWORD = 1;
    pub const OUT_DEFAULT_PRECIS: DWORD = 0;
    pub const CLIP_DEFAULT_PRECIS: DWORD = 0;
    pub const CLEARTYPE_QUALITY: DWORD = 5;
    pub const DEFAULT_PITCH: DWORD = 0;
    pub const FF_DONTCARE: DWORD = 0;
    pub const DT_LEFT: UINT = 0x0000;
    pub const DT_NOCLIP: UINT = 0x0100;

    pub const RECT = extern struct {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    };

    pub extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.winapi) i32;
    pub extern "gdi32" fn SetTextColor(hdc: HDC, color: DWORD) callconv(.winapi) DWORD;
    pub extern "gdi32" fn CreateFontW(
        cHeight: i32,
        cWidth: i32,
        cEscapement: i32,
        cOrientation: i32,
        cWeight: i32,
        bItalic: DWORD,
        bUnderline: DWORD,
        bStrikeOut: DWORD,
        iCharSet: DWORD,
        iOutPrecision: DWORD,
        iClipPrecision: DWORD,
        iQuality: DWORD,
        iPitchAndFamily: DWORD,
        pszFaceName: ?[*:0]const u16,
    ) callconv(.winapi) HANDLE;
    pub extern "gdi32" fn SelectObject(hdc: HDC, h: HANDLE) callconv(.winapi) HANDLE;
    pub extern "gdi32" fn DeleteObject(ho: HANDLE) callconv(.winapi) BOOL;
    pub extern "user32" fn DrawTextW(hdc: HDC, lpchText: [*:0]const u16, cchText: i32, lprc: *RECT, format: UINT) callconv(.winapi) i32;

    pub const LONG_PTR = isize;
};

pub const WindowConfig = struct {
    title: [*:0]const u8 = "ZeroUI Native Engine",
    width: i32 = 1280,
    height: i32 = 720,
    resizable: bool = true,
};

pub const Window = struct {
    hwnd: win.HWND,
    hdc: win.HDC,
    hglrc: win.HGLRC,
    width: u32,
    height: u32,
    dpi: u32,
    should_close: bool,
    taffy_tree: ?*taffy.TaffyTreeWrapper,
    root_layout_node: u64,

    pub fn create(config: WindowConfig, taffy_tree: ?*taffy.TaffyTreeWrapper, root_node: u64) !*Window {
        const allocator = std.heap.c_allocator;
        const window_ptr = try allocator.create(Window);
        errdefer allocator.destroy(window_ptr);

        const h_instance = win.GetModuleHandleW(null);
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("ZeroUI_WindowClass");

        var wnd_class = std.mem.zeroes(win.WNDCLASSEXW);
        wnd_class.cbSize = @sizeOf(win.WNDCLASSEXW);
        wnd_class.style = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC;
        wnd_class.lpfnWndProc = WindowProc;
        wnd_class.hInstance = h_instance;
        wnd_class.hCursor = win.LoadCursorW(null, win.IDC_ARROW);
        wnd_class.hbrBackground = win.GetStockObject(win.BLACK_BRUSH);
        wnd_class.lpszClassName = class_name;

        _ = win.RegisterClassExW(&wnd_class);

        var title_buf: [256]u16 = undefined;
        const title_len = try std.unicode.utf8ToUtf16Le(&title_buf, std.mem.span(config.title));
        title_buf[title_len] = 0;

        const style_flags: win.DWORD = if (config.resizable)
            win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE
        else
            win.WS_OVERLAPPED | win.WS_CAPTION | win.WS_SYSMENU | win.WS_MINIMIZEBOX | win.WS_VISIBLE;

        const hwnd = win.CreateWindowExW(
            0,
            class_name,
            @ptrCast(&title_buf),
            style_flags,
            win.CW_USEDEFAULT,
            win.CW_USEDEFAULT,
            config.width,
            config.height,
            null,
            null,
            h_instance,
            window_ptr,
        );

        if (hwnd == null) {
            return error.WindowCreationFailed;
        }

        const hdc = win.GetDC(hwnd);
        var pfd = std.mem.zeroes(win.PIXELFORMATDESCRIPTOR);
        pfd.nSize = @sizeOf(win.PIXELFORMATDESCRIPTOR);
        pfd.nVersion = 1;
        pfd.dwFlags = 0x00000025; // PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
        pfd.iPixelType = 0;
        pfd.cColorBits = 32;
        pfd.cDepthBits = 24;
        pfd.cStencilBits = 8;

        const pf = win.ChoosePixelFormat(hdc, &pfd);
        _ = win.SetPixelFormat(hdc, pf, &pfd);
        const hglrc = win.wglCreateContext(hdc);
        _ = win.wglMakeCurrent(hdc, hglrc);

        window_ptr.* = .{
            .hwnd = hwnd,
            .hdc = hdc,
            .hglrc = hglrc,
            .width = @intCast(config.width),
            .height = @intCast(config.height),
            .dpi = win.GetDpiForWindow(hwnd),
            .should_close = false,
            .taffy_tree = taffy_tree,
            .root_layout_node = root_node,
        };

        _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, @bitCast(@intFromPtr(window_ptr)));

        _ = win.ShowWindow(hwnd, win.SW_SHOW);
        _ = win.UpdateWindow(hwnd);

        // Initial Layout Compute
        if (taffy_tree) |tree| {
            if (root_node != 0) {
                tree.computeLayout(root_node, @floatFromInt(config.width), @floatFromInt(config.height)) catch {};
            }
        }

        return window_ptr;
    }

    pub fn swapBuffers(self: *Window) void {
        _ = win.SwapBuffers(self.hdc);
    }

    pub fn destroy(self: *Window) void {
        _ = win.wglMakeCurrent(null, null);
        if (self.hglrc != null) {
            _ = win.wglDeleteContext(self.hglrc);
        }
        if (self.hdc != null and self.hwnd != null) {
            _ = win.ReleaseDC(self.hwnd, self.hdc);
        }
        if (self.hwnd != null) {
            _ = win.DestroyWindow(self.hwnd);
        }
        std.heap.c_allocator.destroy(self);
    }

    pub fn pollEvents(self: *Window) bool {
        var msg: win.MSG = std.mem.zeroes(win.MSG);
        while (win.PeekMessageW(&msg, null, 0, 0, win.PM_REMOVE) != 0) {
            if (msg.message == win.WM_QUIT) {
                self.should_close = true;
                return false;
            }
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageW(&msg);
        }
        return !self.should_close;
    }

    pub fn onResize(self: *Window, new_width: u32, new_height: u32) void {
        self.width = new_width;
        self.height = new_height;
        if (self.taffy_tree) |tree| {
            if (self.root_layout_node != 0) {
                tree.computeLayout(self.root_layout_node, @floatFromInt(new_width), @floatFromInt(new_height)) catch {};
            }
        }
    }
};

pub fn WindowProc(hwnd: win.HWND, uMsg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(.winapi) win.LRESULT {
    const ptr = win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA);
    const window: ?*Window = if (ptr != 0) @ptrFromInt(@as(usize, @bitCast(ptr))) else null;

    switch (uMsg) {
        win.WM_SIZE => {
            const width: u32 = @intCast(lParam & 0xFFFF);
            const height: u32 = @intCast((lParam >> 16) & 0xFFFF);
            if (window) |w| {
                w.onResize(width, height);
            }
            return 0;
        },
        win.WM_DPICHANGED => {
            const new_dpi: u32 = @intCast(wParam & 0xFFFF);
            if (window) |w| {
                w.dpi = new_dpi;
            }
            return 0;
        },
        win.WM_DESTROY => {
            if (window) |w| {
                w.should_close = true;
            }
            win.PostQuitMessage(0);
            return 0;
        },
        win.WM_ERASEBKGND => {
            return 1; // Prevent flicker during resize
        },
        else => return win.DefWindowProcW(hwnd, uMsg, wParam, lParam),
    }
}
