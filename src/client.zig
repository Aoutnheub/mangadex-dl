const std = @import("std");
const args = @import("./args.zig");

pub const ChapterRes = struct {
    result: []const u8 = undefined,
    baseUrl: []const u8 = undefined,
    chapter: struct {
        hash: []const u8 = undefined,
        data: [][]const u8 = undefined,
        dataSaver: [][]const u8 = undefined
    } = undefined
};

pub const ChapterDownloader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    client: std.http.Client,
    chapter_buf: []const u8,
    chapter_res: ?std.json.Parsed(ChapterRes) = null,
    file_name: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, link: []const u8) !Self {
        var client = Self{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .chapter_buf = try allocator.alloc(u8, 0)
        };
        try client.getChapter(link);

        return client;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
        self.allocator.free(self.chapter_buf);
        if(self.chapter_res) |cd| { cd.deinit(); }
    }

    pub fn downloadPage(self: *Self, link: []const u8, file_name: []const u8) !void {
        var file = try std.fs.cwd().createFile(file_name, .{ .truncate = true });
        defer file.close();

        var req = try self.client.request(
            .GET, try std.Uri.parse(link), .{ .allocator = self.allocator }, .{}
        );
        try req.start();
        try req.wait();

        var buf = try req.reader().readAllAlloc(self.allocator, 10_000_000);
        defer self.allocator.free(buf);
        try file.writeAll(buf);
    }

    pub fn downloadAllPages(
        self: *Self, range: ?std.meta.Tuple(&.{ u32, u32 }),
        comptime dw_start_callback: fn(fname: []const u8) anyerror!void,
        comptime dw_end_callback: fn() anyerror!void,
        comptime overwrite_callback: fn([]const u8) anyerror!bool
    ) !void {
        try self.downloadAllPagesOfType(
            self.chapter_res.?.value.chapter.data,
            self.chapter_res.?.value.baseUrl,
            self.chapter_res.?.value.chapter.hash,
            "data", range,
            dw_start_callback, dw_end_callback, overwrite_callback
        );
    }

    pub fn downloadAllPagesDS(
        self: *Self, range: ?std.meta.Tuple(&.{ u32, u32 }),
        comptime dw_start_callback: fn(fname: []const u8) anyerror!void,
        comptime dw_end_callback: fn() anyerror!void,
        comptime overwrite_callback: fn([]const u8) anyerror!bool
    ) !void {
        try self.downloadAllPagesOfType(
            self.chapter_res.?.value.chapter.dataSaver,
            self.chapter_res.?.value.baseUrl,
            self.chapter_res.?.value.chapter.hash,
            "data-saver", range,
            dw_start_callback, dw_end_callback, overwrite_callback
        );
    }

    fn getChapter(self: *Self, link: []const u8) !void {
        var req = try self.client.request(
            .GET, try std.Uri.parse(link), .{ .allocator = self.allocator }, .{}
        );
        defer req.deinit();
        try req.start();
        try req.wait();
        self.chapter_buf = try req.reader().readAllAlloc(self.allocator, 10_000);
        self.chapter_res = try std.json.parseFromSlice(ChapterRes, self.allocator, self.chapter_buf, .{});
    }

    fn downloadAllPagesOfType(
        self: *Self, iter: [][]const u8, base: []const u8, hash: []const u8,
        data: []const u8, range: ?std.meta.Tuple(&.{ u32, u32 }),
        comptime dw_start_callback: fn(fname: []const u8) anyerror!void,
        comptime dw_end_callback: fn() anyerror!void,
        comptime overwrite_callback: fn([]const u8) anyerror!bool
    ) !void {
        var rstart: usize = 0;
        var rend: usize = iter.len;
        if(range) |r| {
            if(r.@"1" <= iter.len) { rend = r.@"1"; }
            rstart = r.@"0";
        }
        for(rstart..rend) |i| {
            var fname = iter[i];
            if(self.file_name != null) {
                fname = try std.fmt.allocPrint(self.allocator, "{s}{d:0>2}{s}", .{
                    self.file_name.?, i + 1, std.fs.path.extension(iter[i])
                });
            }

            // Check if file exists and prompt user
            var cwd = std.fs.cwd();
            var file_exists = true;
            _ = cwd.statFile(fname) catch |err| {
                switch(err) {
                    error.FileNotFound => file_exists = false,
                    else => return err
                }
            };
            var overwrite = true;
            if(file_exists) { overwrite = try overwrite_callback(fname); }

            if(overwrite) {
                try dw_start_callback(fname);
                var page_link = try std.mem.concat(self.allocator, u8, &.{
                    base, "/", data ,"/", hash, "/", iter[i]
                });
                defer self.allocator.free(page_link);
                try self.downloadPage(page_link, fname);
                try dw_end_callback();
            }
            if(self.file_name != null) {
                self.allocator.free(fname);
            }
        }
    }
};

