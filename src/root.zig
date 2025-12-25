//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const hashSize = 32;
pub const encodedHashSize = base32.std_encoding.encodeLen(hashSize);

const HashingError = error{ UnsupportedFileType, OutOfMemory, ReadFailed } || std.fs.Dir.StatFileError || std.fs.File.ReadError;

pub fn hashAny(path: []const u8) HashingError![hashSize]u8 {
    const stat = try std.fs.cwd().statFile(path);
    const hash = try switch (stat.kind) {
        .file => hashFile(path),
        .directory => hashDir(path),
        else => return error.UnsupportedFileType,
    };

    return hash;
}

fn hashFile(path: []const u8) ![hashSize]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [256 * 1024]u8 = undefined;
    var r = file.reader(&buf);
    const reader = &r.interface;

    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try reader.readSliceShort(&chunk);
        if (n == 0) break;
        hasher.update(chunk[0..n]);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    std.debug.print("file hash {s} -> {X}\n", .{ path, digest });

    return digest;
}

fn hashDir(path: []const u8) ![hashSize]u8 {
    var alloc = std.heap.page_allocator;
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var hasher = std.crypto.hash.Blake3.init(.{});

    // iterate over files in this dir, collecting paths
    var dir_iter = dir.iterate();
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(alloc);
    while (try dir_iter.next()) |ent| {
        const path_segments = &[_][]const u8{ path, ent.name };
        const ent_path = try std.fs.path.join(alloc, path_segments);
        defer alloc.free(ent_path);

        try paths.append(alloc, try alloc.dupe(u8, ent_path));
    }

    // sort the paths
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(a, b);
        }
    }.lessThan);

    // hash the paths recursively
    for (paths.items) |p| {
        std.debug.print("-> {s}\n", .{p});
        const hash = try hashAny(p);
        hasher.update(&hash);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    std.debug.print("dir hash {s} -> {X}\n", .{ path, digest });

    return digest;
}

pub fn encodeHash(dest: []u8, hash: []const u8) ![]const u8 {
    return base32.std_encoding.encode(dest, hash);
}

const base32 = @import("base32");
