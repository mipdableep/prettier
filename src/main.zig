const std = @import("std");
const prettier = @import("prettier");
const _ = std.Io.Writer;

const Alloc = std.mem.Allocator;
const gpa = std.heap.page_allocator;
const TAB: []const u8 = &[_]u8{ ' ', ' ' };

pub fn main() !void {
    // const val_T = @TypeOf(val);
    // const val_name = @typeName(val_T);
    // const val_info = @typeInfo(val_T);
    const P = Prettify.init(gpa);

    // const opts: Options = .{};

    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    try prettier.prettyPrintValue(&stdout_writer.interface, P, .{ .indentSeq = TAB }, .{});
    try stdout_writer.interface.flush();
}

const Options = struct {
    maxDepth: u8 = 10,
};

const Context = struct {
    indent: u8 = 0,
};

const Prettify = struct {
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

    fn pushObjBuffRec(s: *Self, obj: anytype, ctx: Context) !void {
        const type_T = @TypeOf(obj);
        const info_T = @typeInfo(type_T);
        for (0..ctx.indent) |_| {
            try s.buff.writer.print("{s}", .{"\t"});
        }
        try s.buff.writer.print("{s}", .{@typeName(type_T)});

        _ = info_T;
    }
};
