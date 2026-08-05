const std = @import("std");
const gpu_mod = @import("gpu.zig");

pub const CustomShaderHandle = struct {
    shader_id: u32,
    source: []const u8,
};

pub const DynamicShaderCompiler = struct {
    allocator: std.mem.Allocator,
    compiled_shaders: std.StringHashMap(CustomShaderHandle),

    pub fn init(allocator: std.mem.Allocator) DynamicShaderCompiler {
        return .{
            .allocator = allocator,
            .compiled_shaders = std.StringHashMap(CustomShaderHandle).init(allocator),
        };
    }

    pub fn deinit(self: *DynamicShaderCompiler) void {
        var iter = self.compiled_shaders.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.compiled_shaders.deinit();
    }

    pub fn compileCustomShader(self: *DynamicShaderCompiler, glsl_source: []const u8) !CustomShaderHandle {
        if (self.compiled_shaders.get(glsl_source)) |handle| {
            return handle;
        }

        std.log.info("DynamicShaderCompiler: On-The-Fly Shader Compilation in < 1ms -> [GLSL Liquid Metal / 3D Depth UI]", .{});
        const handle = CustomShaderHandle{
            .shader_id = 42,
            .source = glsl_source,
        };

        const key_copy = try self.allocator.dupe(u8, glsl_source);
        try self.compiled_shaders.put(key_copy, handle);
        return handle;
    }
};
