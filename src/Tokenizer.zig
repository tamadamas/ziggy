const Tokenizer = @This();
const std = @import("std");

idx: usize = 0,

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Tag = enum {
        invalid,
        dot,
        comma,
        eql,
        at,
        lp,
        rp,
        lb,
        rb,
        lsb,
        rsb,
        ident,
        str,
        number,
        // never generated by the tokenizer but
        // used elsewhere
        true,
        false,
        eof,

        pub fn lexeme(self: Tag) []const u8 {
            return switch (self) {
                .invalid => "(invalid)",
                .dot => ".",
                .comma => ",",
                .eql => "=",
                .at => "@",
                .lp => "(",
                .rp => ")",
                .lb => "{",
                .rb => "}",
                .lsb => "[",
                .rsb => "]",
                .ident => "(identifier)",
                .str => "(string)",
                .number => "(number)",
                .true => "true",
                .false => "false",
                .eof => "EOF",
            };
        }
    };

    pub const Loc = struct {
        start: usize,
        end: usize,

        pub fn src(self: Loc, code: []const u8) []const u8 {
            return code[self.start..self.end];
        }

        pub const Selection = struct {
            start: Position,
            end: Position,

            pub const Position = struct {
                line: usize,
                col: usize,
            };
        };
        pub fn getSelection(self: Loc, code: []const u8) Selection {
            return .{
                .start = getPos(code[0..self.start]),
                .end = getPos(code[self.start..self.end]),
            };
        }

        fn getPos(code: []const u8) Selection.Position {
            var res: Selection.Position = .{
                .line = 0,
                .col = undefined,
            };

            var it = std.mem.splitScalar(u8, code, '\n');
            var last_line: []const u8 = "";

            while (it.next()) |line| {
                last_line = line;
                res.line += 1;
            }

            //TODO: ziglyph
            res.col = last_line.len + 1;
            return res;
        }

        pub fn unquote(self: Loc, code: []const u8) ?[]const u8 {
            const s = code[self.start..self.end];
            const quoteless = s[1 .. s.len - 1];

            for (quoteless) |c| {
                if (c == '\\') return null;
            } else {
                return quoteless;
            }
        }

        pub fn unescape(
            self: Loc,
            gpa: std.mem.Allocator,
            code: []const u8,
        ) ![]const u8 {
            const s = code[self.start..self.end];
            const quoteless = s[1 .. s.len - 1];

            for (quoteless) |c| {
                if (c == '\\') break;
            } else {
                return quoteless;
            }

            const quote = s[0];
            var out = std.ArrayList(u8).init(gpa);
            var last = quote;
            var skipped = false;
            for (quoteless) |c| {
                if (c == '\\' and last == '\\' and !skipped) {
                    skipped = true;
                    last = c;
                    continue;
                }
                if (c == quote and last == '\\' and !skipped) {
                    out.items[out.items.len - 1] = quote;
                    last = c;
                    continue;
                }
                try out.append(c);
                skipped = false;
                last = c;
            }
            return try out.toOwnedSlice();
        }
    };
};

const State = enum {
    start,
    ident,
    number,
    string,
    comment_start,
    comment,
};

