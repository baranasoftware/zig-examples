const std = @import("std");

pub fn main() void {
    const sum = add(9001, 2);
    std.debug.print("9001 + 2 = {d}\n", .{sum});

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

fn add(a: i64, b: i64) i64 {
    return a + b;
}
