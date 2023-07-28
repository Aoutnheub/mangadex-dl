const std = @import("std");
const builtin = @import("builtin");
const args = @import("./args.zig");

const DownloadClient = @import("./client.zig").DownloadClient;
const searchManga = @import("./client.zig").searchManga;
const getMangaVolCh = @import("./client.zig").getMangaVolCh;

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
const stderr = std.io.getStdErr().writer();
const version = "1.3";

const Action = enum {
    PrintHelp,
    PrintVersion,
    DownloadChapter,
    PrintChapterLinks,
    SearchManga,
    PrintVolCh
};

var runtime_opts: struct {
    action: Action = .DownloadChapter,
    color: bool = if(builtin.os.tag == .windows) false else true,
    data_saver: bool = false,
    range: ?std.meta.Tuple(&.{ u32, u32 }) = null,
    name: ?[]const u8 = null,
} = .{};

fn printError(comptime fmt: []const u8, _args: anytype) !void {
    if(runtime_opts.color) {
        try stderr.print("[{s}Error{s}] ", .{ args.ANSIRed, "\x1b[0m" });
    } else {
        try stderr.print("[Error] ", .{});
    }
    try stderr.print(fmt ++ "\n", _args);
}

fn iWarn(msg: []const u8, opts: []const u8) !u8 {
    if(runtime_opts.color) {
        try stdout.print("[{s}Warning{s}] {s} [", .{ args.ANSIYellow, "\x1b[0m", msg });
    } else {
        try stdout.print("[Warning] {s} [", .{ msg });
    }
    for(opts, 0..) |o, i| {
        try stdout.writeByte(o);
        if(i != opts.len - 1) { try stdout.writeByte('/'); }
    }
    try stdout.print("] ", .{});
    var b = try stdin.readByte();
    try stdin.skipUntilDelimiterOrEof('\n');

    return b;
}

fn onStartPageDw(fname: []const u8) !void {
    try stdout.print("Downloading page {s}... ", .{ fname });
}

fn onEndPageDw() !void {
    if(runtime_opts.color) {
        try stdout.print("{s}Done{s}\n", .{ args.ANSIGreen, "\x1b[0m" });
    } else {
        try stdout.print("Done\n", .{});
    }
}

fn onFileOverwrite(fname: []const u8) !bool {
    var msg = try std.fmt.allocPrint(
        std.heap.page_allocator, "File \"{s}\" already exists. Overwrite it?", .{ fname }
    );
    defer std.heap.page_allocator.free(msg);
    while(true) {
        var res = try iWarn(msg, "yn");
        switch(res) {
            'y' => return true,
            'n' => return false,
            else => {
                try printError("Invalid option {s}\n", .{ [_]u8{res} });
            }
        }
    }
}

const RangeError = error {
    InvalidStart, BiggerEnd
};

// The range returned will be exclusive and start from range[0]-1
// Ex: For "2-4" it will return [1, 4]
// Hope that makes sense :)
fn parseRange(range: []const u8) (std.fmt.ParseIntError || RangeError)!struct{ u32, u32 } {
    var iter = std.mem.tokenize(u8, range, "- ");
    var nums: [2]u32 = .{ 0, 0 };
    var idx: usize = 0;
    while(iter.next()) |n| {
        if(n.len == 0) { continue; }
        if(idx == 2) { break; }
        if(std.mem.eql(u8, n, "n")) {
            nums[idx] = 9999;
        } else {
            nums[idx] = try std.fmt.parseUnsigned(u8, n, 10);
        }
        idx += 1;
    }

    if(nums[0] == 0) {
        return RangeError.InvalidStart;
    }
    if(nums[0] > nums[1]) {
        return RangeError.BiggerEnd;
    }
    nums[0] -= 1;

    return .{ nums[0], nums[1] };
}

