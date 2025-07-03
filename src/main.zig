const std = @import("std");

const compressor = @import("compressor.zig");
const decompressor = @import("decompressor.zig");

// info about single file compression:
// |unused end size: u8| |number of chars: u8|
// [|char: u8| |len: u5| |char: len| |char buffer space|]+
// |encoded file|
//
// info about combining files
// |mode: File: u8| |file name len: u32| |file name: []char| |file len: u32| |file contents: []char|
// |mode: Dir: u8| |dir name len: u32| |dir name: []char|

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.skip(); // skip the program path

    const mode = args.next() orelse { helpMessage(); return; };
    const in_filename = args.next() orelse { helpMessage(); return; };

    if (std.mem.eql(u8, mode, "compress")) {
        const out_filename = args.next() orelse { helpMessage(); return; };
        try compressor.compress(in_filename, out_filename, allocator);
    } else if (std.mem.eql(u8, mode, "decompress")) {
        try decompressor.decompress(in_filename, allocator);
    } else {
        helpMessage();
    }
}

fn helpMessage() void {
    std.log.err("missing argument: tz [compress | decompress] [input directory] [out filename (only when compressing)]", .{});
}
