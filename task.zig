// a task scheduler
const std = @import("std");

pub fn main() !void {
    var person = Person{ .name = "Vegeta" };
    const thread = try std.Thread.spawn(.{}, Person.say, .{ &person, "limit exceed", 3 * std.time.ns_per_s });
    thread.join();
}

const Person = struct {
    name: []const u8,

    fn say(p: *Person, msg: []const u8, when: u64) void {
        std.time.sleep(when);
        std.debug.print("{s} said: {s} \n", .{ p.name, msg });
    }
};
