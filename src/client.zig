const std = @import("std");

pub const ChapterData = struct {
    result: []const u8 = undefined,
    baseUrl: []const u8 = undefined,
    chapter: struct {
        hash: []const u8 = undefined,
        data: [][]const u8 = undefined,
        dataSaver: [][]const u8 = undefined
    } = undefined
};

pub const Client = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    client: std.http.Client,
    chapter_buf: []const u8,
    chapter_data: ?std.json.Parsed(ChapterData) = null,
    file_name: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, link: []const u8) !Self {
        var client = Self{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .chapter_buf = try allocator.alloc(u8, 0)
        };
        try client.getChapterData(link);

        return client;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
        self.allocator.free(self.chapter_buf);
        if(self.chapter_data) |cd| { cd.deinit(); }
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
            self.chapter_data.?.value.chapter.data,
            self.chapter_data.?.value.baseUrl,
            self.chapter_data.?.value.chapter.hash,
            "data", range, dw_start_callback, dw_end_callback
        );
    }

    pub fn downloadAllPagesDS(
        self: *Self, range: ?std.meta.Tuple(&.{ u32, u32 }),
        comptime dw_start_callback: fn(fname: []const u8) anyerror!void,
        comptime dw_end_callback: fn() anyerror!void,
    ) !void {
        try self.downloadAllPagesOfType(
            self.chapter_data.?.value.chapter.dataSaver,
            self.chapter_data.?.value.baseUrl,
            self.chapter_data.?.value.chapter.hash,
            "data-saver", range, dw_start_callback, dw_end_callback
        );
    }

    fn extractFileExtension(s: []const u8) []const u8 {
        return s[std.mem.lastIndexOf(u8, s, ".").?..];
    }

    fn getChapterData(self: *Client, link: []const u8) !void {
        var req = try self.client.request(
            .GET, try std.Uri.parse(link), .{ .allocator = self.allocator }, .{}
        );
        defer req.deinit();
        try req.start();
        try req.wait();
        self.chapter_buf = try req.reader().readAllAlloc(self.allocator, 10_000);
        self.chapter_data = try std.json.parseFromSlice(ChapterData, self.allocator, self.chapter_buf, .{});
    }

    fn downloadAllPagesOfType(
        self: *Self, iter: [][]const u8, base: []const u8, hash: []const u8,
        data: []const u8, range: ?std.meta.Tuple(&.{ u32, u32 }),
        comptime dw_start_callback: fn(fname: []const u8) anyerror!void,
        comptime dw_end_callback: fn() anyerror!void,
    ) !void {
        if(range != null) {
            if(range.?.@"1" + 1 > iter.len) {
                return error.InvalidRange;
            }
            for(range.?.@"0"..range.?.@"1" + 1) |i| {
                var fname = iter[i];
                if(self.file_name != null) {
                    fname = try std.fmt.allocPrint(self.allocator, "{s}{d:0>2}{s}", .{
                        self.file_name.?, i + 1, extractFileExtension(iter[i])
                    });
                }
                try dw_start_callback(fname);
                var page_link = try std.mem.concat(self.allocator, u8, &.{
                    base, "/", data ,"/", hash, "/", iter[i]
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
            for(iter) |l| {
                var fname = l;
                if(self.file_name != null) {
                    fname = try std.fmt.allocPrint(self.allocator, "{s}{d:0>2}{s}", .{
                        self.file_name.?, idx, extractFileExtension(l)
                    });
                }
                try dw_start_callback(fname);
                var page_link = try std.mem.concat(self.allocator, u8, &.{
                    base, "/", data ,"/", hash, "/", l
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