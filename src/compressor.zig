const std = @import("std");
const expect = std.testing.expect;

const shared = @import("shared.zig");
const Code = shared.Code;
const Mode = shared.Mode;
const readFile = shared.readFile;

pub fn compress(in_filename: []const u8, out_filename: []const u8, allocator: std.mem.Allocator) !void {
    const contents = try combine(in_filename, allocator);
    defer contents.deinit();

    var elements = try countBits(contents.items, allocator);
    defer elements.deinit();

    var tree = try makeTree(&elements, allocator);
    defer tree.deinit();

    var codes = try makeCodes(tree, allocator);
    defer codes.deinit();
    std.log.info("generated codes", .{});

    const encoded = try encodeFile(contents.items, codes, allocator);
    defer encoded.list.deinit();
    std.log.info("encoded file", .{});

    try writeToFile(out_filename, codes, encoded);
    std.log.info("done!", .{});
}

fn binarySearch(
    comptime T: type,
    elements: []const T,
    value: T,
    compare: fn (context: void, a: T, b: T) bool,
) usize {
    var lo: usize = 0;
    var hi: usize = elements.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (compare({}, elements[mid], value)) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

// ===================== combine files =====================
fn combine(in_filename: []const u8, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var out_buffer = std.ArrayList(u8).init(allocator);
    
    const stat = try std.fs.cwd().statFile(in_filename);
    switch (stat.kind) {
        .directory => try combine_dir(in_filename, &out_buffer, allocator),
        .file => try combine_file(in_filename, &out_buffer, allocator),
        else => unreachable,
    }

    return out_buffer;
}

fn combine_dir(dirname: []const u8, out_buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out_buffer.append(@intFromEnum(Mode.Dir));

    try writeArbitraryBuffer(u32, @intCast(dirname.len), out_buffer);
    try out_buffer.appendSlice(dirname);

    var dir = try std.fs.cwd().openDir(dirname, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const new_path = try std.fs.path.join(allocator, &[_][]const u8{ dirname, entry.name });
        defer allocator.free(new_path);
        if (entry.kind == .directory) {
            try combine_dir(new_path, out_buffer, allocator);
        } else if (entry.kind == .file) {
            try combine_file(new_path, out_buffer, allocator);
        }
    }
}

fn combine_file(filename: []const u8, out_buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const file_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(file_buffer);

    const read = try file.readAll(file_buffer);
    if (read != file_size) return error.UnexpectedEof;

    try out_buffer.append(@intFromEnum(Mode.File));

    try writeArbitraryBuffer(u32, @intCast(filename.len), out_buffer);
    try out_buffer.appendSlice(filename);

    try writeArbitraryBuffer(u32, @intCast(file_size), out_buffer);
    try out_buffer.appendSlice(file_buffer);
}

// ===================== node =====================
const Node = struct {
    count: u32,
    data: union(enum) {
        Branch: BranchData,
        Leaf: LeafData,
    },
    allocator: std.mem.Allocator,

    pub const BranchData = struct {
        left: *Node,
        right: *Node,
    };

    pub const LeafData = struct {
        byte: u8,
    };

    pub fn deinit(self: *Node) void {
        switch (self.data) {
            .Leaf => {},
            .Branch => |b| {
                b.left.deinit();
                self.allocator.destroy(b.left);
                b.right.deinit();
                self.allocator.destroy(b.right);
            }
        }
    }

    fn compare(_: void, a: Node, b: Node) bool {
        return a.count > b.count;
    }
};


// ===================== count bits =====================
fn countBits(file: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Node) {
    var count = [_]u32{0} ** 256;
    for (file) |c| count[c] += 1;

    var elements = std.ArrayList(Node).init(allocator);
    for (count, 0..) |c, byte| {
        if (c != 0) {
            try elements.append(Node {
                .count = c,
                .data = .{ .Leaf = Node.LeafData { .byte = @intCast(byte) } },
                .allocator = allocator,
            });
        }
    }

    std.mem.sort(Node, elements.items, {}, Node.compare);

    return elements;
}

// ===================== make tree =====================
fn makeTree(elements: *std.ArrayList(Node), allocator: std.mem.Allocator) !Node {
    while (elements.items.len >= 2) {
        const smallest1 = try allocator.create(Node);
        const smallest2 = try allocator.create(Node);
        smallest1.* = elements.pop() orelse unreachable;
        smallest2.* = elements.pop() orelse unreachable;

        const new_node = Node {
            .count = smallest1.count + smallest2.count,
            .allocator = allocator,
            .data = .{ .Branch = Node.BranchData {
                .left = smallest1,
                .right = smallest2,
            }}
        };

        const idx = binarySearch(Node, elements.items, new_node, Node.compare);
        try elements.insert(idx, new_node);
    }

    const return_elem = elements.pop() orelse unreachable;
    return return_elem;
}

// ===================== make binary from tree =====================
fn makeCodes(tree: Node, allocator: std.mem.Allocator) !std.AutoHashMap(u8, Code) {
    var codes = std.AutoHashMap(u8, Code).init(allocator);
    try makeCodesIntern(&tree, 0, 0, &codes);
    return codes;
}

fn makeCodesIntern(branch: *const Node, bits: u32, len: u5, hm: *std.AutoHashMap(u8, Code)) !void {
    switch (branch.data) {
        .Leaf => |l| {
            try hm.put(l.byte, Code { .len = len, .bits = bits });
        },
        .Branch => |b| {
            try makeCodesIntern(b.left, (bits << 1) + 1, len + 1, hm);
            try makeCodesIntern(b.right, bits << 1, len + 1, hm);
        },
    }
}

// ===================== encode file =====================
const EncodedFile = struct {
    list: std.ArrayList(u8),
    end_rem: u3,
};

fn encodeFile(
    contents: []const u8, codes: std.AutoHashMap(u8, Code), allocator: std.mem.Allocator
) !EncodedFile {
    var bytes = std.ArrayList(u8).init(allocator);

    var buffer: u8 = 0;
    var buf_idx: u3 = 7;

    for (contents) |char| {
        const code = codes.get(char) orelse unreachable;

        var len = code.len;
        var bits = code.bits;

        while (len != 0) {
            len -= 1;
            // go from:
            //             v buf_idx
            // buffer: xxxx0000|
            // bits:       aaaa|aaa
            //
            // to:
            // buffer: xxxxa000|
            // bits:        aaa|aaa
            //
            // this takes the first `a` and puts it as the first `0`
            // => buffer: xxxxa000|
            buffer |= @as(u8, @intCast((bits & (@as(u32, 1) << len)) >> len)) << buf_idx;
            // this removes the fist `a` to put it in sync with the buffer
            // =>   bits:      aaaa|aaa
            bits &= ~(@as(u32, 1) << len);
            // if the buffer is full, push and clear it, else decrease the starting position for
            // writing to it
            if (buf_idx == 0) {
                try bytes.append(buffer);
                buffer = 0;
                buf_idx = 7;
            } else {
                buf_idx -= 1;
            }
        }
    }

    // if there are some things written to the buffer but it isn't full yet, push it anyway
    // but we keep the amount of the last byte that hasn't been written to
    if (buf_idx != 7) {
        try bytes.append(buffer);
    } else {
        buf_idx = 0;
    }

    return .{
        .list = bytes,
        .end_rem = buf_idx + 1,
    };
}

// ===================== write to file =====================
fn writeToFile(filename: []const u8, codes: std.AutoHashMap(u8, Code), encoded_file: EncodedFile) !void {
    // info:
    // |unused end size: u8| |number of chars: usize|
    // [|char: u8| |len: u5| |encoded char: u32|]+
    // |encoded file|
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    // metadata: unused end size
    try file.writeAll(&[_]u8{ @as(u8, encoded_file.end_rem) });

    // metadata: number of chars
    try writeArbitraryFile(usize, codes.count(), file);

    // metadata: chars
    var iter = codes.iterator();
    while (iter.next()) |code| {
        try file.writeAll(&[_]u8{ code.key_ptr.* });
        try file.writeAll(&[_]u8{ @as(u8, code.value_ptr.*.len) });
        try writeArbitraryFile(u32, code.value_ptr.*.bits, file);
    }

    // file
    try file.writeAll(encoded_file.list.items);
}

fn writeArbitraryFile(comptime T: type, num: T, file: std.fs.File) !void {
    var buffer: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buffer, num, .little);
    try file.writeAll(&buffer);
}

fn writeArbitraryBuffer(comptime T: type, num: T, out_buffer: *std.ArrayList(u8)) !void {
    var buffer: [@sizeOf(u32)]u8 = undefined;
    std.mem.writeInt(u32, &buffer, num, .little);
    try out_buffer.appendSlice(&buffer);
}
