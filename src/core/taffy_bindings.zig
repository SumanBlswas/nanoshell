const std = @import("std");

pub const c = @cImport({
    @cInclude("taffy_c.h");
});

pub const TaffyError = error{
    NullPointer,
    InvalidNode,
    Panic,
    LayoutFailed,
    Unknown,
};

fn checkResult(res: c_int) TaffyError!void {
    switch (res) {
        c.TAFFY_RESULT_OK => return,
        c.TAFFY_RESULT_ERROR_NULL_POINTER => return TaffyError.NullPointer,
        c.TAFFY_RESULT_ERROR_INVALID_NODE => return TaffyError.InvalidNode,
        c.TAFFY_RESULT_ERROR_PANIC => return TaffyError.Panic,
        c.TAFFY_RESULT_ERROR_LAYOUT_FAILED => return TaffyError.LayoutFailed,
        else => return TaffyError.Unknown,
    }
}

pub const TaffyTreeWrapper = struct {
    handle: *c.CTaffyTree,

    pub fn init() TaffyError!TaffyTreeWrapper {
        const ptr = c.taffy_tree_create();
        if (ptr == null) return TaffyError.NullPointer;
        return TaffyTreeWrapper{ .handle = ptr.? };
    }

    pub fn deinit(self: *TaffyTreeWrapper) void {
        c.taffy_tree_free(self.handle);
    }

    pub fn createNode(self: *TaffyTreeWrapper, style: *const c.CTaffyStyle) TaffyError!u64 {
        const id = c.taffy_node_create(self.handle, style);
        if (id == 0) return TaffyError.InvalidNode;
        return id;
    }

    pub fn freeNode(self: *TaffyTreeWrapper, node: u64) TaffyError!void {
        try checkResult(c.taffy_node_free(self.handle, node));
    }

    pub fn addChild(self: *TaffyTreeWrapper, parent: u64, child: u64) TaffyError!void {
        try checkResult(c.taffy_node_add_child(self.handle, parent, child));
    }

    pub fn insertChildAtIndex(self: *TaffyTreeWrapper, parent: u64, index: u32, child: u64) TaffyError!void {
        try checkResult(c.taffy_node_insert_child_at_index(self.handle, parent, index, child));
    }

    pub fn removeChild(self: *TaffyTreeWrapper, parent: u64, child: u64) TaffyError!void {
        try checkResult(c.taffy_node_remove_child(self.handle, parent, child));
    }

    pub fn removeChildAtIndex(self: *TaffyTreeWrapper, parent: u64, index: u32) TaffyError!void {
        try checkResult(c.taffy_node_remove_child_at_index(self.handle, parent, index));
    }

    pub fn clearChildren(self: *TaffyTreeWrapper, parent: u64) TaffyError!void {
        try checkResult(c.taffy_node_clear_children(self.handle, parent));
    }

    pub fn setStyle(self: *TaffyTreeWrapper, node: u64, style: *const c.CTaffyStyle) TaffyError!void {
        try checkResult(c.taffy_node_set_style(self.handle, node, style));
    }

    pub fn computeLayout(self: *TaffyTreeWrapper, root: u64, width: f32, height: f32) TaffyError!void {
        try checkResult(c.taffy_compute_layout(self.handle, root, width, height));
    }

    pub fn getLayout(self: *TaffyTreeWrapper, node: u64) TaffyError!c.CTaffyLayout {
        var layout: c.CTaffyLayout = std.mem.zeroes(c.CTaffyLayout);
        try checkResult(c.taffy_get_layout(self.handle, node, &layout));
        return layout;
    }

    pub fn markDirty(self: *TaffyTreeWrapper, node: u64) TaffyError!void {
        try checkResult(c.taffy_mark_dirty(self.handle, node));
    }
};
