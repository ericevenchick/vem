const std = @import("std");

pub const hashSize = 32;
pub const encodedHashSize = 2 * hashSize;

pub const vem_path = "~/.vem/";
const blobcas_dir = "blobcas";
const treecas_dir = "treecas";

const CasError = error{ UnsupportedFileType, OutOfMemory, ReadFailed } || std.fs.Dir.StatFileError || std.fs.File.ReadError;

pub const CasStore = struct {
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) CasStore {
        return CasStore{ .gpa = gpa };
    }

    pub fn blobcasPath(self: *CasStore, hash: [hashSize]u8) ![]const u8 {
        const hash_enc = try encodeHash(&hash);
        const path_segments = &[_][]const u8{ vem_path, blobcas_dir, hash_enc[0..2], hash_enc[2..hash_enc.len] };
        const cas_path = try std.fs.path.join(self.gpa, path_segments);
        return cas_path;
    }

    pub fn addAny(self: *CasStore, path: []const u8) CasError![hashSize]u8 {
        const stat = try std.fs.cwd().statFile(path);
        const hash = try switch (stat.kind) {
            .file => self.addFile(path),
            else => return error.UnsupportedFileType,
        };
        return hash;
    }

    fn addFile(self: *CasStore, path: []const u8) ![hashSize]u8 {
        const hash = try self.hashFile(path);
        const cas_path = try self.blobcasPath(hash);
        defer self.gpa.free(cas_path);

        std.debug.print("adding file {s} to path {s}\n", .{ path, cas_path });

        return hash;
    }

    pub fn hashAny(self: *CasStore, path: []const u8) CasError![hashSize]u8 {
        const stat = try std.fs.cwd().statFile(path);
        const hash = try switch (stat.kind) {
            .file => self.hashFile(path),
            .directory => self.hashDir(path),
            else => return error.UnsupportedFileType,
        };

        return hash;
    }

    fn hashFile(self: *CasStore, path: []const u8) ![hashSize]u8 {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        // add the git reader
        const header = try std.fmt.allocPrint(self.gpa, "blob {d}\x00", .{stat.size});
        defer self.gpa.free(header);
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

        // TODO we need to actually return this, not print it
        std.debug.print("{o} blob {x} {s}\n", .{ stat.mode, digest, path });
        return digest;
    }

    fn hashDir(self: *CasStore, path: []const u8) ![hashSize]u8 {
        var arena_impl = std.heap.ArenaAllocator.init(self.gpa);
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        // iterate over files in this dir, collecting paths
        var dir_iter = dir.iterate();
        var paths: std.ArrayList([]const u8) = .empty;

        while (try dir_iter.next()) |ent| {
            const path_segments = &[_][]const u8{ path, ent.name };
            const ent_path = try std.fs.path.join(arena, path_segments);

            try paths.append(arena, try arena.dupe(u8, ent_path));
        }

        // sort the paths
        std.mem.sort([]const u8, paths.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // hash the paths recursively
        // TODO this does not actually generate the correct git hash yet
        for (paths.items) |p| {
            const hash = try self.hashAny(p);
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
};
