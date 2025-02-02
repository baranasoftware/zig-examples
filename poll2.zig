// nc  localhost 8443
// non-blocking server with poll

const std = @import("std");
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.tcp_demo);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try Server.init(allocator, 4096);
    defer server.deinit();

    const address = try std.net.Address.parseIp("127.0.0.1", 8443);
    try server.run(address);

    std.debug.print("dns server is ready\n", .{});
}

const Server = struct {
    allocator: Allocator,
    connected: usize,
    polls: []posix.pollfd,
    clients: []Client,
    clients_polls: []posix.pollfd,

    fn init(allocator: Allocator, max: usize) !Server {
        const polls = try allocator.alloc(posix.pollfd, max + 1);
        errdefer allocator.free(polls);

        const clients = try allocator.alloc(Client, max);
        errdefer allocator.free(clients);

        return .{
            .polls = polls,
            .clients = clients,
            .client_polls = polls[1..],
            .connected = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Server) void {
        self.allocator.free(self.polls);
        self.allocator.free(self.clients);
    }
};

const Client = struct {
    reader: Reader,
    socket: posix.socket_t,
    address: std.net.Address,

    fn init(allocator: Allocator, socket: posix.socket_t, address: std.net.Address) !Client {
        const reader = try Reader.init(allocator, 4096);
        errdefer reader.deinit(allocator);

        return .{
            .reader = reader,
            .socket = socket,
            .address = address,
        };
    }

    fn deinit(self: *const Client, allocator: Allocator) void {
        self.reader.deinit(allocator);
    }

    fn readMessage(self: *Client) !?[]const u8 {
        return self.reader.readMessage(self.socket) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };
    }
};

const Reader = struct {
    buf: []u8,
    pos: usize = 0,
    start: usize = 0,

    fn init(allocator: Allocator, size: usize) !Reader {
        const buf = try allocator.alloc(u8, size);
        return .{
            .pos = 0,
            .start = 0,
            .buf = buf,
        };
    }

    fn deinit(self: *const Reader, allocator: Allocator) void {
        allocator.free(self.buf);
    }

    fn readMessage(self: *Reader, socket: posix.socket_t) ![]u8 {
        var buf = self.buf;

        while (true) {
            if (try self.bufferedMessage()) |msg| {
                return msg;
            }
            const pos = self.pos;
            const n = try posix.read(socket, buf[pos..]);
            if (n == 0) {
                return error.Closed;
            }
            self.pos = pos + n;
        }
    }

    fn bufferedMessage(self: *Reader) !?[]u8 {
        const buf = self.buf;
        const pos = self.pos;
        const start = self.start;

        std.debug.assert(pos >= start);
        const unprocessed = buf[start..pos];
        if (unprocessed.len < 4) {
            self.ensureSpace(4 - unprocessed.len) catch unreachable;
            return null;
        }

        const message_len = std.mem.readInt(u32, unprocessed[0..4], .little);

        // the length of our message + the length of our prefix
        const total_len = message_len + 4;

        if (unprocessed.len < total_len) {
            try self.ensureSpace(total_len);
            return null;
        }

        self.start += total_len;
        return unprocessed[4..total_len];
    }

    fn ensureSpace(self: *Reader, space: usize) error{BufferTooSmall}!void {
        const buf = self.buf;
        if (buf.len < space) {
            return error.BufferTooSmall;
        }

        const start = self.start;
        const spare = buf.len - start;
        if (spare >= space) {
            return;
        }

        const unprocessed = buf[start..self.pos];
        std.mem.copyForwards(u8, buf[0..unprocessed.len], unprocessed);
        self.start = 0;
        self.pos = unprocessed.len;
    }

    fn run() !void {
        const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        defer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        self.polls[0] = .{
            .fd = listener,
            .events = posix.POLL.IN,
            .revents = 0,
        };


        while (true) {
            _ = try posix.poll(self.polls[0..self.connected + 1], -1);

            if (self.[0].revents != 0) { // active[0] is the listening socket
                var client_address: net.Address = undefined;
                var client_address_len: posix.socklen_t = @sizeOf(net.Address);

                const socket = try posix.accept(listener, &client_address.any, &client_address_len, posix.SOCK.NONBLOCK);

                polls[poll_count] = .{
                    .fd = socket,
                    .revents = 0,
                    .events = posix.POLL.IN,
                };

                poll_count += 1;
            }

            var i: usize = 1;
            while (i < active.len) {
                const polled = active[i];

                const revents = polled.revents;
                if (revents == 0) {
                    //not ready yet
                    i += 1;
                    continue;
                }
                var closed = false;
                if (revents & posix.POLL.IN == posix.POLL.IN) {
                    // socket is ready for polling
                    var buf: [4096]u8 = undefined;
                    const read = posix.read(polled.fd, &buf) catch 0;
                    if (read == 0) {
                        closed = true;
                    } else {
                        std.debug.print("[{d}] got: {any}\n", .{ polled.fd, buf[0..read] });
                    }
                }

                if (closed or (revents & posix.POLL.HUP == posix.POLL.HUP)) {
                    // read failed or socket is closed
                    posix.close(polled.fd);

                    const last_index = active.len - 1;
                    active[i] = active[last_index];
                    active = active[0..last_index];
                    poll_count = 1;
                } else {
                    i += 1; // go to the next socket
                }
            }
        }


    }
};

pub const DnsServer = struct {
    ip_addr: []const u8,
    port: u16,

    pub fn init(ip_addr: []const u8, port: u16) DnsServer {
        return DnsServer{ .ip_addr = ip_addr, .port = port };
    }

    pub fn start(self: DnsServer) !void {
        const address = try std.net.Address.parseIp(self.ip_addr, self.port);
        const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        defer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        var polls: [4096]posix.pollfd = undefined;
        polls[0] = .{
            .fd = listener,
            .events = posix.POLL.IN,
            .revents = 0,
        };

        var poll_count: usize = 1;

        while (true) {
            var active = polls[0 .. poll_count + 1];
            _ = try posix.poll(active, -1);

            if (active[0].revents != 0) { // active[0] is the listening socket
                var client_address: net.Address = undefined;
                var client_address_len: posix.socklen_t = @sizeOf(net.Address);

                const socket = try posix.accept(listener, &client_address.any, &client_address_len, posix.SOCK.NONBLOCK);

                polls[poll_count] = .{
                    .fd = socket,
                    .revents = 0,
                    .events = posix.POLL.IN,
                };

                poll_count += 1;
            }

            var i: usize = 1;
            while (i < active.len) {
                const polled = active[i];

                const revents = polled.revents;
                if (revents == 0) {
                    //not ready yet
                    i += 1;
                    continue;
                }
                var closed = false;
                if (revents & posix.POLL.IN == posix.POLL.IN) {
                    // socket is ready for polling
                    var buf: [4096]u8 = undefined;
                    const read = posix.read(polled.fd, &buf) catch 0;
                    if (read == 0) {
                        closed = true;
                    } else {
                        std.debug.print("[{d}] got: {any}\n", .{ polled.fd, buf[0..read] });
                    }
                }

                if (closed or (revents & posix.POLL.HUP == posix.POLL.HUP)) {
                    // read failed or socket is closed
                    posix.close(polled.fd);

                    const last_index = active.len - 1;
                    active[i] = active[last_index];
                    active = active[0..last_index];
                    poll_count = 1;
                } else {
                    i += 1; // go to the next socket
                }
            }
        }
    }
};