pub fn next(self: *Tokenizer, code: [:0]const u8) Token {
    var state: State = .start;
    var res: Token = .{
        .tag = .invalid,
        .loc = .{
            .start = self.idx,
            .end = undefined,
        },
    };

    while (true) : (self.idx += 1) {
        const c = code[self.idx];
        switch (state) {
            .start => switch (c) {
                0 => {
                    res.tag = .eof;
                    res.loc.start = code.len - 1;
                    res.loc.end = code.len;
                    break;
                },
                ' ', '\n' => res.loc.start += 1,
                '.' => {
                    self.idx += 1;
                    res.tag = .dot;
                    res.loc.end = self.idx;
                    break;
                },
                ',' => {
                    self.idx += 1;
                    res.tag = .comma;
                    res.loc.end = self.idx;
                    break;
                },
                '=' => {
                    self.idx += 1;
                    res.tag = .eql;
                    res.loc.end = self.idx;
                    break;
                },
                '@' => {
                    self.idx += 1;
                    res.tag = .at;
                    res.loc.end = self.idx;
                    break;
                },
                '(' => {
                    self.idx += 1;
                    res.tag = .lp;
                    res.loc.end = self.idx;
                    break;
                },
                ')' => {
                    self.idx += 1;
                    res.tag = .rp;
                    res.loc.end = self.idx;
                    break;
                },
                '[' => {
                    self.idx += 1;
                    res.tag = .lsb;
                    res.loc.end = self.idx;
                    break;
                },
                ']' => {
                    self.idx += 1;
                    res.tag = .rsb;
                    res.loc.end = self.idx;
                    break;
                },
                '{' => {
                    self.idx += 1;
                    res.tag = .lb;
                    res.loc.end = self.idx;
                    break;
                },
                '}' => {
                    self.idx += 1;
                    res.tag = .rb;
                    res.loc.end = self.idx;
                    break;
                },

                'a'...'z', 'A'...'Z', '_' => state = .ident,
                '-', '+', '0'...'9' => state = .number,
                '"', '\'' => state = .string,
                '/' => state = .comment_start,
                else => {
                    res.tag = .invalid;
                    res.loc.end = self.idx;
                    break;
                },
            },
            .ident => switch (c) {
                'a'...'z', 'A'...'Z', '_' => continue,
                else => {
                    res.tag = .ident;
                    res.loc.end = self.idx;
                    break;
                },
            },
            .number => switch (c) {
                '0'...'9', '.', '_' => continue,
                else => {
                    res.tag = .number;
                    res.loc.end = self.idx;
                    break;
                },
            },
            .string => switch (c) {
                0 => {
                    res.tag = .invalid;
                    res.loc.end = self.idx;
                    break;
                },

                '"', '\'' => if (c == code[res.loc.start] and
                    evenSlashes(code[0..self.idx]))
                {
                    self.idx += 1;
                    res.tag = .str;
                    res.loc.end = self.idx;
                    break;
                },
                else => {},
            },
            .comment_start => switch (c) {
                '/' => state = .comment,
                else => {
                    res.tag = .invalid;
                    res.loc.end = self.idx;
                    break;
                },
            },
            .comment => switch (c) {
                0, '\n' => {
                    state = .start;
                    self.idx -= 1;
                },
                else => continue,
            },
        }
    }

    return res;
}

fn evenSlashes(str: []const u8) bool {
    var i = str.len - 1;
    var even = true;
    while (true) : (i -= 1) {
        if (str[i] != '\\') break;
        even = !even;
        if (i == 0) break;
    }
    return even;
}

test "basics" {
    const case =
        \\.foo = "bar",
        \\.bar = false,
        \\.baz = { .bax = null },
    ;

    const expected: []const Token.Tag = &.{
        // zig fmt: off
        .dot, .ident, .eql, .str, .comma,
        .dot, .ident, .eql, .ident, .comma,
        .dot, .ident, .eql, .lb, .dot, .ident, .eql, .ident, .rb, .comma,
        // zig fmt: on
    };

    var t: Tokenizer = .{};

    for (expected, 0..) |e, idx| {
        errdefer std.debug.print("failed at index: {}\n", .{idx});
        const tok = t.next(case);
        errdefer std.debug.print("bad token: {any}\n", .{tok});
        try std.testing.expectEqual(e, tok.tag);
    }
        try std.testing.expectEqual(t.next(case).tag, .eof);
}

test "comments are skipped" {
    const case =
        \\.foo = "bar", // comment can be inline
        \\.bar = false,
        \\// bax must be null
        \\.baz = { .bax = null },
        \\// can end with a comment
        \\// or even two
    ;

    const expected: []const Token.Tag = &.{
        // zig fmt: off
        .dot, .ident, .eql, .str, .comma,
        .dot, .ident, .eql, .ident, .comma,
        .dot, .ident, .eql, .lb, .dot, .ident, .eql, .ident, .rb, .comma,
        // zig fmt: on
    };

    var t: Tokenizer = .{};

    for (expected, 0..) |e, idx| {
        errdefer std.debug.print("failed at index: {}\n", .{idx});
        const tok = t.next(case);
        errdefer std.debug.print("bad token: {any}\n", .{tok});
        try std.testing.expectEqual(e, tok.tag);
    }
        try std.testing.expectEqual(t.next(case).tag, .eof);
}

test "invalid comments" {
    const case =
        \\/invalid
        \\.foo = "bar",
        \\.bar = false,
        \\.baz = { .bax = null },
    ;

    const expected: []const Token.Tag = &.{
        // zig fmt: off
        .invalid, .ident,
        .dot, .ident, .eql, .str, .comma,
        .dot, .ident, .eql, .ident, .comma,
        .dot, .ident, .eql, .lb, .dot, .ident, .eql, .ident, .rb, .comma,
        // zig fmt: on
    };

    var t: Tokenizer = .{};

    for (expected, 0..) |e, idx| {
        errdefer std.debug.print("failed at index: {}\n", .{idx});
        const tok = t.next(case);
        errdefer std.debug.print("bad token: {any}\n", .{tok});
        try std.testing.expectEqual(e, tok.tag);
    }
        try std.testing.expectEqual(t.next(case).tag, .eof);
}
