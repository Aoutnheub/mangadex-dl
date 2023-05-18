const std = @import("std");
const builtin = @import("builtin");
const args = @import("./args.zig");

const Client = @import("./client.zig").Client;

var runtime_opts: struct {
    print_links: bool = false,
    color: bool = if(builtin.os.tag == .windows) false else true,
    data_saver: bool = false,
    range: ?std.meta.Tuple(&.{ u32, u32 }) = null,
    name: ?[]const u8 = null,
} = .{};

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

fn printError(comptime fmt: []const u8, _args: anytype) !void {
    if(runtime_opts.color) {
        try stderr.print("[{s}Error{s}] ", .{ args.ANSIRed, "\x1b[0m" });
    } else {
        try stderr.print("[Error] ", .{});
    }
    try stderr.print(fmt ++ "\n", _args);
}

fn onStartPageDw(fname: []const u8) !void {
    try stdout.print("Downloading page {s}... ", .{ fname });
}

fn onEndPageDw() !void {
    if(runtime_opts.color) {
        try stdout.print("{s}Done\x1b[0m\n", .{ args.ANSIGreen });
    } else {
        try stdout.print("Done\n", .{});
    }
}

fn parseRange(range: []const u8) !struct{ u32, u32 } {
    var iter = std.mem.tokenize(u8, range, "- ");
    var nums: [2]u32 = .{ 0, 0 };
    var idx: usize = 0;
    while(iter.next()) |n| {
        if(n.len == 0) { continue; }
        if(idx == 2) { break; }
        nums[idx] = try std.fmt.parseUnsigned(u8, n, 10);
        idx += 1;
    }

    return .{ nums[0], nums[1] };
}

pub fn main() !void {
    // Argument parser
    var parser = args.Parser.init(
        std.heap.page_allocator, "mangadex-dl v1.0",
        \\CLI utility for downloading chapters from mangadex.
        \\Usage: mangadex-dl [OPTIONS] <CHAPTER_LINK>
    );
    defer parser.deinit();
    parser.colors = runtime_opts.color;
    // Flags
    try parser.addFlag("help", "Print this message and exit", 'h');
    try parser.addFlag("print-links", "Print the links to all the pages without downloading any", 'l');
    try parser.addFlag("color", "Toggle colored output. Enabled by default if not on Windows", null);
    try parser.addFlag("data-saver", "Download compressed images. Smaller size, less quality", 's');
    // Options
    try parser.addOption(
        "range",
        \\Download pages in this range.
        \\Ex: "3-12"
        , 'r', null, null
    );
    try parser.addOption("name", "Name of the downloaded images excluding file extension", 'n', null, null);

    // Parse arguments
    var raw_args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, raw_args);
    var results = parser.parse(raw_args) catch |err| {
        switch(err) {
            args.ParserError.InvalidArgument => {
                try printError("Invalid argument '{s}'", .{ parser.err.? });
            },
            args.ParserError.InvalidValue => {
                try printError("Invalid value for argument '{s}'", .{ parser.err.? });
            },
            args.ParserError.MissingValue => {
                try printError("Missing value for argument '{s}'", .{ parser.err.? });
            },
            else => {
                try printError("{any}", .{ err });
            }
        }
        std.process.exit(1);
    };
    defer results.deinit();

    // Set runtime options
    if(results.flag) |flag| {
        if(flag.get("help") != null) {
            try parser.help();
            std.process.exit(0);
        }
        if(flag.get("print-links") != null) {
            runtime_opts.print_links = true;
        }
        if(flag.get("color") != null) {
            runtime_opts.color = !runtime_opts.color;
        }
        if(flag.get("data-saver") != null) {
            runtime_opts.data_saver = true;
        }
    }
    if(results.option) |option| {
        var range_opt = option.get("range");
        if(range_opt != null) {
            runtime_opts.range = try parseRange(range_opt.?);
            if(runtime_opts.range.?.@"0" == 0 or runtime_opts.range.?.@"1" == 0) {
                try printError("Invalid range. Pages start from 1", .{});
                std.process.exit(1);
            }
            runtime_opts.range.?.@"0" -= 1;
            runtime_opts.range.?.@"1" -= 1;
            if(runtime_opts.range.?.@"0" > runtime_opts.range.?.@"1") {
                try printError("Invalid range. End must be bigger than start", .{});
                std.process.exit(1);
            }
        }
        runtime_opts.name = option.get("name");
    }

    // Get chapter data
    var link: []const u8 = undefined;
    defer std.heap.page_allocator.free(link);
    if(results.positional) |positional| {
        link = try std.mem.concat(std.heap.page_allocator, u8, &.{
            "https://api.mangadex.org/at-home/server/", positional.items[0]
        });
    } else {
        try printError("Missing chapter id", .{});
        std.process.exit(1);
    }
    var client = try Client.init(std.heap.page_allocator, link);
    client.file_name = runtime_opts.name;
    defer client.deinit();

    // Print links if enabled
    if(runtime_opts.print_links) {
        if(runtime_opts.data_saver) {
            for(client.chapter_data.data_saver.items) |l| {
                try stdout.print("{s}/data-saver/{s}/{s}\n", .{
                    client.chapter_data.base_url, client.chapter_data.hash, l.string
                });
            }
        } else {
            for(client.chapter_data.data.items) |l| {
                try stdout.print("{s}/data/{s}/{s}\n", .{
                    client.chapter_data.base_url, client.chapter_data.hash, l.string
                });
            }
        }
        std.process.exit(0);
    }

    // Download pages
    if(runtime_opts.data_saver) {
        try client.downloadAllPagesDS(runtime_opts.range, onStartPageDw, onEndPageDw);
    } else {
        try client.downloadAllPages(runtime_opts.range, onStartPageDw, onEndPageDw);
    }
}
