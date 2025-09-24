const std = @import("std");
const Writer = std.Io.Writer;
const Error = Writer.Error;
const defaultFmtOpts: std.fmt.Options = .{};

const Options = struct {
    maxDepth: u8 = 10,
};

const Context = struct {
    depth: u8 = 0,
    needNewLine: bool = false,
    showType: bool = true,
};

pub fn prettyPrintValue(
    w: *Writer,
    value: anytype,
    opts: Options,
    ctx: Context,
) Error!void {
    const T = @TypeOf(value);
    // TODO: add newline and indent if not top
    // TODO: add type
    var passCtx = ctx;
    passCtx.depth += 1;
    var passCtxNoNewLine = passCtx;
    passCtxNoNewLine.needNewLine = false;
    var passCtxNewLine = passCtx;
    passCtxNewLine.needNewLine = true;
    var passCtxNoType = passCtx;
    passCtxNoType.showType = false;
    var passCtxNoLineType = passCtxNoNewLine;
    passCtxNoLineType.showType = false;

    switch (@typeInfo(T)) {
        .float, .comptime_float => {
            return printFloat(w, value, defaultFmtOpts.toNumber(.decimal, .lower));
        },
        .int, .comptime_int => {
            return printInt(w, value, 10, .lower, defaultFmtOpts);
        },
        .bool => {
            const string: []const u8 = if (value) "true" else "false";
            return w.alignBufferOptions(string, defaultFmtOpts);
        },
        .void => {
            return w.alignBufferOptions("void", defaultFmtOpts);
        },
        .optional => {
            if (value) |payload| {
                return prettyPrintValue(&w, payload, opts, passCtx);
            } else {
                return w.alignBufferOptions("null", defaultFmtOpts);
            }
        },
        .error_union => {
            if (value) |payload| {
                return prettyPrintValue(&w, payload, opts, passCtx);
            } else |err| {
                return prettyPrintValue(&w, err, opts, passCtx);
            }
        },
        .error_set => {
            return printErrorSet(w, value);
        },
        .@"enum" => |info| {
            if (info.is_exhaustive) {
                return printEnumExhaustive(w, value);
            } else {
                return printEnumNonexhaustive(w, value);
            }
        },
        .@"union" => |info| {
            if (ctx.depth == opts.maxDepth) {
                try w.writeAll(".{ ... }");
                return;
            }
            if (info.tag_type) |UnionTagType| {
                try w.writeAll(".{ .");
                try w.writeAll(@tagName(@as(UnionTagType, value)));
                try w.writeAll(" = ");
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try prettyPrintValue(&w, @field(value, u_field.name), opts, passCtxNoNewLine);
                    }
                }
                try w.writeAll(" }");
            } else switch (info.layout) {
                .auto => {
                    return w.writeAll(".{ ... }");
                },
                .@"extern", .@"packed" => {
                    if (info.fields.len == 0) return w.writeAll(".{}");
                    try w.writeAll(".{ ");
                    inline for (info.fields, 1..) |field, i| {
                        try w.writeByte('.');
                        try w.writeAll(field.name);
                        try w.writeAll(" = ");
                        try prettyPrintValue(&w, @field(value, field.name), opts, passCtx);
                        try w.writeAll(if (i < info.fields.len) ", " else " }");
                    }
                },
            }
        },
        .@"struct" => |info| {
            if (info.is_tuple) {
                try w.writeAll(".{");
                inline for (info.fields, 0..) |f, i| {
                    if (i == 0) {
                        try w.writeAll(" ");
                    } else {
                        try w.writeAll(", ");
                    }
                    try prettyPrintValue(w, ANY, defaultFmtOpts, @field(value, f.name), passCtx);
                }
                try w.writeAll(" }");
                return;
            }
            if (ctx.depth == opts.maxDepth) {
                try w.writeAll(".{ ... }");
                return;
            }
            try w.writeAll(".{");
            inline for (info.fields) |f| {
                w.print(".{s}: {} = ", .{ f.name, @typeName(f.type) });
                try prettyPrintValue(&w, @field(value, f.name), opts, passCtxNoLineType);
                try w.writeAll(",");
            }
            try w.writeAll("\n");
            for (0..ctx.depth) |_| {
                try w.writeAll("\t");
            }
            try w.writeAll("}");
        },
        .pointer => |ptr_info| switch (ptr_info.size) {
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => |array_info| return prettyPrintValue(&w, fmt @as([]const array_info.child, value), max_depth),
                .@"enum", .@"union", .@"struct" => return prettyPrintValue(&w, fmt, defaultFmtOpts, value.*, max_depth),
                else => {
                    var buffers: [2][]const u8 = .{ @typeName(ptr_info.child), "@" };
                    try w.writeVecAll(&buffers);
                    try w.printInt(@intFromPtr(value), 16, .lower, defaultFmtOpts);
                    return;
                },
            },
            .many, .c => {
                if (!is_any) @compileError("cannot format pointer without a specifier (i.e. {s} or {*})");
                optionsForbidden(defaultFmtOpts);
                try w.printAddress(value);
            },
            .slice => {
                if (!is_any)
                    @compileError("cannot format slice without a specifier (i.e. {s}, {x}, {b64}, or {any})");
                if (max_depth == 0) return w.writeAll("{ ... }");
                try w.writeAll("{ ");
                for (value, 0..) |elem, i| {
                    try prettyPrintValue(&w, fmt, defaultFmtOpts, elem, max_depth - 1);
                    if (i != value.len - 1) {
                        try w.writeAll(", ");
                    }
                }
                try w.writeAll(" }");
            },
        },
        .array => {
            if (!is_any) @compileError("cannot format array without a specifier (i.e. {s} or {any})");
            if (max_depth == 0) return w.writeAll("{ ... }");
            try w.writeAll("{ ");
            for (value, 0..) |elem, i| {
                try prettyPrintValue(&w, fmt, defaultFmtOpts, elem, max_depth - 1);
                if (i < value.len - 1) {
                    try w.writeAll(", ");
                }
            }
            try w.writeAll(" }");
        },
        .vector => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return printVector(w, fmt, defaultFmtOpts, value, max_depth);
        },
        .@"fn" => @compileError("unable to format function body type, use '*const " ++ @typeName(T) ++ "' for a function pointer type"),
        .type => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return w.alignBufferOptions(@typeName(value), defaultFmtOpts);
        },
        .enum_literal => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            optionsForbidden(defaultFmtOpts);
            var vecs: [2][]const u8 = .{ ".", @tagName(value) };
            return w.writeVecAll(&vecs);
        },
        .null => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return w.alignBufferOptions("null", defaultFmtOpts);
        },
        else => @compileError("unable to format type '" ++ @typeName(T) ++ "'"),
    }
}

