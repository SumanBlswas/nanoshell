const std = @import("std");

pub const ZeroAllocator = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init() ZeroAllocator {
        return .{
            .arena = std.heap.ArenaAllocator.init(std.heap.c_allocator),
        };
    }

    pub fn deinit(self: *ZeroAllocator) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *ZeroAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }
};
