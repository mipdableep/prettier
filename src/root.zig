const std = @import("std");
const Writer = std.Io.Writer;
const Error = Writer.Error;

pub fn prettyPrintValue(
    w: *Writer,
    comptime fmt: []const u8,
    options: std.fmt.Options,
    value: anytype,
    max_depth: usize,
) Error!void {
    const T = @TypeOf(value);

    switch (fmt.len) {
        1 => switch (fmt[0]) {
            '*' => return w.printAddress(value),
            'f' => return value.format(w),
            'd' => switch (@typeInfo(T)) {
                .float, .comptime_float => return printFloat(w, value, options.toNumber(.decimal, .lower)),
                .int, .comptime_int => return printInt(w, value, 10, .lower, options),
                .@"struct" => return value.formatNumber(w, options.toNumber(.decimal, .lower)),
                .@"enum" => return printInt(w, @intFromEnum(value), 10, .lower, options),
                .vector => return printVector(w, fmt, options, value, max_depth),
                else => invalidFmtError(fmt, value),
            },
            'c' => return w.printAsciiChar(value, options),
            'u' => return w.printUnicodeCodepoint(value),
            'b' => switch (@typeInfo(T)) {
                .int, .comptime_int => return printInt(w, value, 2, .lower, options),
                .@"enum" => return printInt(w, @intFromEnum(value), 2, .lower, options),
                .@"struct" => return value.formatNumber(w, options.toNumber(.binary, .lower)),
                .vector => return printVector(w, fmt, options, value, max_depth),
                else => invalidFmtError(fmt, value),
            },
            'o' => switch (@typeInfo(T)) {
                .int, .comptime_int => return printInt(w, value, 8, .lower, options),
                .@"enum" => return printInt(w, @intFromEnum(value), 8, .lower, options),
                .@"struct" => return value.formatNumber(w, options.toNumber(.octal, .lower)),
                .vector => return printVector(w, fmt, options, value, max_depth),
                else => invalidFmtError(fmt, value),
            },
            'x' => switch (@typeInfo(T)) {
                .float, .comptime_float => return printFloatHexOptions(w, value, options.toNumber(.hex, .lower)),
                .int, .comptime_int => return printInt(w, value, 16, .lower, options),
                .@"enum" => return printInt(w, @intFromEnum(value), 16, .lower, options),
                .@"struct" => return value.formatNumber(w, options.toNumber(.hex, .lower)),
                .pointer => |info| switch (info.size) {
                    .one, .slice => {
                        const slice: []const u8 = value;
                        optionsForbidden(options);
                        return printHex(w, slice, .lower);
                    },
                    .many, .c => {
                        const slice: [:0]const u8 = std.mem.span(value);
                        optionsForbidden(options);
                        return printHex(w, slice, .lower);
                    },
                },
                .array => {
                    const slice: []const u8 = &value;
                    optionsForbidden(options);
                    return printHex(w, slice, .lower);
                },
                .vector => return printVector(w, fmt, options, value, max_depth),
                else => invalidFmtError(fmt, value),
            },
            'X' => switch (@typeInfo(T)) {
                .float, .comptime_float => return printFloatHexOptions(w, value, options.toNumber(.hex, .upper)),
                .int, .comptime_int => return printInt(w, value, 16, .upper, options),
                .@"enum" => return printInt(w, @intFromEnum(value), 16, .upper, options),
                .@"struct" => return value.formatNumber(w, options.toNumber(.hex, .upper)),
                .pointer => |info| switch (info.size) {
                    .one, .slice => {
                        const slice: []const u8 = value;
                        optionsForbidden(options);
                        return printHex(w, slice, .upper);
                    },
                    .many, .c => {
                        const slice: [:0]const u8 = std.mem.span(value);
                        optionsForbidden(options);
                        return printHex(w, slice, .upper);
                    },
                },
                .array => {
                    const slice: []const u8 = &value;
                    optionsForbidden(options);
                    return printHex(w, slice, .upper);
                },
                .vector => return printVector(w, fmt, options, value, max_depth),
                else => invalidFmtError(fmt, value),
            },
            's' => switch (@typeInfo(T)) {
                .pointer => |info| switch (info.size) {
                    .one, .slice => {
                        const slice: []const u8 = value;
                        return w.alignBufferOptions(slice, options);
                    },
                    .many, .c => {
                        const slice: [:0]const u8 = std.mem.span(value);
                        return w.alignBufferOptions(slice, options);
                    },
                },
                .array => {
                    const slice: []const u8 = &value;
                    return w.alignBufferOptions(slice, options);
                },
                else => invalidFmtError(fmt, value),
            },
            'B' => switch (@typeInfo(T)) {
                .int, .comptime_int => return w.printByteSize(value, .decimal, options),
                .@"struct" => return value.formatByteSize(w, .decimal),
                else => invalidFmtError(fmt, value),
            },
            'D' => switch (@typeInfo(T)) {
                .int, .comptime_int => return w.printDuration(value, options),
                .@"struct" => return value.formatDuration(w),
                else => invalidFmtError(fmt, value),
            },
            'e' => switch (@typeInfo(T)) {
                .float, .comptime_float => return printFloat(w, value, options.toNumber(.scientific, .lower)),
                .@"struct" => return value.formatNumber(w, options.toNumber(.scientific, .lower)),
                else => invalidFmtError(fmt, value),
            },
            'E' => switch (@typeInfo(T)) {
                .float, .comptime_float => return printFloat(w, value, options.toNumber(.scientific, .upper)),
                .@"struct" => return value.formatNumber(w, options.toNumber(.scientific, .upper)),
                else => invalidFmtError(fmt, value),
            },
            't' => switch (@typeInfo(T)) {
                .error_set => return w.alignBufferOptions(@errorName(value), options),
                .@"enum", .@"union" => return w.alignBufferOptions(@tagName(value), options),
                else => invalidFmtError(fmt, value),
            },
            else => {},
        },
        2 => switch (fmt[0]) {
            'B' => switch (fmt[1]) {
                'i' => switch (@typeInfo(T)) {
                    .int, .comptime_int => return w.printByteSize(value, .binary, options),
                    .@"struct" => return value.formatByteSize(w, .binary),
                    else => invalidFmtError(fmt, value),
                },
                else => {},
            },
            else => {},
        },
        3 => if (fmt[0] == 'b' and fmt[1] == '6' and fmt[2] == '4') switch (@typeInfo(T)) {
            .pointer => |info| switch (info.size) {
                .one, .slice => {
                    const slice: []const u8 = value;
                    optionsForbidden(options);
                    return w.printBase64(slice);
                },
                .many, .c => {
                    const slice: [:0]const u8 = std.mem.span(value);
                    optionsForbidden(options);
                    return w.printBase64(slice);
                },
            },
            .array => {
                const slice: []const u8 = &value;
                optionsForbidden(options);
                return w.printBase64(slice);
            },
            else => invalidFmtError(fmt, value),
        },
        else => {},
    }

    const is_any = comptime std.mem.eql(u8, fmt, ANY);
    if (!is_any and std.meta.hasMethod(T, "format") and fmt.len == 0) {
        // after 0.15.0 is tagged, delete this compile error and its condition
        @compileError("ambiguous format string; specify {f} to call format method, or {any} to skip it");
    }

    switch (@typeInfo(T)) {
        .float, .comptime_float => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return printFloat(w, value, options.toNumber(.decimal, .lower));
        },
        .int, .comptime_int => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return printInt(w, value, 10, .lower, options);
        },
        .bool => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            const string: []const u8 = if (value) "true" else "false";
            return w.alignBufferOptions(string, options);
        },
        .void => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return w.alignBufferOptions("void", options);
        },
        .optional => {
            const remaining_fmt = comptime if (fmt.len > 0 and fmt[0] == '?')
                stripOptionalOrErrorUnionSpec(fmt)
            else if (is_any)
                ANY
            else
                @compileError("cannot print optional without a specifier (i.e. {?} or {any})");
            if (value) |payload| {
                return w.prettyPrintValue(remaining_fmt, options, payload, max_depth);
            } else {
                return w.alignBufferOptions("null", options);
            }
        },
        .error_union => {
            const remaining_fmt = comptime if (fmt.len > 0 and fmt[0] == '!')
                stripOptionalOrErrorUnionSpec(fmt)
            else if (is_any)
                ANY
            else
                @compileError("cannot print error union without a specifier (i.e. {!} or {any})");
            if (value) |payload| {
                return w.prettyPrintValue(remaining_fmt, options, payload, max_depth);
            } else |err| {
                return w.prettyPrintValue("", options, err, max_depth);
            }
        },
        .error_set => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            optionsForbidden(options);
            return printErrorSet(w, value);
        },
        .@"enum" => |info| {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            optionsForbidden(options);
            if (info.is_exhaustive) {
                return printEnumExhaustive(w, value);
            } else {
                return printEnumNonexhaustive(w, value);
            }
        },
        .@"union" => |info| {
            if (!is_any) {
                if (fmt.len != 0) invalidFmtError(fmt, value);
                return prettyPrintValue(w, ANY, options, value, max_depth);
            }
            if (max_depth == 0) {
                try w.writeAll(".{ ... }");
                return;
            }
            if (info.tag_type) |UnionTagType| {
                try w.writeAll(".{ .");
                try w.writeAll(@tagName(@as(UnionTagType, value)));
                try w.writeAll(" = ");
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try w.prettyPrintValue(ANY, options, @field(value, u_field.name), max_depth - 1);
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
                        try w.prettyPrintValue(ANY, options, @field(value, field.name), max_depth - 1);
                        try w.writeAll(if (i < info.fields.len) ", " else " }");
                    }
                },
            }
        },
        .@"struct" => |info| {
            if (!is_any) {
                if (fmt.len != 0) invalidFmtError(fmt, value);
                return prettyPrintValue(w, ANY, options, value, max_depth);
            }
            if (info.is_tuple) {
                // Skip the type and field names when formatting tuples.
                if (max_depth == 0) {
                    try w.writeAll(".{ ... }");
                    return;
                }
                try w.writeAll(".{");
                inline for (info.fields, 0..) |f, i| {
                    if (i == 0) {
                        try w.writeAll(" ");
                    } else {
                        try w.writeAll(", ");
                    }
                    try w.prettyPrintValue(ANY, options, @field(value, f.name), max_depth - 1);
                }
                try w.writeAll(" }");
                return;
            }
            if (max_depth == 0) {
                try w.writeAll(".{ ... }");
                return;
            }
            try w.writeAll(".{");
            inline for (info.fields, 0..) |f, i| {
                if (i == 0) {
                    try w.writeAll(" .");
                } else {
                    try w.writeAll(", .");
                }
                try w.writeAll(f.name);
                try w.writeAll(" = ");
                try w.prettyPrintValue(ANY, options, @field(value, f.name), max_depth - 1);
            }
            try w.writeAll(" }");
        },
        .pointer => |ptr_info| switch (ptr_info.size) {
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => |array_info| return w.prettyPrintValue(fmt, options, @as([]const array_info.child, value), max_depth),
                .@"enum", .@"union", .@"struct" => return w.prettyPrintValue(fmt, options, value.*, max_depth),
                else => {
                    var buffers: [2][]const u8 = .{ @typeName(ptr_info.child), "@" };
                    try w.writeVecAll(&buffers);
                    try w.printInt(@intFromPtr(value), 16, .lower, options);
                    return;
                },
            },
            .many, .c => {
                if (!is_any) @compileError("cannot format pointer without a specifier (i.e. {s} or {*})");
                optionsForbidden(options);
                try w.printAddress(value);
            },
            .slice => {
                if (!is_any)
                    @compileError("cannot format slice without a specifier (i.e. {s}, {x}, {b64}, or {any})");
                if (max_depth == 0) return w.writeAll("{ ... }");
                try w.writeAll("{ ");
                for (value, 0..) |elem, i| {
                    try w.prettyPrintValue(fmt, options, elem, max_depth - 1);
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
                try w.prettyPrintValue(fmt, options, elem, max_depth - 1);
                if (i < value.len - 1) {
                    try w.writeAll(", ");
                }
            }
            try w.writeAll(" }");
        },
        .vector => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return printVector(w, fmt, options, value, max_depth);
        },
        .@"fn" => @compileError("unable to format function body type, use '*const " ++ @typeName(T) ++ "' for a function pointer type"),
        .type => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return w.alignBufferOptions(@typeName(value), options);
        },
        .enum_literal => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            optionsForbidden(options);
            var vecs: [2][]const u8 = .{ ".", @tagName(value) };
            return w.writeVecAll(&vecs);
        },
        .null => {
            if (!is_any and fmt.len != 0) invalidFmtError(fmt, value);
            return w.alignBufferOptions("null", options);
        },
        else => @compileError("unable to format type '" ++ @typeName(T) ++ "'"),
    }
}

