const std = @import("std");
const builtin = @import("builtin");
const args = @import("./args.zig");

const ChapterDownloader = @import("./client.zig").ChapterDownloader;
const searchManga = @import("./client.zig").searchManga;
const getMangaVolCh = @import("./client.zig").getMangaVolCh;
const getManga = @import("./client.zig").getManga;

const version = "1.4.3";

const Action = enum {
    PrintHelp,
    PrintVersion,
    DownloadChapter,
    PrintChapterLinks,
    SearchManga,
    PrintVolCh,
    DownloadCover
};

var runtime_opts: struct {
    action: Action = .DownloadChapter,
    color: bool = if(builtin.os.tag == .windows) false else true,
    data_saver: bool = false,
    range: ?std.meta.Tuple(&.{ u32, u32 }) = null,
    output: ?[]const u8 = null,
} = .{};

fn printError(comptime fmt: []const u8, _args: anytype) !void {
    const stderr = std.io.getStdErr().writer();
    if(runtime_opts.color) {
        try stderr.print("[{s}Error{s}] ", .{ args.ANSIRed, "\x1b[0m" });
    } else {
        try stderr.print("[Error] ", .{});
    }
    try stderr.print(fmt ++ "\n", _args);
}

fn iWarn(msg: []const u8, opts: []const u8) !u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
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

fn onStartPageDw(fname: []const u8) anyerror!void {
    try std.io.getStdOut().writer().print("Downloading page {s}... ", .{ fname });
}

fn onEndPageDw() anyerror!void {
    const stdout = std.io.getStdOut().writer();
    if(runtime_opts.color) {
        try stdout.print("{s}Done{s}\n", .{ args.ANSIGreen, "\x1b[0m" });
    } else {
        try stdout.print("Done\n", .{});
    }
}

fn onFileOverwrite(fname: []const u8) anyerror!bool {
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
    const stdout = std.io.getStdOut().writer();

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
    try parser.addFlag("cover", "Get the cover of a manga", null);
    // Options
    try parser.addOption(
        "range",
        \\Select items in this range. Use "n" (Ex: "-r 2-n") to specify the end.
        \\Ex: "mangadex-dl <CHAPTER> -r 2-5" will only download pages 2 to 5.
        \\    "mangadex-dl --search <TITLE> -r 1-2" will only show the first 2 results.
        , 'r', null, null
    );
    try parser.addOption("output", "Name of the downloaded images excluding file extension", 'o', null, null);
    try parser.addOption("first", "Select the first n items. Equivalent to \"-r 1-<NUM>\"", 'n', null, null);

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
        if(flag.get("cover") != null) { runtime_opts.action = .DownloadCover; }
        if(flag.get("data-saver") != null) { runtime_opts.data_saver = true; }
    }
    if(results.option) |option| {
        var first_opt = option.get("first");
        if(first_opt) |fo| {
            runtime_opts.range = .{ 0, try std.fmt.parseUnsigned(u32, fo, 10) };
        }
        var range_opt = option.get("range");
        if(range_opt) |ro| {
            if(runtime_opts.range != null) {
                try printError("Incompatible options \"--first\" and \"--range\"", .{});
                std.process.exit(1);
            }
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
        runtime_opts.output = option.get("output");
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
            var client = try ChapterDownloader.init(std.heap.page_allocator, link);
            client.file_name = runtime_opts.output;
            defer client.deinit();

            // Print links if enabled
            if(runtime_opts.action == .PrintChapterLinks) {
                var iter: [][]const u8 = undefined;
                if(runtime_opts.data_saver) {
                    iter = client.chapter_res.?.value.chapter.dataSaver;
                } else {
                    iter = client.chapter_res.?.value.chapter.data;
                }
                var start: usize = 0;
                var end: usize = iter.len;
                if(runtime_opts.range) |r| {
                    start = r.@"0";
                    if(r.@"1" <= end) { end = r.@"1"; }
                }
                for(start..end) |i| {
                    try stdout.print("{s}/{s}/{s}/{s}\n", .{
                        client.chapter_res.?.value.baseUrl,
                        if(runtime_opts.data_saver) "data-saver" else "data",
                        client.chapter_res.?.value.chapter.hash, iter[i]
                    });
                }
                std.process.exit(0);
            } else {
                // Download pages
                if(runtime_opts.data_saver) {
                    try client.downloadAllPagesDS(runtime_opts.range, onStartPageDw, onEndPageDw, onFileOverwrite);
                } else {
                    try client.downloadAllPages(runtime_opts.range, onStartPageDw, onEndPageDw, onFileOverwrite);
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
                    if(end > res.res.value.data.len) { end = res.res.value.data.len; }
                    if(runtime_opts.color) { try res.printrColor(start, end); }
                    else { try res.printr(start, end); }
                } else { try res.print(runtime_opts.color); }
                std.os.exit(0);
            } else {
                try printError("Nothing to search for", .{});
                std.os.exit(1);
            }
        },
        .DownloadCover => {
            if(results.positional) |pos| {
                var res = try getManga(pos.items[0], std.heap.page_allocator);
                defer res.deinit();
                var cover_id: []const u8 = undefined;
                for(res.res.value.data.relationships) |rel| {
                    if(
                        std.mem.eql(u8, rel.object.get("type").?.string, "cover_art") and
                        rel.object.get("attributes") != null
                    ) {
                        cover_id = rel.object.get("attributes").?.object.get("fileName").?.string;
                    }
                }

                var ext = std.fs.path.extension(cover_id);
                var fname = try std.fmt.allocPrint(std.heap.page_allocator, "cover{s}", .{ ext });
                defer std.heap.page_allocator.free(fname);
                var link = try std.fmt.allocPrint(
                    std.heap.page_allocator, "https://uploads.mangadex.org/covers/{s}/{s}",
                    .{ pos.items[0], cover_id }
                );
                defer std.heap.page_allocator.free(link);
                var file = try std.fs.cwd().createFile(fname, .{ .truncate = true });
                defer file.close();

                var client = std.http.Client{ .allocator = std.heap.page_allocator };
                var req = try client.request(
                    .GET, try std.Uri.parse(link), .{ .allocator = std.heap.page_allocator }, .{}
                );
                try req.start();
                try req.wait();

                var buf = try req.reader().readAllAlloc(std.heap.page_allocator, 10_000_000);
                defer std.heap.page_allocator.free(buf);
                try file.writeAll(buf);
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
                        if(end > res.res.value.volumes.object.count()) {
                            end = res.res.value.volumes.object.count();
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
