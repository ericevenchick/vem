const SubCmd = enum {
    add,
};

fn parseSubcommand(cmd: []const u8) ?SubCmd {
    return std.meta.stringToEnum(SubCmd, cmd);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const parsers = comptime .{ .COMMAND = clap.parsers.enumeration(SubCmd), .ARGS = clap.parsers.string };

    const global_params = comptime clap.parseParamsComptime(
        \\ -h, --help   Show help
        \\ <COMMAND>    Run subcommand    
        \\ <ARGS>   
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &global_params, parsers, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        // Report useful error and exit
        switch (err) {
            error.NameNotPartOfEnum => {
                std.debug.print("Invalid subcommand\n", .{});
                std.process.exit(1);
            },
            else => diag.reportToFile(std.fs.File.stderr(), err) catch {},
        }
        return err;
    };
    defer res.deinit();

    const cmd = res.positionals[0] orelse {
        std.debug.print("No subcommand provided\n", .{});
        return;
    };

    switch (cmd) {
        .add => try runAdd(res.positionals[1] orelse ""),
    }
}

fn runAdd(args: []const u8) !void {
    var buf: [lib.fileHashSize]u8 = undefined;
    const hash = lib.hashFile(&buf, args) catch |err| {
        std.debug.print("Error hashing file {s}\n", .{@errorName(err)});
        return;
    };

    std.debug.print("{s}\n", .{hash});
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("vem_lib");
const clap = @import("clap");
