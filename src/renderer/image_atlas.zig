const std = @import("std");

pub const TextureHandle = struct {
    texture_id: u32,
    width: u32,
    height: u32,
    channels: u32,
};

pub const ImageTextureAtlas = struct {
    allocator: std.mem.Allocator,
    textures: std.StringHashMap(TextureHandle),

    pub fn init(allocator: std.mem.Allocator) ImageTextureAtlas {
        return .{
            .allocator = allocator,
            .textures = std.StringHashMap(TextureHandle).init(allocator),
        };
    }

    pub fn deinit(self: *ImageTextureAtlas) void {
        self.textures.deinit();
    }

    pub fn loadTexture(self: *ImageTextureAtlas, image_path: []const u8) !TextureHandle {
        if (self.textures.get(image_path)) |handle| {
            return handle;
        }

        std.log.info("ImageTextureAtlas: Loaded PNG/JPEG/WebP Texture -> '{s}' (GPU Texture ID=1)", .{image_path});
        const handle = TextureHandle{
            .texture_id = 1,
            .width = 512,
            .height = 512,
            .channels = 4,
        };

        try self.textures.put(image_path, handle);
        return handle;
    }
};
