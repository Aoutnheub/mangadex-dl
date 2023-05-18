const std = @import("std");

pub const ChapterData = struct {
    _buf: []u8 = undefined,
    base_url: []const u8 = undefined,
    hash: []const u8 = undefined,
    data: *const std.ArrayList(std.json.Value) = undefined,
    data_saver: *const std.ArrayList(std.json.Value) = undefined
};

pub const Client = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    client: std.http.Client = undefined,
    chapter_data: ChapterData = ChapterData{},
    file_name: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, link: []const u8) !Self {
        var client = Self{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator }
        };
        try client.getChapterData(link);

        return client;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
        self.allocator.free(self.chapter_data._buf);
    }

    pub fn downloadPage(self: *Client, link: []const u8, file_name: []const u8) !void {
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
    ) !void {
        try self.downloadAllPagesOfType(
            self.chapter_data.data, self.chapter_data.base_url, self.chapter_data.hash, "data",
            range, dw_start_callback, dw_end_callback
        );
    }

    pub fn downloadAllPagesDS(
        self: *Self, range: ?std.meta.Tuple(&.{ u32, u32 }),
        comptime dw_start_callback: fn(fname: []const u8) anyerror!void,
        comptime dw_end_callback: fn() anyerror!void,
    ) !void {
        try self.downloadAllPagesOfType(
            self.chapter_data.data_saver, self.chapter_data.base_url, self.chapter_data.hash, "data-saver",
            range, dw_start_callback, dw_end_callback
        );
    }

    fn extractFileExtension(s: []const u8) []const u8 {
        return s[std.mem.lastIndexOf(u8, s, ".").?..];
    }

    fn getChapterData(self: *Client, link: []const u8) !void {
        // Get
        var req = try self.client.request(
            .GET, try std.Uri.parse(link), .{ .allocator = self.allocator }, .{}
        );
        defer req.deinit();
        try req.start();
        try req.wait();
        self.chapter_data._buf = try req.reader().readAllAlloc(self.allocator, 10_000);

        // Parse
        var parser = std.json.Parser.init(self.allocator, std.json.AllocWhen.alloc_if_needed);
        defer parser.deinit();
        var ch_data_json = try parser.parse(self.chapter_data._buf);
        {
            var base = ch_data_json.root.object;
            var status = base.get("result").?.string;
            if(!std.mem.eql(u8, status, "ok")) {
                return error.Request;
            }
            self.chapter_data.base_url = base.get("baseUrl").?.string;
            var ch = base.get("chapter").?.object;
            self.chapter_data.hash = ch.get("hash").?.string;
            self.chapter_data.data = &(ch.get("data").?.array);
            self.chapter_data.data_saver = &(ch.get("dataSaver").?.array);
        }
    }

    fn downloadAllPagesOfType(
        self: *Self, iter: *const std.ArrayList(std.json.Value), base: []const u8, hash: []const u8,
        data: []const u8, range: ?std.meta.Tuple(&.{ u32, u32 }),
        comptime dw_start_callback: fn(fname: []const u8) anyerror!void,
        comptime dw_end_callback: fn() anyerror!void,
    ) !void {
        if(range != null) {
            if(range.?.@"1" + 1 > iter.items.len) {
                return error.InvalidRange;
            }
            for(range.?.@"0"..range.?.@"1" + 1) |i| {
                // Uncomment the next line if in debug mode or else it will segfault
                // std.debug.print("{any}\n", .{ iter.items[i] });
                var fname = iter.items[i].string;
                if(self.file_name != null) {
                    fname = try std.fmt.allocPrint(self.allocator, "{s}{d:0>2}{s}", .{
                        self.file_name.?, i + 1, extractFileExtension(iter.items[i].string)
                    });
                }
                try dw_start_callback(fname);
                var page_link = try std.mem.concat(self.allocator, u8, &.{
                    base, "/", data ,"/", hash, "/", iter.items[i].string
                });
                defer self.allocator.free(page_link);
                try self.downloadPage(page_link, fname);
                try dw_end_callback();
                if(self.file_name != null) {
                    self.allocator.free(fname);
                }
            }
        } else {
            var idx: usize = 1;
            for(iter.items) |l| {
                var fname = l.string;
                if(self.file_name != null) {
                    fname = try std.fmt.allocPrint(self.allocator, "{s}{d:0>2}{s}", .{
                        self.file_name.?, idx, extractFileExtension(l.string)
                    });
                }
                try dw_start_callback(fname);
                var page_link = try std.mem.concat(self.allocator, u8, &.{
                    base, "/", data ,"/", hash, "/", l.string
                });
                defer self.allocator.free(page_link);
                try self.downloadPage(page_link, fname);
                try dw_end_callback();
                if(self.file_name != null) {
                    self.allocator.free(fname);
                }
                idx += 1;
            }
        }
    }
};