pub const MangaData = struct {
    id: []const u8,
    @"type": []const u8,
    attributes: struct {
        title: struct {
            en: []const u8
        },
        description: std.json.Value, // Object but sometimes empty
        isLocked: bool,
        originalLanguage: []const u8,
        lastVolume: ?[]const u8,
        lastChapter: ?[]const u8,
        publicationDemographic: ?[]const u8,
        status: []const u8,
        year: ?u32,
        contentRating: []const u8,
        tags: []struct {
            id: []const u8,
            @"type": []const u8,
            attributes: struct {
                name: struct {
                    en: []const u8
                },
                group: []const u8,
                version: u32
            }
        },
        state: []const u8,
        chapterNumbersResetOnNewVolume: bool,
        createdAt: []const u8,
        updatedAt: []const u8,
        version: u32,
        availableTranslatedLanguages: [][]const u8,
        latestUploadedChapter: ?[]const u8,
    },
    relationships: []std.json.Value
};

pub const MangaRes = struct {
    result: []const u8,
    response: []const u8,
    data: MangaData
};

pub const Manga = struct {
    const Self = @This();

    _buf: []u8,
    allocator: std.mem.Allocator,
    res: std.json.Parsed(MangaRes),

    pub fn deinit(self: *Self) void {
        self.res.deinit();
        self.allocator.free(self._buf);
    }
};

pub fn getManga(id: []const u8, allocator: std.mem.Allocator) !Manga {
    var client = std.http.Client{ .allocator = allocator };
    var link = try std.fmt.allocPrint(
        allocator,
        "https://api.mangadex.org/manga/{s}?includes[]=author&includes[]=artist&includes[]=cover_art",
        .{ id }
    );
    defer allocator.free(link);
    var req = try client.request(
        .GET, try std.Uri.parse(link), .{ .allocator = allocator }, .{}
    );
    defer req.deinit();
    try req.start();
    try req.wait();

    var buf = try req.reader().readAllAlloc(allocator, 10_000_000);
    var parsed = try std.json.parseFromSlice(MangaRes, allocator, buf, .{
        .ignore_unknown_fields = true
    });

    return Manga {
        ._buf = buf,
        .allocator = allocator,
        .res = parsed
    };
}

pub const MangaSearchRes = struct {
    result: []const u8,
    response: []const u8,
    data: []MangaData,
    limit: u32,
    offset: u32,
    total: u32
};

