const std = @import("std");
const prettier = @import("prettier");
const _ = std.Io.Writer;

const Alloc = std.mem.Allocator;
const gpa = std.heap.page_allocator;

pub fn main() !void {
    // const val_T = @TypeOf(val);
    // const val_name = @typeName(val_T);
    // const val_info = @typeInfo(val_T);

    var buff: std.ArrayList(u8) = try std.ArrayList(u8).initCapacity(gpa, 1);
    defer buff.deinit(gpa);
    buff.appendAssumeCapacity('a');
    try buff.appendSlice(gpa, "tester");

    std.debug.print("{s}\n", .{buff.items});
    std.debug.print("{}, {}\n", .{ buff.items.len, buff.capacity });

    var P: Prettify = try Prettify.init(gpa);
    try P.pushObjBuffRec(&P, .{ .indent = 0 });
    std.debug.print("{s}", .{P.buff.items});
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
    fn init(alloc: Alloc) Alloc.Error!Self {
        const ret: @This() = @This(){ .alloc = alloc, .buff = try std.Io.Writer.Allocating.initCapacity(alloc, 512) };
        return ret;
    }

    fn deinit(s: *Self) !void {
        s.buff.deinit(s.alloc);
    }

    fn pushObjBuffRec(s: *Self, obj: anytype, ctx: Context) Alloc.Error!void {
        const type_T = @TypeOf(obj);
        const info_T = @typeInfo(type_T);
        for (0..ctx.indent) |_| {
            try s.buff.writer.print("{}", .{"\t"});
        }
        s.buff.writer.print("{}", .{@typeName(type_T)});

        _ = info_T;
    }
};
