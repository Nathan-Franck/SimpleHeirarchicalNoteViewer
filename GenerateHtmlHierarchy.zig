const std = @import("std");
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const Node = struct {
    content: []const u8,
    children: ArrayList(*Node),
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    lines: ArrayList([]const u8),
};

const FONT_SIZE: f32 = 14;
const CHAR_WIDTH: f32 = FONT_SIZE * 0.6; // Approximation for monospace
const LINE_HEIGHT: f32 = FONT_SIZE * 1.2;
const MAX_WIDTH: f32 = 250;
const PADDING: f32 = 10;

fn createNode(allocator: std.mem.Allocator, content: []const u8) !*Node {
    const node = try allocator.create(Node);
    node.* = Node{
        .content = content,
        .children = ArrayList(*Node).init(allocator),
        .lines = ArrayList([]const u8).init(allocator),
    };
    return node;
}

fn wrapText(allocator: std.mem.Allocator, text: []const u8, max_width: f32) !ArrayList([]const u8) {
    var lines = ArrayList([]const u8).init(allocator);
    var words = std.mem.splitScalar(u8, text, ' ');
    var line = ArrayList(u8).init(allocator);
    var line_width: f32 = 0;

    while (words.next()) |word| {
        const word_width = @as(f32, @floatFromInt(word.len)) * CHAR_WIDTH;
        if (line_width + word_width > max_width - 2 * PADDING) {
            if (line.items.len > 0) {
                try lines.append(try line.toOwnedSlice());
                line = ArrayList(u8).init(allocator);
                line_width = 0;
            }
        }
        if (line.items.len > 0) {
            try line.append(' ');
            line_width += CHAR_WIDTH;
        }
        try line.appendSlice(word);
        line_width += word_width;
    }

    if (line.items.len > 0) {
        try lines.append(try line.toOwnedSlice());
    }

    return lines;
}

fn parseHierarchy(allocator: std.mem.Allocator, lines: []const []const u8) !*Node {
    const root = try createNode(allocator, "Root");
    var stack = ArrayList(*Node).init(allocator);
    try stack.append(root);

    for (lines) |line| {
        var indent: usize = 0;
        while (indent < line.len and line[indent] == ' ') : (indent += 1) {}
        const content = std.mem.trim(u8, line[indent..], " ");

        while (stack.items.len > indent / 2 + 1) {
            _ = stack.pop();
        }

        const node = try createNode(allocator, content);
        node.lines = try wrapText(allocator, content, MAX_WIDTH);
        node.width = MAX_WIDTH;
        node.height = @as(f32, @floatFromInt(node.lines.items.len)) * LINE_HEIGHT + 2 * PADDING;

        try stack.items[stack.items.len - 1].children.append(node);
        try stack.append(node);
    }

    return root;
}

fn layoutNodes(node: *Node, x: f32, y: f32, level: usize) void {
    const VERTICAL_GAP: f32 = 20;
    const HORIZONTAL_GAP: f32 = 40;

    node.x = x;
    node.y = y;

    var currentY = y; // + node.height + VERTICAL_GAP;
    for (node.children.items) |child| {
        layoutNodes(child, x + node.width + HORIZONTAL_GAP, currentY, level + 1);
        currentY += child.height + VERTICAL_GAP;
    }

    if (node.children.items.len > 0) {
        const totalHeight = currentY - y - VERTICAL_GAP;
        node.height = @max(node.height, totalHeight);
    }
}

fn generateSVG(allocator: std.mem.Allocator, root: *Node, height: f32) ![]const u8 {
    var svg = ArrayList(u8).init(allocator);
    const writer = svg.writer();

    try writer.writeAll(try std.fmt.allocPrint(allocator,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="{}">
        \\  <defs>
        // \\    <filter id="dropShadow" height="130%">
        // \\      <feGaussianBlur in="SourceAlpha" stdDeviation="3"/>
        // \\      <feOffset dx="2" dy="2" result="offsetblur"/>
        // \\      <feComponentTransfer>
        // \\        <feFuncA type="linear" slope="0.5"/>
        // \\      </feComponentTransfer>
        // \\      <feMerge>
        // \\        <feMergeNode/>
        // \\        <feMergeNode in="SourceGraphic"/>
        // \\      </feMerge>
        // \\    </filter>
        \\  </defs>
    , .{height}));

    try renderNode(writer, root);

    try writer.writeAll("</svg>");

    return svg.toOwnedSlice();
}