pub fn prettyPrint(w: *Writer, comptime fmt: []const u8, args: anytype) Error!void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.@"struct".fields;
    const max_format_args = @typeInfo(std.fmt.ArgSetType).int.bits;
    if (fields_info.len > max_format_args) {
        @compileError("32 arguments max are supported per format call");
    }

    @setEvalBranchQuota(fmt.len * 1000);
    comptime var arg_state: std.fmt.ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    comptime var literal: []const u8 = "";
    inline while (true) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        literal = literal ++ fmt[start_index..end_index];

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        // Write out the literal
        if (literal.len != 0) {
            try w.writeAll(literal);
            literal = "";
        }

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        // Get past the {
        comptime assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        // Get past the }
        comptime assert(fmt[i] == '}');
        i += 1;

        const placeholder_array = fmt[fmt_begin..fmt_end].*;
        const placeholder = comptime std.fmt.Placeholder.parse(&placeholder_array);
        const arg_pos = comptime switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            .named => |arg_name| std.meta.fieldIndex(ArgsType, arg_name) orelse
                @compileError("no argument with name '" ++ arg_name ++ "'"),
        };

        const width = switch (placeholder.width) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const precision = switch (placeholder.precision) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const arg_to_print = comptime arg_state.nextArg(arg_pos) orelse
            @compileError("too few arguments");

        try prettyPrintValue(
            &w,
            placeholder.specifier_arg,
            .{
                .fill = placeholder.fill,
                .alignment = placeholder.alignment,
                .width = width,
                .precision = precision,
            },
            @field(args, fields_info[arg_to_print].name),
            std.options.fmt_max_depth,
        );
    }

    if (comptime arg_state.hasUnusedArgs()) {
        const missing_count = arg_state.args_len - @popCount(arg_state.used_args);
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("unused argument in '" ++ fmt ++ "'"),
            else => @compileError(std.fmt.comptimePrint("{d}", .{missing_count}) ++ " unused arguments in '" ++ fmt ++ "'"),
        }
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