const printInt = std.Io.Writer.printInt;
const writeSliceEndian = std.Io.Writer.writeSliceEndian;
const writeStruct = std.Io.Writer.writeStruct;
const writeInt = std.Io.Writer.writeInt;

const fixed = std.Io.Writer.fixed;
const hashed = std.Io.Writer.hashed;
const buffered = std.Io.Writer.buffered;
const countSplat = std.Io.Writer.countSplat;
const countSendFileLowerBound = std.Io.Writer.countSendFileLowerBound;
const writeVec = std.Io.Writer.writeVec;
const writeSplat = std.Io.Writer.writeSplat;
const writeSplatHeader = std.Io.Writer.writeSplatHeader;
const writeSplatHeaderLimit = std.Io.Writer.writeSplatHeaderLimit;
const flush = std.Io.Writer.flush;
const defaultFlush = std.Io.Writer.defaultFlush;
const noopFlush = std.Io.Writer.noopFlush;
const rebase = std.Io.Writer.rebase;
const defaultRebase = std.Io.Writer.defaultRebase;
const unusedCapacitySlice = std.Io.Writer.unusedCapacitySlice;
const unusedCapacityLen = std.Io.Writer.unusedCapacityLen;
const writableArray = std.Io.Writer.writableArray;
const writableSlice = std.Io.Writer.writableSlice;
const writableSliceGreedy = std.Io.Writer.writableSliceGreedy;
const writableSliceGreedyPreserve = std.Io.Writer.writableSliceGreedyPreserve;
const writableSlicePreserve = std.Io.Writer.writableSlicePreserve;
const ensureUnusedCapacity = std.Io.Writer.ensureUnusedCapacity;
const undo = std.Io.Writer.undo;
const advance = std.Io.Writer.advance;
const writeVecAll = std.Io.Writer.writeVecAll;
const writeSplatAll = std.Io.Writer.writeSplatAll;
const write = std.Io.Writer.write;
const writeAll = std.Io.Writer.writeAll;
const print = std.Io.Writer.print;
const writeByte = std.Io.Writer.writeByte;
const writeBytePreserve = std.Io.Writer.writeBytePreserve;
const splatByteAll = std.Io.Writer.splatByteAll;
const splatBytePreserve = std.Io.Writer.splatBytePreserve;
const splatByte = std.Io.Writer.splatByte;
const splatBytesAll = std.Io.Writer.splatBytesAll;
const splatBytes = std.Io.Writer.splatBytes;
const writeSliceSwap = std.Io.Writer.writeSliceSwap;
const sendFile = std.Io.Writer.sendFile;
const sendFileHeader = std.Io.Writer.sendFileHeader;
const sendFileReading = std.Io.Writer.sendFileReading;
const sendFileAll = std.Io.Writer.sendFileAll;
const sendFileReadingAll = std.Io.Writer.sendFileReadingAll;
const alignBuffer = std.Io.Writer.alignBuffer;
const alignBufferOptions = std.Io.Writer.alignBufferOptions;
const printAddress = std.Io.Writer.printAddress;
const printValue = std.Io.Writer.printValue;
const printVector = std.Io.Writer.printVector;
const printIntAny = std.Io.Writer.printIntAny;
const printAsciiChar = std.Io.Writer.printAsciiChar;
const printAscii = std.Io.Writer.printAscii;
const printUnicodeCodepoint = std.Io.Writer.printUnicodeCodepoint;
const printFloat = std.Io.Writer.printFloat;
const printFloatHexOptions = std.Io.Writer.printFloatHexOptions;
const printFloatHex = std.Io.Writer.printFloatHex;
const printByteSize = std.Io.Writer.printByteSize;
const invalidFmtError = std.Io.Writer.invalidFmtError;
const printDurationSigned = std.Io.Writer.printDurationSigned;
const printDurationUnsigned = std.Io.Writer.printDurationUnsigned;
const printDuration = std.Io.Writer.printDuration;
const printHex = std.Io.Writer.printHex;
const printBase64 = std.Io.Writer.printBase64;
const writeUleb128 = std.Io.Writer.writeUleb128;
const writeSleb128 = std.Io.Writer.writeSleb128;
const writeLeb128 = std.Io.Writer.writeLeb128;
const failingDrain = std.Io.Writer.failingDrain;
const failingSendFile = std.Io.Writer.failingSendFile;
const failingRebase = std.Io.Writer.failingRebase;
const consume = std.Io.Writer.consume;
const consumeAll = std.Io.Writer.consumeAll;
const unimplementedSendFile = std.Io.Writer.unimplementedSendFile;
const fixedDrain = std.Io.Writer.fixedDrain;
const unreachableDrain = std.Io.Writer.unreachableDrain;
const unreachableRebase = std.Io.Writer.unreachableRebase;
const Hashed = std.Io.Writer.Hashed;
const Hashing = std.Io.Writer.Hashing;

const ANY = "any";

const assert = std.debug.assert;
fn optionsForbidden(options: std.fmt.Options) void {
    assert(options.precision == null);
    assert(options.width == null);
}

fn printErrorSet(w: *Writer, error_set: anyerror) Error!void {
    var vecs: [2][]const u8 = .{ "error.", @errorName(error_set) };
    try w.writeVecAll(&vecs);
}

fn printEnumExhaustive(w: *Writer, value: anytype) Error!void {
    var vecs: [2][]const u8 = .{ ".", @tagName(value) };
    try w.writeVecAll(&vecs);
}

fn printEnumNonexhaustive(w: *Writer, value: anytype) Error!void {
    if (std.enums.tagName(@TypeOf(value), value)) |tag_name| {
        var vecs: [2][]const u8 = .{ ".", tag_name };
        try w.writeVecAll(&vecs);
        return;
    }
    try w.writeAll("@enumFromInt(");
    try w.printInt(@intFromEnum(value), 10, .lower, .{});
    try w.writeByte(')');
}

fn stripOptionalOrErrorUnionSpec(comptime fmt: []const u8) []const u8 {
    return if (std.mem.eql(u8, fmt[1..], ANY))
        ANY
    else
        fmt[1..];
}
