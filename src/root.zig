//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const fileHashSize = base32.std_encoding.encodeLen(32);

pub fn hashFile(dest: []u8, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var hasher = std.crypto.hash.Blake3.init(.{});
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    const out = base32.std_encoding.encode(dest, &digest);

    return out;
}

const base32 = @import("base32");
