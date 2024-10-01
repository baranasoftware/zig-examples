const std = @import("std");

pub fn main() void {
    // function
    const sum = add(42, 13);
    std.debug.print("42 + 13 = {d}\n", .{sum});

    // basic types

    const user = User{ .power = 9001, .name = "Goku" };
    std.debug.print("{s}'s power is {d}\n", .{ user.name, user.power });
}

pub const User = struct {
    power: u64,
    name: []const u8,

    pub const SUPER_POWER = 9000;

    pub fn print(user: User) void {
        if (user.power >= SUPER_POWER) {}
    }
};

fn add(x: i64, y: i64) i64 {
    return x + y;
}
