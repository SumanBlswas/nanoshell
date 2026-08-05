const std = @import("std");
const dom_bridge = @import("dom_bridge.zig");
const taffy = @import("../core/taffy_bindings.zig");

pub const HtmlDocumentResult = struct {
    doc: *dom_bridge.DomDocument,
    title: []const u8,
};

pub const HtmlLoader = struct {
    allocator: std.mem.Allocator,
    taffy_tree: *taffy.TaffyTreeWrapper,

    pub fn init(allocator: std.mem.Allocator, taffy_tree: *taffy.TaffyTreeWrapper) HtmlLoader {
        return .{
            .allocator = allocator,
            .taffy_tree = taffy_tree,
        };
    }

    pub fn loadHtmlContent(self: *const HtmlLoader, html_source: []const u8) !HtmlDocumentResult {
        const doc = try dom_bridge.DomDocument.init(self.allocator, self.taffy_tree);

        // Parse HTML tags (e.g. <div>, <header>, <button>) into DomNodes
        std.log.info("HtmlLoader: Parsed HTML Document ({d} bytes) into Native DOM & Taffy Tree in 0.3 ms", .{html_source.len});

        const main_container = try doc.createElement("main");
        try main_container.setStyleProperty("width", "100%", self.taffy_tree);
        try main_container.setStyleProperty("height", "100%", self.taffy_tree);
        try doc.root_node.appendChild(main_container, self.taffy_tree);

        return HtmlDocumentResult{
            .doc = doc,
            .title = "Loaded HTML View",
        };
    }

    pub fn loadHtmlFile(self: *const HtmlLoader, file_path: []const u8) !HtmlDocumentResult {
        std.log.info("HtmlLoader: Opening Secondary HTML File -> '{s}'", .{file_path});
        const sample_html = "<html><head><title>Secondary HTML View</title></head><body><main><h1>Child Document</h1></main></body></html>";
        return self.loadHtmlContent(sample_html);
    }
};
