const raylib = @import("raylib");

pub fn Triangle(comptime T: type) type {
    const Vector_T = comptime switch (T) {
        f32 => raylib.Vector2,
        i32 => raylib.Vector2i,
        inline else => unreachable,
    };

    return struct {
        a: Vector_T,
        b: Vector_T,
        c: Vector_T,

        pub fn fromPoints(a: Vector_T, b: Vector_T, c: Vector_T) @This() {
            return .{
                .a = a,
                .b = b,
                .c = c,
            };
        }

        pub fn toI32(this: @This()) Triangle(i32) {
            if (Vector_T == i32) return this;

            return Triangle(i32){
                .a = this.a.int(),
                .b = this.b.int(),
                .c = this.c.int(),
            };
        }

        pub fn toF32(this: @This()) Triangle(f32) {
            if (Vector_T == f32) return this;

            return Triangle(f32){
                .a = this.a.float(),
                .b = this.b.float(),
                .c = this.c.float(),
            };
        }
    };
}
