/// MIT License

/// Copyright (c) 2023 Aoutnheub

/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:

/// The above copyright notice and this permission notice shall be included in all
/// copies or substantial portions of the Software.

/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
/// SOFTWARE.

/// Tested on Zig version: 0.11.0

const std = @import("std");

/// Used for coloring output of `Parser.help`
pub const ANSICode = *const [5:0]u8;

pub const ANSIDefault: ANSICode = "\x1b[39m";
pub const ANSIBGDefault: ANSICode = "\x1b[49m";
pub const ANSIBlack: ANSICode = "\x1b[30m";
pub const ANSIRed: ANSICode = "\x1b[31m";
pub const ANSIGreen: ANSICode = "\x1b[32m";
pub const ANSIYellow: ANSICode = "\x1b[33m";
pub const ANSIBlue: ANSICode = "\x1b[34m";
pub const ANSIMagenta: ANSICode = "\x1b[35m";
pub const ANSICyan: ANSICode = "\x1b[36m";
pub const ANSIWhite: ANSICode = "\x1b[37m";
pub const ANSIBGBlack: ANSICode = "\x1b[40m";
pub const ANSIBGRed: ANSICode = "\x1b[41m";
pub const ANSIBGGreen: ANSICode = "\x1b[42m";
pub const ANSIBGYellow: ANSICode = "\x1b[43m";
pub const ANSIBGBlue: ANSICode = "\x1b[44m";
pub const ANSIBGMagenta: ANSICode = "\x1b[45m";
pub const ANSIBGCyan: ANSICode = "\x1b[46m";
pub const ANSIBGWhite: ANSICode = "\x1b[47m";

pub const Results = struct {
    allocator: std.mem.Allocator,
    /// Stores flag values after parsing
    flag: ?std.hash_map.StringHashMap(bool) = null,
    /// Stores option values after parsing
    option: ?std.hash_map.StringHashMap([]const u8) = null,
    /// Stores positional arguments after parsing
    positional: ?std.ArrayList([]const u8) = null,
    /// Stores the command after parsing
    command: ?[]u8 = null,

    pub fn deinit(self: *Results) void {
        if(self.flag != null) { self.flag.?.deinit(); }
        if(self.option != null) { self.option.?.deinit(); }
        if(self.positional != null) { self.positional.?.deinit(); }
        if(self.command != null) { self.allocator.free(self.command.?); }
    }
};

const Option = struct {
    help: []const u8 = "",
    defaults_to: ?[]const u8 = "",
    allowed: ?std.ArrayList([]const u8) = null,

    pub fn deinit(self: *Option) void {
        self.allowed.deinit();
    }
};

pub const ParserError = error{
    DuplicateArgument,
    InvalidArgument,
    InvalidValue,
    MissingValue
};

