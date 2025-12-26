const std = @import("std");

pub const hashSize = 32;
pub const encodedHashSize = 2 * hashSize;

pub const vem_path = "~/.vem/";
const blobcas_dir = "blobcas";
const treecas_dir = "treecas";

const CasError = error{ UnsupportedFileType, OutOfMemory, ReadFailed } || std.fs.Dir.StatFileError || std.fs.File.ReadError;

pub fn blobcasPath(alloc: std.mem.Allocator, hash: [hashSize]u8) ![]const u8 {
    const hash_enc = try encodeHash(&hash);
    const path_segments = &[_][]const u8{ vem_path, blobcas_dir, hash_enc[0..2], hash_enc[2..hash_enc.len] };
    const cas_path = try std.fs.path.join(alloc, path_segments);
    return cas_path;
}

pub fn addAny(alloc: std.mem.Allocator, path: []const u8) CasError![hashSize]u8 {
    const stat = try std.fs.cwd().statFile(path);
    const hash = try switch (stat.kind) {
        .file => addFile(alloc, path),
        else => return error.UnsupportedFileType,
    };
    return hash;
}

fn addFile(alloc: std.mem.Allocator, path: []const u8) ![hashSize]u8 {
    const hash = try hashFile(alloc, path);
    const cas_path = try blobcasPath(alloc, hash);
    defer alloc.free(cas_path);

    std.debug.print("adding file {s} to path {s}\n", .{ path, cas_path });

    return hash;
}

pub fn hashAny(alloc: std.mem.Allocator, path: []const u8) CasError![hashSize]u8 {
    const stat = try std.fs.cwd().statFile(path);
    const hash = try switch (stat.kind) {
        .file => hashFile(alloc, path),
        .directory => hashDir(alloc, path),
        else => return error.UnsupportedFileType,
    };

    return hash;
}

fn hashFile(alloc: std.mem.Allocator, path: []const u8) ![hashSize]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    // add the git reader
    const header = try std.fmt.allocPrint(alloc, "blob {d}\x00", .{stat.size});
    defer alloc.free(header);
    hasher.update(header);

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
    std.debug.print("{o} blob {x} {s}\n", .{ stat.mode, digest, path });

    return digest;
}

fn hashDir(alloc: std.mem.Allocator, path: []const u8) ![hashSize]u8 {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

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
        const hash = try hashAny(alloc, p);
        hasher.update(&hash);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    std.debug.print("040000 tree {x} {s}\n", .{ digest, path });
    std.debug.print("\n", .{});

    return digest;
}

pub fn encodeHash(hash: []const u8) ![encodedHashSize]u8 {
    var r: [encodedHashSize]u8 = undefined;
    _ = try std.fmt.bufPrint(&r, "{x}", .{hash});
    return r;
}
