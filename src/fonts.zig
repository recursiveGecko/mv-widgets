const std = @import("std");
const raylib = @import("raylib");

const FontSizeHashMap = std.AutoHashMap(i32, raylib.Font);

var primary_font_map: ?FontSizeHashMap = null;
var mono_font_map: ?FontSizeHashMap = null;

pub const FontType = enum { primary, mono };

pub fn init(allocator: std.mem.Allocator) void {
    primary_font_map = std.AutoHashMap(i32, raylib.Font).init(allocator);
    mono_font_map = std.AutoHashMap(i32, raylib.Font).init(allocator);
}

pub fn deinit() void {
    primary_font_map.?.deinit();
    primary_font_map = null;
    mono_font_map.?.deinit();
    mono_font_map = null;
}

pub fn getFont(font_type: FontType, font_size: i32) raylib.Font {
    if (primary_font_map == null) @panic("Fonts not initialized");

    var hash_map: *FontSizeHashMap = switch (font_type) {
        .primary => &primary_font_map.?,
        .mono => &mono_font_map.?,
    };

    var font_file = switch (font_type) {
        .primary => @embedFile("primary_font.ttf"),
        .mono => @embedFile("mono_font.ttf"),
    };

    if (hash_map.get(font_size)) |font| {
        return font;
    } else {
        const font = raylib.LoadFontFromMemory(
            ".ttf",
            font_file,
            @intCast(font_file.len),
            @intCast(font_size),
            null,
            0,
        );
        hash_map.putNoClobber(font_size, font) catch unreachable;
        return font;
    }
}