pub const MangaSearchResults = struct {
    const Self = @This();

    _buf: []u8,
    allocator: std.mem.Allocator,
    res: std.json.Parsed(MangaSearchRes),

    pub fn deinit(self: *Self) void {
        self.res.deinit();
        self.allocator.free(self._buf);
    }

    pub fn printr(self: *Self, start: usize, end: usize) !void {
        var bufw = std.io.bufferedWriter(std.io.getStdIn().writer());
        var stdout = bufw.writer();
        for(start..end) |i| {
            // Title, id
            try stdout.print("\n{s} ({s})\n", .{
                self.res.value.data[i].attributes.title.en, self.res.value.data[i].id
            });
            // Status, year, last volume, last chapter
            try stdout.print(
                "Status: {s} Published: {?} Last volume: {s} Last chapter: {s}\n",
                .{
                    self.res.value.data[i].attributes.status,
                    self.res.value.data[i].attributes.year,
                    if(self.res.value.data[i].attributes.lastVolume) |s| s else "?",
                    if(self.res.value.data[i].attributes.lastChapter) |s| s else "?"
                }
            );
            // Tags
            try stdout.print("Tags: ", .{});
            for(self.res.value.data[i].attributes.tags) |t| {
                try stdout.print("[{s}]", .{ t.attributes.name.en });
                try stdout.writeByte(' ');
            }
            try stdout.writeByte('\n');
            // Languages
            _ = try stdout.write("Languages: ");
            for(self.res.value.data[i].attributes.availableTranslatedLanguages) |lang| {
                _ = try stdout.write(lang);
                try stdout.writeByte(' ');
            }
            _ = try stdout.write("\n\n");
            // Description
            _ = try stdout.write(
                if(self.res.value.data[i].attributes.description.object.get("en")) |s| s.string else "No description"
            );
            _ = try stdout.write("\n\n");
            try bufw.flush();
        }
    }

    pub fn printrColor(self: *Self, start: usize, end: usize) !void {
        var bufw = std.io.bufferedWriter(std.io.getStdIn().writer());
        var stdout = bufw.writer();
        for(start..end) |i| {
            // Title, id
            try stdout.print("\n{s}{s}{s} {s}({s}){s}\n", .{
                args.ANSIGreen, self.res.value.data[i].attributes.title.en, "\x1b[0m",
                args.ANSIBlack, self.res.value.data[i].id, "\x1b[0m"
            });
            // Status, year, last volume, last chapter
            try stdout.print(
                "Status: {s}{s}{s} Published: {s}{?}{s} Last volume: {s}{s}{s} Last chapter: {s}{s}{s}\n",
                .{
                    args.ANSIBlue, self.res.value.data[i].attributes.status, "\x1b[0m",
                    args.ANSIBlue, self.res.value.data[i].attributes.year, "\x1b[0m",
                    args.ANSIBlue, if(self.res.value.data[i].attributes.lastVolume) |s| s else "?", "\x1b[0m",
                    args.ANSIBlue, if(self.res.value.data[i].attributes.lastChapter) |s| s else "?", "\x1b[0m"
                }
            );
            // Tags
            try stdout.print("Tags: ", .{});
            for(self.res.value.data[i].attributes.tags) |t| {
                try stdout.print("[{s}{s}{s}]", .{ args.ANSIYellow, t.attributes.name.en, "\x1b[0m" });
                try stdout.writeByte(' ');
            }
            _ = try stdout.write("\x1b[0m\n");
            // Languages
            try stdout.print("Languages: {s}", .{ args.ANSIMagenta });
            for(self.res.value.data[i].attributes.availableTranslatedLanguages) |lang| {
                _ = try stdout.write(lang);
                try stdout.writeByte(' ');
            }
            _ = try stdout.write("\x1b[0m\n\n");
            // Description
            _ = try stdout.write(
                if(self.res.value.data[i].attributes.description.object.get("en")) |s| s.string else "No description"
            );
            _ = try stdout.write("\n\n");
            try bufw.flush();
        }
    }

    pub fn print(self: *Self, color: bool) !void {
        if(color) {
            try self.printrColor(0, self.res.value.data.len);
        } else {
            try self.printr(0, self.res.value.data.len);
        }
    }
};

pub fn searchManga(title: []const u8, allocator: std.mem.Allocator) !MangaSearchResults {
    var client = std.http.Client{ .allocator = allocator };
    var link = try std.fmt.allocPrint(allocator, "https://api.mangadex.org/manga?title={s}", .{ title });
    defer allocator.free(link);
    var req = try client.request(
        .GET, try std.Uri.parse(link), .{ .allocator = allocator }, .{}
    );
    defer req.deinit();
    try req.start();
    try req.wait();

    var buf = try req.reader().readAllAlloc(allocator, 10_000_000);
    var parsed = try std.json.parseFromSlice(MangaSearchRes, allocator, buf, .{
        .ignore_unknown_fields = true
    });

    return MangaSearchResults {
        ._buf = buf,
        .allocator = allocator,
        .res = parsed
    };
}