fn renderNode(writer: anytype, node: *Node) !void {
    // Draw connection lines to children
    for (node.children.items) |child| {
        try writer.print(
            \\  <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" stroke="#999" stroke-width="2"/>
        , .{
            node.x + node.width / 2, // Start from middle of parent
            node.y, // Start from top of parent
            child.x, // End at left side of child
            child.y + child.height / 2, // End at middle of child's left side
        });
        try renderNode(writer, child);
    }

    // Draw rounded rectangle
    try writer.print(
        \\  <rect x="{d}" y="{d}" width="{d}" height="{d}" rx="10" ry="10" fill="#f0f0f0" stroke="#333" stroke-width="2" filter="url(#dropShadow)"/>
    , .{ node.x, node.y, node.width, node.height });

    // Draw wrapped text
    for (node.lines.items, 0..) |line, i| {
        const text_y = node.y + PADDING + FONT_SIZE + @as(f32, @floatFromInt(i)) * LINE_HEIGHT;
        try writer.print(
            \\  <text x="{d}" y="{d}" font-family="Courier, monospace" font-size="{d}" fill="#333">{s}</text>
        , .{ node.x + PADDING, text_y, FONT_SIZE, line });
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const text =
        \\Fanciful Tasks
        \\  ⬜ Naturalistic Cat Rendering
        \\    ⬜ Naturalistic skybox rendering
        \\    ⬜ Raytrace against the skybox and the cat!
        \\      Could be a metal cat :)
        \\      🐛 ⬜ Raytracing on a reflection causes a crash - something with finding your own triangle and hitting it?
        \\  ⬜ Tree generation
        \\    Same algo as always :)
        \\    Preserve the connection data so I can start some
        \\    ⬜ Physics simulation!
        \\    ⬜ Make it look pretty!
        \\      ⬜ Textures
        \\      ⬜ Translucent lighting on leaves
        \\      ⬜ Subdiv enhancements to have simple branch smoothing
        \\        If subdividing a non-enclosed shape, don't freak out!
        \\        Edge sharpness?
        \\  ⬜ Forest Spawning
        \\    ✅ ⚠️ How would this relate to gameplay? What game would benefit from pretty forests?
        \\      Not a Multiplayer Deathmatch Shooter...
        \\        Would still make for great background elements and in-level small features...
        \\        Does that justify the effort to implement it?
        \\          Regardless, it's something I want to do, so there.
        \\      Maybe an Adventure Exploration Game
        \\        The Witness type?
        \\      Or a survival game!
        \\        I should just make Reign of Kings :)
        \\          Except I don't like playing Survival Games, so I don't think it's my thing... Maybe as a second project after a smaller first one
        \\      💡Yeah so I'm just making a forest sim, that's the whole thing!
        \\        Make it work in VR so it's an experience!
        \\        Can borrow a headset from Shawn to figure out if it's worth it before taking the plunge financially
        \\    ⬜ Take all the skillz and knowledge from my Codehatch job and just copy-paste into my code!
        \\      ⬜ Chunks of forest data (x, y, density)
        \\        Generate on the fly, on demand
        \\        Smaller chunks can depend on the data of larger chunks to show sticks around trees, hide grass under rocks etc.
        \\      ⬜❓️Sprites at a far distance - Generate billboards ahead of time
        \\      Models up close with varying LOD settings
        \\  ⬜ Tile-based sun shadows
        \\    Consider my thoughts on orthographic rendering as a starting point
        \\    Renderer can figure out what parts of the scene are actually moving and only update those parts of the shadow map
        \\    If the view moves around, just shift the shadow map and update the areas yet to be rendered
        \\    Area rendered should just center on camera position, don't consider the frustum!
        \\    Yeah it's more area, but once rendered initially, it's done, and no updates have to occur as long as the scene is still!
        \\    Need to ensure most objects don't animate constantly
        \\      Wind effects should have some threshold where no movement occurs, and select only some objects (high, in open areas)
    ;
    var linesIter = std.mem.splitScalar(u8, text, '\n');
    var lines = std.ArrayList([]const u8).init(allocator);
    while (linesIter.next()) |line|
        try lines.append(line);

    const root = try parseHierarchy(allocator, lines.items);
    layoutNodes(root, 10, 10, 0);

    const svg = try generateSVG(allocator, root, root.height);

    const html = try std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>Hierarchical Notes Visualization</title>
        \\    <style>
        \\        body {{ margin: 0; padding: 0; }}
        \\        svg {{ display: block; }}
        \\    </style>
        \\</head>
        \\<body>
        \\    {s}
        \\</body>
        \\</html>
    , .{svg});
    const file = try std.fs.cwd().createFile("hierarchical_notes.html", .{});
    defer file.close();
    try file.writeAll(html);

    std.debug.print("HTML file generated: hierarchical_notes.html\n", .{});
}
