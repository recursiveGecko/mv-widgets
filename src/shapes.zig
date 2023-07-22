const raylib = @import("raylib");

pub const Triangle = struct {
    a: raylib.Vector2,
    b: raylib.Vector2,
    c: raylib.Vector2,

    pub fn fromPoints(a: raylib.Vector2, b: raylib.Vector2, c: raylib.Vector2) @This() {
        return .{
            .a = a,
            .b = b,
            .c = c,
        };
    }
};
