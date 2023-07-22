pub const Config = enum {
    decoration_size,
};

pub fn ConfigType(comptime config: Config) type {
    return switch (config) {
        .decoration_size => i32,
    };
}

pub fn getValue(config: Config) ConfigType(config) {
    return switch (config) {
        .decoration_size => 20,
    };
}