pub fn main() !void {
    // Argument parser
    var parser = args.Parser.init(
        std.heap.page_allocator, "mangadex-dl " ++ version,
        \\CLI utility for downloading chapters from mangadex.
        \\Usage: mangadex-dl [OPTIONS] <CHAPTER_LINK>
    );
    defer parser.deinit();
    parser.colors = runtime_opts.color;
    // Flags
    try parser.addFlag("help", "Print this message and exit", 'h');
    try parser.addFlag("version", "Print version and exit", 'v');
    try parser.addFlag("print-links", "Print the links to all the pages without downloading any", 'l');
    try parser.addFlag("color", "Toggle colored output. Enabled by default if not on Windows", null);
    try parser.addFlag("data-saver", "Download compressed images. Smaller size, less quality", 's');
    try parser.addFlag("search", "Search for a manga", 'S');
    try parser.addFlag("volch", "Print volumes and chapters of manga", 'C');
    // Options
    try parser.addOption(
        "range",
        \\Select items in this range. Use "n" (Ex: "-r 2-n") to specify the end.
        \\Ex: "mangadex-dl <CHAPTER> -r 2-5" will only download pages 2 to 5.
        \\    "mangadex-dl --search <TITLE> -r 1-2" will only show the first 2 results.
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
    if(results.flag) |flag| FLAG_CHECK: {
        if(flag.get("color") != null) { runtime_opts.color = !runtime_opts.color; }
        if(flag.get("help") != null) {
            runtime_opts.action = .PrintHelp;
            break :FLAG_CHECK;
        }
        if(flag.get("version") != null) {
            runtime_opts.action = .PrintVersion;
            break :FLAG_CHECK;
        }
        if(flag.get("search") != null) { runtime_opts.action = .SearchManga; }
        if(flag.get("volch") != null) { runtime_opts.action = .PrintVolCh; }
        if(flag.get("print-links") != null) { runtime_opts.action = .PrintChapterLinks; }
        if(flag.get("data-saver") != null) { runtime_opts.data_saver = true; }
    }
    if(results.option) |option| {
        var range_opt = option.get("range");
        if(range_opt) |ro| {
            runtime_opts.range = parseRange(ro) catch |err| {
                switch(err) {
                    error.InvalidStart => {
                        try printError("Invalid range. Start from 1", .{});
                        std.process.exit(1);
                    },
                    error.BiggerEnd => {
                        try printError("Invalid range. End must be bigger than start", .{});
                        std.process.exit(1);
                    },
                    else => {
                        try printError("Could not parse range", .{});
                        std.process.exit(1);
                    }
                }
            };
        }
        runtime_opts.name = option.get("name");
    }

    switch(runtime_opts.action) {
        .PrintHelp => {
            try parser.help();
            std.process.exit(0);
        },
        .PrintVersion => {
            try stdout.print("Version " ++ version ++ "\n", .{});
            std.process.exit(0);
        },
        .DownloadChapter, .PrintChapterLinks => {
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
            var dclient = try DownloadClient.init(std.heap.page_allocator, link);
            dclient.file_name = runtime_opts.name;
            defer dclient.deinit();

            // Print links if enabled
            if(runtime_opts.action == .PrintChapterLinks) {
                var iter: [][]const u8 = undefined;
                if(runtime_opts.data_saver) {
                    iter = dclient.chapter_data.?.value.chapter.dataSaver;
                } else {
                    iter = dclient.chapter_data.?.value.chapter.data;
                }
                var start: usize = 0;
                var end: usize = iter.len;
                if(runtime_opts.range) |r| {
                    start = r.@"0";
                    if(r.@"1" <= end) { end = r.@"1"; }
                }
                for(start..end) |i| {
                    try stdout.print("{s}/{s}/{s}/{s}\n", .{
                        dclient.chapter_data.?.value.baseUrl,
                        if(runtime_opts.data_saver) "data-saver" else "data",
                        dclient.chapter_data.?.value.chapter.hash, iter[i]
                    });
                }
                std.process.exit(0);
            } else {
                // Download pages
                if(runtime_opts.data_saver) {
                    try dclient.downloadAllPagesDS(runtime_opts.range, onStartPageDw, onEndPageDw, onFileOverwrite);
                } else {
                    try dclient.downloadAllPages(runtime_opts.range, onStartPageDw, onEndPageDw, onFileOverwrite);
                }
            }
        },
        .SearchManga => {
            if(results.positional) |pos| {
                var title = try std.mem.join(std.heap.page_allocator, " ", pos.items);
                defer std.heap.page_allocator.free(title);
                var res = try searchManga(title, std.heap.page_allocator);
                defer res.deinit();
                if(runtime_opts.range) |r| {
                    var start: usize = r.@"0";
                    var end: usize = r.@"1";
                    if(end > res.data.value.data.len) { end = res.data.value.data.len; }
                    if(runtime_opts.color) { try res.printrColor(start, end); }
                    else { try res.printr(start, end); }
                } else { try res.print(runtime_opts.color); }
                std.os.exit(0);
            } else {
                try printError("Nothing to search for", .{});
                std.os.exit(1);
            }
        },
        .PrintVolCh => {
            if(results.positional) |pos| {
                if(pos.items.len == 2) {
                    var res = try getMangaVolCh(pos.items[0], pos.items[1], std.heap.page_allocator);
                    defer res.deinit();
                    if(runtime_opts.range) |r| {
                        var start: usize = r.@"0";
                        var end: usize = r.@"1";
                        if(end > res.data.value.volumes.object.count()) {
                            end = res.data.value.volumes.object.count();
                        }
                        if(runtime_opts.color) { try res.printrColor(start, end); }
                        else { try res.printr(start, end); }
                    } else { try res.print(runtime_opts.color); }
                    std.os.exit(0);
                } else {
                    try printError("Two arguments required <LANG> <ID>", .{});
                    std.os.exit(1);
                }
            } else {
                try printError("No arguments given", .{});
                std.os.exit(1);
            }
        }
    }
}
