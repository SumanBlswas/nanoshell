const std = @import("std");
const qjs = @import("quickjs_core.zig").qjs;
const taffy = @import("../core/taffy_bindings.zig");
const style_parser = @import("style_parser.zig");

pub const DomNode = struct {
    tag_name: []const u8,
    taffy_node_id: u64,
    style: taffy.c.CTaffyStyle,
    parent: ?*DomNode,
    children: std.ArrayList(*DomNode),
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, tag_name: []const u8, taffy_tree: *taffy.TaffyTreeWrapper) !*DomNode {
        const node = try allocator.create(DomNode);
        errdefer allocator.destroy(node);

        var initial_style = std.mem.zeroes(taffy.c.CTaffyStyle);
        initial_style.display = taffy.c.TAFFY_DISPLAY_FLEX;
        initial_style.flex_direction = taffy.c.TAFFY_FLEX_DIRECTION_COLUMN;

        const node_id = try taffy_tree.createNode(&initial_style);

        node.* = .{
            .tag_name = try allocator.dupe(u8, tag_name),
            .taffy_node_id = node_id,
            .style = initial_style,
            .parent = null,
            .children = std.ArrayList(*DomNode).empty,
            .allocator = allocator,
        };

        return node;
    }

    pub fn destroy(self: *DomNode, taffy_tree: *taffy.TaffyTreeWrapper) void {
        _ = taffy_tree.freeNode(self.taffy_node_id) catch {};
        for (self.children.items) |child| {
            child.destroy(taffy_tree);
        }
        self.children.deinit(self.allocator);
        self.allocator.free(self.tag_name);
        self.allocator.destroy(self);
    }

    pub fn appendChild(self: *DomNode, child: *DomNode, taffy_tree: *taffy.TaffyTreeWrapper) !void {
        child.parent = self;
        try self.children.append(self.allocator, child);
        try taffy_tree.addChild(self.taffy_node_id, child.taffy_node_id);
    }

    pub fn setStyleProperty(self: *DomNode, prop: []const u8, val: []const u8, taffy_tree: *taffy.TaffyTreeWrapper) !void {
        style_parser.applyCssProperty(&self.style, prop, val);
        try taffy_tree.setStyle(self.taffy_node_id, &self.style);
    }
};

pub const DomDocument = struct {
    allocator: std.mem.Allocator,
    taffy_tree: *taffy.TaffyTreeWrapper,
    root_node: *DomNode,

    pub fn init(allocator: std.mem.Allocator, taffy_tree: *taffy.TaffyTreeWrapper) !*DomDocument {
        const doc = try allocator.create(DomDocument);
        errdefer allocator.destroy(doc);

        const root = try DomNode.create(allocator, "body", taffy_tree);

        doc.* = .{
            .allocator = allocator,
            .taffy_tree = taffy_tree,
            .root_node = root,
        };

        return doc;
    }

    pub fn deinit(self: *DomDocument) void {
        self.root_node.destroy(self.taffy_tree);
        self.allocator.destroy(self);
    }

    pub fn createElement(self: *DomDocument, tag_name: []const u8) !*DomNode {
        return DomNode.create(self.allocator, tag_name, self.taffy_tree);
    }
};
