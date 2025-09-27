const std = @import("std");
const prettier = @import("prettier");
const _ = std.Io.Writer;

const Alloc = std.mem.Allocator;
const gpa = std.heap.page_allocator;
const TAB: []const u8 = &[_]u8{ ' ', ' ' };

pub fn main() !void {
    // const tester = try testerStruct.init(gpa);
    const t: prettier.Options = .{};
    const opts: prettier.Options = .{ .indentSeq = TAB };

    // const opts: Options = .{};
    const val = .{ .a = .{ .b = 0, .c = t }, .d = std.Io.AnyReader, .easdfwlkwejlrjlkwejflkjasdasdfiasidfo = .{ .f = .{ .grgarrmrmrmrm = 5000000000 } } };

    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    try stdout_writer.interface.writeAll("val: ");
    try prettier.prettyPrintValue(&stdout_writer.interface, val, opts);
    try stdout_writer.interface.writeAll("\nprettier opts: ");
    try prettier.prettyPrintValue(&stdout_writer.interface, opts, opts);
    try stdout_writer.interface.flush();
}

const testerStruct = struct {
    alloc: Alloc,
    buff: std.Io.Writer.Allocating,

    const Self = @This();
    fn init(alloc: Alloc) !Self {
        const ret: @This() = @This(){ .alloc = alloc, .buff = try std.Io.Writer.Allocating.initCapacity(alloc, 512) };
        return ret;
    }

    fn deinit(s: *Self) !void {
        s.buff.deinit(s.alloc);
    }

    fn pushObjBuffRec(s: *Self, obj: anytype) !void {
        const type_T = @TypeOf(obj);
        const info_T = @typeInfo(type_T);
        try s.buff.writer.print("{s}", .{@typeName(type_T)});

        _ = info_T;
    }
};
