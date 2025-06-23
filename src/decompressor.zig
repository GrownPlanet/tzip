const std = @import("std");

const shared = @import("shared.zig");
const Code = shared.Code;
const readFile = shared.readFile;

pub fn decompress(in_filename: []const u8, out_filename: []const u8, allocator: std.mem.Allocator) !void {
    const file_contents = try readFile(in_filename, allocator);
    defer allocator.free(file_contents);
    var idx: usize = 0;

    const end_rem: u3 = @intCast(file_contents[0]);
    idx += 1;

    var codes = try readCode(file_contents, &idx, allocator);
    defer codes.deinit();
    std.log.info("read codes", .{});

    try decodeFile(file_contents, out_filename, codes, idx, end_rem);
    std.log.info("done!", .{});
}

// ===================== read codes =====================
fn readCode(file: []const u8, idx: *usize, allocator: std.mem.Allocator) !std.AutoHashMap(Code, u8) {
    const number_of_chars = readArbitrary(usize, u6, file, idx.*);
    idx.* += @sizeOf(usize);
    var codes = std.AutoHashMap(Code, u8).init(allocator);

    for (0..number_of_chars) |_| {
        const char = file[idx.*];
        const len: u5 = @truncate(file[idx.* + 1]);
        const bits = readArbitrary(u32, u5, file, idx.* + 2);
        idx.* += 2 + @sizeOf(u32);
        try codes.put(Code { .bits = bits, .len = len }, char);
    }

    return codes;
}

fn readArbitrary(comptime T: type, comptime LT: type, file: []const u8, idx: usize) T {
    var n: T = 0;
    for (0..@sizeOf(T)) |i| {
        const byte = file[i + idx];
        n |= @as(T, byte) << (@as(LT, @truncate(i)) * 8);
    }
    return n;
}

// ===================== read codes =====================
fn decodeFile(
    file: []const u8,
    out_filename: []const u8,
    codes: std.AutoHashMap(Code, u8),
    idx: usize,
    end_rem: u3,
) !void {
    var out_file = try std.fs.cwd().createFile(out_filename, .{});

    var buffer: u32 = 0;
    var buf_len: u5 = 0;

    for (idx..file.len) |i| {
        const byte = file[i];
        var j: u5 = 7;
        if (i + 1 == file.len) { j -= end_rem; }
        while (true) : (j -= 1) {
            const bit = (byte & (@as(u32, 1) << j)) >> j;
            buffer = (buffer << 1) | bit;
            buf_len += 1;
            if (codes.get(Code { .bits = buffer, .len = buf_len})) |char| {
                try out_file.writer().writeByte(char);
                buffer = 0;
                buf_len = 0;
            }
            if (j == 0) break;
        }
    }
}
