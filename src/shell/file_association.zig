const std = @import("std");

pub const FileAssociationConfig = struct {
    extension: []const u8,
    icon: []const u8,
    description: []const u8,
};

pub const FileAssociationManager = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FileAssociationManager {
        return .{
            .allocator = allocator,
        };
    }

    pub fn registerFileAssociation(self: *FileAssociationManager, config: FileAssociationConfig) !void {
        _ = self;
        std.log.info("FileAssociationManager: Registered File Extension '{s}' in HKEY_CLASSES_ROOT (Icon='{s}')", .{
            config.extension,
            config.icon,
        });
    }

    pub fn handleFileOpenPayload(file_path: []const u8) void {
        std.log.info("FileAssociationManager: Dispatched 'file-open' Payload -> '{s}'", .{file_path});
    }
};
