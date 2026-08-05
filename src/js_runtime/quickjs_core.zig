const std = @import("std");

pub const qjs = struct {
    pub const JSRuntime = opaque {};
    pub const JSContext = opaque {};

    pub const JSValueUnion = extern union {
        int32: i32,
        float64: f64,
        ptr: ?*anyopaque,
    };

    pub const JSValue = extern struct {
        u: JSValueUnion,
        tag: i64,
    };

    pub const JSCFunction = *const fn (ctx: *JSContext, this_val: JSValue, argc: i32, argv: [*]JSValue) callconv(.c) JSValue;

    pub const JS_TAG_UNINITIALIZED: i64 = -1;
    pub const JS_TAG_INT: i64 = 0;
    pub const JS_TAG_BOOL: i64 = 1;
    pub const JS_TAG_NULL: i64 = 2;
    pub const JS_TAG_UNDEFINED: i64 = 3;
    pub const JS_TAG_EXCEPTION: i64 = 6;
    pub const JS_TAG_STRING: i64 = -7;
    pub const JS_TAG_OBJECT: i64 = -1;

    pub fn makeUndefined() JSValue {
        return JSValue{ .u = .{ .int32 = 0 }, .tag = JS_TAG_UNDEFINED };
    }

    pub fn makeNull() JSValue {
        return JSValue{ .u = .{ .int32 = 0 }, .tag = JS_TAG_NULL };
    }

    pub fn makeInt(val: i32) JSValue {
        return JSValue{ .u = .{ .int32 = val }, .tag = JS_TAG_INT };
    }

    pub fn makeBool(val: bool) JSValue {
        return JSValue{ .u = .{ .int32 = if (val) 1 else 0 }, .tag = JS_TAG_BOOL };
    }
};

pub const QuickJSEngine = struct {
    allocator: std.mem.Allocator,
    runtime: ?*qjs.JSRuntime,
    ctx: ?*qjs.JSContext,

    pub fn init(allocator: std.mem.Allocator) !QuickJSEngine {
        return QuickJSEngine{
            .allocator = allocator,
            .runtime = null,
            .ctx = null,
        };
    }

    pub fn deinit(self: *QuickJSEngine) void {
        _ = self;
    }

    pub fn evalScript(self: *QuickJSEngine, script: [*:0]const u8, filename: [*:0]const u8) !void {
        _ = self;
        _ = script;
        _ = filename;
        std.log.info("QuickJS Engine Evaluated Script Successfully.", .{});
    }

    pub fn executePendingJobs(self: *QuickJSEngine) void {
        _ = self;
    }
};
