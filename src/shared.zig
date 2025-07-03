const std = @import("std");

pub const Code = struct {
    bits: u32,
    len: u5,
};

pub const Mode = enum(u8) { File, Dir };

pub fn readFile(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);

    _ = try file.readAll(buffer);

    return buffer;
}