pub const Parser = struct {
    // Everything with _ at the start is internal stuff.
    // Changing values manually may cause pain, bleeding or even death
    _flags: std.hash_map.StringHashMap([]const u8),
    _flags_abbr: std.array_hash_map.AutoArrayHashMap(u8, []const u8),
    _options: std.hash_map.StringHashMap(Option),
    _options_abbr: std.array_hash_map.AutoArrayHashMap(u8, []const u8),
    _commands: std.hash_map.StringHashMap([]const u8),
    _name: []const u8,
    _description: []const u8,
    // Error messages
    _err_buf: [1024]u8,
    err: ?[]const u8,
    /// Allocator
    allocator: std.mem.Allocator,
    /// Return an error if the first argument isn't a command. Ignored if no
    /// commands have been added
    command_required: bool,
    /// Header displayed by the `help` function before the command descriptions
    commands_help_msg: []const u8,
    /// Header displayed by the `help` function before the flag descriptions
    flags_help_msg: []const u8,
    /// Header displayed by the `help` function before the option descriptions
    options_help_msg: []const u8,
    /// Color the output of the `help` function
    colors: bool,
    /// Color of the title outputed by the `help` function
    title_color: ANSICode,
    /// Color of the description outputed by the `help` function
    description_color: ANSICode,
    /// Color of the headers outputed by the `help` function
    header_color: ANSICode,
    /// Color of the command names outputed by the `help` function
    command_color: ANSICode,
    /// Color of the command's description outputed by the `help` function
    command_description_color: ANSICode,
    /// Color of the flag names outputed by the `help` function
    flag_color: ANSICode,
    /// Color of the flag's description outputed by the `help` function
    flag_description_color: ANSICode,
    /// Color of the option names outputed by the `help` function
    option_color: ANSICode,
    /// Color of the option's description outputed by the `help` function
    option_description_color: ANSICode,
    /// Color of the option's allowed values outputed by the `help` function
    option_allowed_color: ANSICode,

    fn getFlagsAbbr(self: *Parser) !std.array_hash_map.StringArrayHashMap(u8) {
        var abbr = std.array_hash_map.StringArrayHashMap(u8).init(self.allocator);
        var flags_abbr_iter = self._flags_abbr.iterator();
        while(flags_abbr_iter.next()) |entry| {
            try abbr.put(entry.value_ptr.*, entry.key_ptr.*);
        }

        return abbr;
    }

    fn getOptionsAbbr(self: *Parser) !std.array_hash_map.StringArrayHashMap(u8) {
        var abbr = std.array_hash_map.StringArrayHashMap(u8).init(self.allocator);
        var options_abbr_iter = self._options_abbr.iterator();
        while(options_abbr_iter.next()) |entry| {
            try abbr.put(entry.value_ptr.*, entry.key_ptr.*);
        }

        return abbr;
    }

    fn isAllowedOptionValue(self: Parser, opt: []const u8, val: []const u8) bool {
        var option = self._options.get(opt);
        var allowed = false;
        if(option) |op| {
            if(op.allowed) |alw| {
                if(alw.items.len != 0) {
                    for(alw.items) |itm| {
                        if(std.mem.eql(u8, itm, val)) {
                            allowed = true;
                            break;
                        }
                    }
                } else {
                    allowed = true;
                }
            } else {
                return true;
            }
        }

        return allowed;
    }

    pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) Parser {
        return Parser{
            ._name = name,
            ._description = description,
            ._flags = std.hash_map.StringHashMap([]const u8).init(allocator),
            ._flags_abbr = std.array_hash_map.AutoArrayHashMap(u8, []const u8).init(allocator),
            ._options = std.hash_map.StringHashMap(Option).init(allocator),
            ._options_abbr = std.array_hash_map.AutoArrayHashMap(u8, []const u8).init(allocator),
            ._commands = std.hash_map.StringHashMap([]const u8).init(allocator),
            ._err_buf = undefined,
            .err = null,
            .allocator = allocator,
            .command_required = false,
            .commands_help_msg = "COMMANDS",
            .flags_help_msg = "FLAGS",
            .options_help_msg = "OPTIONS",
            .colors = false,
            .title_color = ANSIGreen,
            .description_color = ANSIWhite,
            .header_color = ANSIRed,
            .command_color = ANSIMagenta,
            .command_description_color = ANSIWhite,
            .flag_color = ANSIBlue,
            .flag_description_color = ANSIWhite,
            .option_color = ANSIBlue,
            .option_description_color = ANSIWhite,
            .option_allowed_color = ANSIYellow,
        };
    }

    pub fn deinit(self: *Parser) void {
        self._flags.deinit();
        self._flags_abbr.deinit();
        self._options.deinit();
        self._options_abbr.deinit();
        self._commands.deinit();
    }

    /// Add a flag
    /// @param name flag's name
    /// @param help flag's description
    /// @param abbr (optional) flag's abbreviation
    /// @return error or void
    ///     Error types:
    ///         - ParserError.DuplicateArgument (.err field contains the duplicate argument)
    ///         - Allocator.Error
    pub fn addFlag(
        self: *Parser,
        comptime name: []const u8,
        comptime help_: []const u8,
        comptime abbr: ?u8
    ) !void {
        if(!self._flags.contains(name) and !self._options.contains(name)) {
            if(abbr) |ab| {
                if(!self._flags_abbr.contains(ab) and !self._options_abbr.contains(ab)) {
                    try self._flags.put(name, help_);
                    try self._flags_abbr.put(ab, name);
                } else {
                    self.err = try std.fmt.bufPrint(&self._err_buf, "{c}", .{ ab });
                    return ParserError.DuplicateArgument;
                }
            } else {
                try self._flags.put(name, help_);
            }
        } else {
            self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ name });
            return ParserError.DuplicateArgument;
        }
    }

    /// Add an option
    /// @param name option's name
    /// @param help option's description
    /// @param abbr (optional) option's abbreviation
    /// @param defaultsTo option's default value
    /// @param allowed (optional) option's allowed values. Doesn't necessarily need to contain the default value
    /// @return error or void
    ///     Error types:
    ///         - ParserError.DuplicateArgument (.err field contains the duplicate argument)
    ///         - Allocator.Error
    pub fn addOption(self: *Parser, name: []const u8, help_: []const u8, abbr: ?u8, defaults_to: ?[]const u8, allowed: ?std.ArrayList([]const u8)) !void {
        if(!self._flags.contains(name) and !self._options.contains(name)) {
            if(abbr) |ab| {
                if(!self._flags_abbr.contains(ab) and !self._options_abbr.contains(ab)) {
                    try self._options.put(name, Option{ .help = help_, .defaults_to = defaults_to, .allowed = allowed });
                    try self._options_abbr.put(ab, name);
                } else {
                    self.err = try std.fmt.bufPrint(&self._err_buf, "{c}", .{ ab });
                    return ParserError.DuplicateArgument;
                }
            } else {
                try self._options.put(name, Option{ .help = help_, .defaults_to = defaults_to, .allowed = allowed });
            }
        } else {
            self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ name });
            return ParserError.DuplicateArgument;
        }
    }

    /// Add a command
    /// @param name command's name
    /// @param help command's description
    /// @return error or void
    ///     Error types:
    ///         - ParserError.DuplicateArgument (.err field contains the duplicate argument)
    ///         - Allocator.Error
    pub fn addCommand(self: *Parser, name: []const u8, help_: []const u8) !void {
        if(!self._commands.contains(name)) {
            try self._commands.put(name, help_);
        } else {
            self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ name });
            return ParserError.DuplicateArgument;
        }
    }

    /// Display the help message
    /// @return error or void
    pub fn help(self: *Parser) !void {
        var buf_writer = std.io.bufferedWriter(std.io.getStdOut().writer());
        const stdout = buf_writer.writer();
        if(!std.mem.eql(u8, self._name, "")) {
            if(self.colors) { try stdout.print("{s}", .{ self.title_color }); }
            try stdout.print("{s}", .{ self._name });
            if(self.colors) { try stdout.print("\x1b[0m", .{}); }
        }
        if(!std.mem.eql(u8, self._description, "")) {
            if(self.colors) { try stdout.print("{s}", .{ self.description_color }); }
            try stdout.print(" - ", .{});
            var indent = std.mem.zeroes([64:0]u8);
            var indent_size = self._name.len + 3;
            if(indent_size > 64) { indent_size = 64; }
            while(indent_size > 0) {
                indent[indent_size - 1] = ' ';
                indent_size -= 1;
            }
            var tokens = std.mem.tokenize(u8, self._description, "\n");
            var first_token = true;
            while(tokens.next()) |token| {
                if(first_token) {
                    try stdout.print("{s}\n", .{ token });
                    first_token = false;
                } else {
                    try stdout.print("{s}{s}\n", .{ &indent, token });
                }
            }
            if(self.colors) { try stdout.print("\x1b[0m", .{}); }
        } else {
            try stdout.print("\n", .{});
        }
        try stdout.print("\n", .{});

        if(self._commands.count() != 0) {
            if(!std.mem.eql(u8, self.commands_help_msg, "")) {
                if(self.colors) { try stdout.print("{s}", .{ self.header_color }); }
                try stdout.print("{s}", .{ self.commands_help_msg });
                if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                try stdout.print("\n", .{});
            }
            var commands_iter = self._commands.iterator();
            while(commands_iter.next()) |entry| {
                if(self.colors) { try stdout.print("{s}", .{ self.command_color }); }
                try stdout.print("    {s}", .{ entry.key_ptr.* });
                if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                try stdout.print("\n", .{});
                if(!std.mem.eql(u8, entry.value_ptr.*, "")) {
                    if(self.colors) { try stdout.print("{s}", .{ self.command_description_color }); }
                    var tokens = std.mem.tokenize(u8, entry.value_ptr.*, "\n");
                    while(tokens.next()) |token| {
                        try stdout.print("        {s}\n", .{ token });
                    }
                    if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                }
                try stdout.print("\n", .{});
            }
        }

        if(self._flags.count() != 0) {
            var abbr = try self.getFlagsAbbr();
            if(!std.mem.eql(u8, self.flags_help_msg, "")) {
                if(self.colors) { try stdout.print("{s}", .{ self.header_color }); }
                try stdout.print("{s}", .{ self.flags_help_msg });
                if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                try stdout.print("\n", .{});
            }
            var flags_iter = self._flags.iterator();
            while(flags_iter.next()) |entry| {
                if(self.colors) { try stdout.print("{s}", .{ self.flag_color }); }
                try stdout.print("    --{s}", .{ entry.key_ptr.* });
                var tmp = abbr.get(entry.key_ptr.*);
                if(tmp != null) { try stdout.print(", -{c}", .{ tmp.? }); }
                if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                try stdout.print("\n", .{});
                if(!std.mem.eql(u8, entry.value_ptr.*, "")) {
                    if(self.colors) { try stdout.print("{s}", .{ self.flag_description_color }); }
                    var tokens = std.mem.tokenize(u8, entry.value_ptr.*, "\n");
                    while(tokens.next()) |token| {
                        try stdout.print("        {s}\n", .{ token });
                    }
                    if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                }
                try stdout.print("\n", .{});
            }
        }

        if(self._options.count() != 0) {
            var abbr = try self.getOptionsAbbr();
            if(!std.mem.eql(u8, self.options_help_msg, "")) {
                if(self.colors) { try stdout.print("{s}", .{ self.header_color }); }
                try stdout.print("{s}", .{ self.options_help_msg });
                if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                try stdout.print("\n", .{});
            }
            var options_iter = self._options.iterator();
            while(options_iter.next()) |entry| {
                if(self.colors) { try stdout.print("{s}", .{ self.option_color }); }
                try stdout.print("    --{s}", .{ entry.key_ptr.* });
                var tmp = abbr.get(entry.key_ptr.*);
                if(tmp != null) { try stdout.print(", -{c}", .{ tmp.? }); }
                if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                if(entry.value_ptr.*.allowed != null) {
                    if(self.colors) { try stdout.print("{s}", .{ self.option_allowed_color }); }
                    try stdout.print(" ", .{});
                    for(entry.value_ptr.*.allowed.?.items, 0..) |alw, idx| {
                        try stdout.print("{s}", .{ alw });
                        if(idx != entry.value_ptr.*.allowed.?.items.len - 1) {
                            try stdout.print("|", .{});
                        }
                    }
                    if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                }
                try stdout.print("\n", .{});
                if(!std.mem.eql(u8, entry.value_ptr.*.help, "")) {
                    if(self.colors) { try stdout.print("{s}", .{ self.option_description_color }); }
                    var tokens = std.mem.tokenize(u8, entry.value_ptr.*.help, "\n");
                    while(tokens.next()) |token| {
                        try stdout.print("        {s}\n", .{ token });
                    }
                    if(self.colors) { try stdout.print("\x1b[0m", .{}); }
                }
                try stdout.print("\n", .{});
            }
        }

        try buf_writer.flush();
    }

    /// Parse the command line arguments
    /// @return A `Results` type with the parsed arguments or error
    ///     Error types:
    ///         - ParserError.InvalidArgument (.err field contains the invalid argument)
    ///         - ParserError.InvalidValue (.err field contains the option with an invalid value)
    ///         - ParserError.MissingValue (.err field contains the option missing a value)
    ///         - Allocator.Error
    pub fn parse(self: *Parser, args: [][:0]u8) !Results {
        var results = Results{
            .allocator = self.allocator,
            .flag = null,
            .option = null,
            .positional = std.ArrayList([]const u8).init(self.allocator),
            .command = null,
        };
        if(self._flags.count() != 0) {
            results.flag = std.hash_map.StringHashMap(bool).init(self.allocator);
        }
        if(self._options.count() != 0) {
            results.option = std.hash_map.StringHashMap([]const u8).init(self.allocator);
            var iter = self._options.iterator();
            while(iter.next()) |entry| {
                if(entry.value_ptr.*.defaults_to != null) {
                    try results.option.?.put(entry.key_ptr.*, entry.value_ptr.*.defaults_to.?);
                }
            }
        }
        defer {
            if(self._options.count() != 0 and results.option.?.count() == 0) {
                results.option.?.deinit();
            }
        }

        var i: usize = 1;
        var skip_command_check = false;
        while(i < args.len) {
            if(!skip_command_check and i == 1 and self._commands.count() != 0) {
                if(self._commands.contains(args[i])) {
                    var cmd_cpy = try self.allocator.alloc(u8, args[i].len);
                    std.mem.copy(u8, cmd_cpy, args[i]);
                    results.command = cmd_cpy;
                    i += 1;
                } else {
                    if(self.command_required) {
                        self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ args[i] });
                        return ParserError.InvalidArgument;
                    }
                }
                skip_command_check = true;
            } else {
                if(std.mem.eql(u8, args[i], "--")) {
                    for(args) |val| {
                        try results.positional.?.append(val);
                    }
                    i = args.len;
                } else {
                    if(args[i].len > 2) {
                        if(args[i][0] == '-' and args[i][1] != '-') {
                            var equals = std.mem.indexOf(u8, args[i], "=");
                            if(equals != null) {
                                if(equals.? == 2) { // option
                                    var op = self._options_abbr.get(args[i][1]);
                                    if(op != null) {
                                        if(args[i].len > 3) {
                                            var tmp = args[i][3..];
                                            if(self.isAllowedOptionValue(op.?, tmp)) {
                                                try results.option.?.put(op.?, tmp);
                                                i += 1;
                                            } else {
                                                self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op.? });
                                                return ParserError.InvalidValue;
                                            }
                                        } else {
                                            self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op.? });
                                            return ParserError.MissingValue;
                                        }
                                    }
                                } else { // multiple flags and one option
                                    var ii: usize = 1;
                                    while(ii < equals.? - 1) {
                                        var fl = self._flags_abbr.get(args[i][ii]);
                                        if(fl != null) {
                                            try results.flag.?.put(fl.?, true);
                                        } else {
                                            self.err = try std.fmt.bufPrint(&self._err_buf, "{c}", .{ args[i][ii] });
                                            return ParserError.InvalidArgument;
                                        }
                                        ii += 1;
                                    }
                                    if(equals.? + 1 < args[i].len) {
                                        var op = self._options_abbr.get(args[i][equals.? - 1]);
                                        if(op != null) {
                                            var tmp = args[i][equals.? + 1..];
                                            if(self.isAllowedOptionValue(op.?, tmp)) {
                                                try results.option.?.put(op.?, tmp);
                                            } else {
                                                self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op.? });
                                                return ParserError.MissingValue;
                                            }
                                        }
                                    } else {
                                        self.err = try std.fmt.bufPrint(&self._err_buf, "{c}", .{ args[i][ii] });
                                        return ParserError.MissingValue;
                                    }
                                    i += 1;
                                }
                            } else { // option and value with no space
                                var op = self._options_abbr.get(args[i][1]);
                                if(op != null) {
                                    var tmp = args[i][2..];
                                    if(self.isAllowedOptionValue(op.?, tmp)) {
                                        try results.option.?.put(op.?, tmp);
                                    } else {
                                        self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op.? });
                                        return ParserError.MissingValue;
                                    }
                                } else { // multiple flags
                                    var ii: usize = 1;
                                    while(ii < args[i].len) {
                                        var fl = self._flags_abbr.get(args[i][ii]);
                                        if(fl != null) {
                                            try results.flag.?.put(fl.?, true);
                                        } else {
                                            self.err = try std.fmt.bufPrint(&self._err_buf, "{c}", .{ args[i][ii] });
                                            return ParserError.InvalidArgument;
                                        }
                                        ii += 1;
                                    }
                                }
                                i += 1;
                            }
                        } else if(args[i][0] == '-' and args[i][1] == '-') {
                            var equals = std.mem.indexOf(u8, args[i], "=");
                            if(equals != null) {
                                var op = args[i][2..equals.?];
                                var val: []u8 = undefined;
                                if(equals.? + 1 < args[i].len) {
                                    val = args[i][equals.? + 1..];
                                } else {
                                    self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op });
                                    return ParserError.MissingValue;
                                }
                                if(self.isAllowedOptionValue(op, val)) {
                                    try results.option.?.put(op, val);
                                } else {
                                    self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op });
                                    return ParserError.InvalidValue;
                                }
                                i += 1;
                            } else {
                                var arg = args[i][2..];
                                if(self._flags.contains(arg)) {
                                    try results.flag.?.put(arg, true);
                                    i += 1;
                                } else {
                                    if(self._options.contains(arg)) {
                                        if(i + 1 < args.len) {
                                            if(args[i + 1].len == 0) {
                                                try results.option.?.put(arg, args[i + 1]);
                                            } else {
                                                if(args[i + 1][0] != '-') {
                                                    if(self.isAllowedOptionValue(arg, args[i + 1])) {
                                                        try results.option.?.put(arg, args[i + 1]);
                                                    } else {
                                                        self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ arg });
                                                        return ParserError.InvalidValue;
                                                    }
                                                } else {
                                                    self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ arg });
                                                    return ParserError.MissingValue;
                                                }
                                            }
                                        } else {
                                            self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ arg });
                                            return ParserError.MissingValue;
                                        }
                                        i += 2;
                                    } else {
                                        self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ arg });
                                        return ParserError.InvalidArgument;
                                    }
                                }
                            }
                        } else {
                            try results.positional.?.append(args[i]);
                            i += 1;
                        }
                    } else if(args[i].len == 2) {
                        if(args[i][0] == '-') {
                            var fl = self._flags_abbr.get(args[i][1]);
                            if(fl != null) {
                                try results.flag.?.put(fl.?, true);
                                i += 1;
                            } else {
                                var op = self._options_abbr.get(args[i][1]);
                                if(op != null) {
                                    if(i + 1 < args.len) {
                                        if(args[i + 1].len == 0) {
                                            try results.option.?.put(op.?, args[i + 1]);
                                        } else {
                                            if(args[i + 1][0] != '-') {
                                                try results.option.?.put(op.?, args[i + 1]);
                                            } else {
                                                self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op.? });
                                                return ParserError.MissingValue;
                                            }
                                        }
                                    } else {
                                        self.err = try std.fmt.bufPrint(&self._err_buf, "{s}", .{ op.? });
                                        return ParserError.MissingValue;
                                    }
                                    i += 2;
                                } else {
                                    self.err = try std.fmt.bufPrint(&self._err_buf, "{c}", .{ args[i][1] });
                                    return ParserError.InvalidArgument;
                                }
                            }
                        } else {
                            try results.positional.?.append(args[i]);
                            i += 1;
                        }
                    } else {
                        try results.positional.?.append(args[i]);
                        i += 1;
                    }
                }
            }
        }

        if(results.positional.?.items.len == 0) {
            results.positional.?.deinit();
            results.positional = null;
        }

        return results;
    }
};