const MangaVolChDataChapter = struct {
    chapter: []const u8,
    id: []const u8,
    others: [][]const u8,
    count: u32
};

pub const MangaVolChRes = struct {
    result: []const u8,
    volumes: std.json.Value
};

pub const MangaVolChResults = struct {
    const Self = @This();

    _buf: []u8,
    allocator: std.mem.Allocator,
    res: std.json.Parsed(MangaVolChRes),

    pub fn deinit(self: *Self) void {
        self.res.deinit();
        self.allocator.free(self._buf);
    }

    pub fn printr(self: *Self, start: usize, end: usize) !void {
        var bufw = std.io.bufferedWriter(std.io.getStdIn().writer());
        var stdout = bufw.writer();
        var iter = self.res.value.volumes.object.iterator();
        var i = start;
        while(iter.next()) |entry| {
            if(i >= end) { break; }

            try stdout.print("Volume {s}\n", .{ entry.key_ptr.* });
            var ch_iter = entry.value_ptr.*.object.get("chapters").?.object.iterator();
            while(ch_iter.next()) |ch| {
                var chapter = try std.json.parseFromValue(
                    MangaVolChDataChapter, std.heap.page_allocator, ch.value_ptr.*,
                    .{ .ignore_unknown_fields = true }
                );
                defer chapter.deinit();
                try stdout.print("    Chapter {s} ({s})\n", .{ chapter.value.chapter, chapter.value.id });
            }
            try stdout.writeByte('\n');
            try bufw.flush();
            i += 1;
        }
    }

    pub fn printrColor(self: *Self, start: usize, end: usize) !void {
        var bufw = std.io.bufferedWriter(std.io.getStdIn().writer());
        var stdout = bufw.writer();
        var iter = self.res.value.volumes.object.iterator();
        var i = start;
        while(iter.next()) |entry| {
            if(i >= end) { break; }

            try stdout.print("{s}Volume {s}{s}\n", .{ args.ANSIGreen, entry.key_ptr.*, "\x1b[0m" });
            var ch_iter = entry.value_ptr.*.object.get("chapters").?.object.iterator();
            while(ch_iter.next()) |ch| {
                var chapter = try std.json.parseFromValue(
                    MangaVolChDataChapter, std.heap.page_allocator, ch.value_ptr.*,
                    .{ .ignore_unknown_fields = true }
                );
                defer chapter.deinit();
                try stdout.print("    Chapter {s} {s}({s}){s}\n", .{
                    chapter.value.chapter, args.ANSIBlack, chapter.value.id, "\x1b[0m"
                });
            }
            try stdout.writeByte('\n');
            try bufw.flush();
            i += 1;
        }
    }

    pub fn print(self: *Self, color: bool) !void {
        if(color) {
            try self.printrColor(0, self.res.value.volumes.object.count());
        } else {
            try self.printr(0, self.res.value.volumes.object.count());
        }
    }
};

pub fn getMangaVolCh(lang: []const u8, id: []const u8, allocator: std.mem.Allocator) !MangaVolChResults {
    var client = std.http.Client{ .allocator = allocator };
    var link = try std.fmt.allocPrint(
        allocator, "https://api.mangadex.org/manga/{s}/aggregate?translatedLanguage[]={s}",
        .{ id, lang }
    );
    defer allocator.free(link);
    var req = try client.request(
        .GET, try std.Uri.parse(link), .{ .allocator = allocator }, .{}
    );
    defer req.deinit();
    try req.start();
    try req.wait();

    var buf = try req.reader().readAllAlloc(allocator, 10_000_000);
    var parsed = try std.json.parseFromSlice(MangaVolChRes, allocator, buf, .{
        .ignore_unknown_fields = true
    });

    return MangaVolChResults {
        ._buf = buf,
        .allocator = allocator,
        .res = parsed
    };
}
