//! This file has to do with parsing and rendering the ZIR text format.

const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const BigInt = std.math.big.Int;
const Type = @import("../type.zig").Type;
const Value = @import("../value.zig").Value;
const ir = @import("../ir.zig");

/// These are instructions that correspond to the ZIR text format. See `ir.Inst` for
/// in-memory, analyzed instructions with types and values.
pub const Inst = struct {
    tag: Tag,
    /// Byte offset into the source.
    src: usize,

    /// These names are used directly as the instruction names in the text format.
    pub const Tag = enum {
        str,
        int,
        ptrtoint,
        fieldptr,
        deref,
        as,
        @"asm",
        @"unreachable",
        @"fn",
        @"export",
        primitive,
        fntype,
        intcast,
        bitcast,
        elemptr,
        add,
    };

    pub fn TagToType(tag: Tag) type {
        return switch (tag) {
            .str => Str,
            .int => Int,
            .ptrtoint => PtrToInt,
            .fieldptr => FieldPtr,
            .deref => Deref,
            .as => As,
            .@"asm" => Asm,
            .@"unreachable" => Unreachable,
            .@"fn" => Fn,
            .@"export" => Export,
            .primitive => Primitive,
            .fntype => FnType,
            .intcast => IntCast,
            .bitcast => BitCast,
            .elemptr => ElemPtr,
            .add => Add,
        };
    }

    pub fn cast(base: *Inst, comptime T: type) ?*T {
        if (base.tag != T.base_tag)
            return null;

        return @fieldParentPtr(T, "base", base);
    }

    pub const Str = struct {
        pub const base_tag = Tag.str;
        base: Inst,

        positionals: struct {
            bytes: []const u8,
        },
        kw_args: struct {},
    };

    pub const Int = struct {
        pub const base_tag = Tag.int;
        base: Inst,

        positionals: struct {
            int: BigInt,
        },
        kw_args: struct {},
    };

    pub const PtrToInt = struct {
        pub const base_tag = Tag.ptrtoint;
        base: Inst,

        positionals: struct {
            ptr: *Inst,
        },
        kw_args: struct {},
    };

    pub const FieldPtr = struct {
        pub const base_tag = Tag.fieldptr;
        base: Inst,

        positionals: struct {
            object_ptr: *Inst,
            field_name: *Inst,
        },
        kw_args: struct {},
    };

    pub const Deref = struct {
        pub const base_tag = Tag.deref;
        base: Inst,

        positionals: struct {
            ptr: *Inst,
        },
        kw_args: struct {},
    };

    pub const As = struct {
        pub const base_tag = Tag.as;
        base: Inst,

        positionals: struct {
            dest_type: *Inst,
            value: *Inst,
        },
        kw_args: struct {},
    };

    pub const Asm = struct {
        pub const base_tag = Tag.@"asm";
        base: Inst,

        positionals: struct {
            asm_source: *Inst,
            return_type: *Inst,
        },
        kw_args: struct {
            @"volatile": bool = false,
            output: ?*Inst = null,
            inputs: []*Inst = &[0]*Inst{},
            clobbers: []*Inst = &[0]*Inst{},
            args: []*Inst = &[0]*Inst{},
        },
    };

    pub const Unreachable = struct {
        pub const base_tag = Tag.@"unreachable";
        base: Inst,

        positionals: struct {},
        kw_args: struct {},
    };

    pub const Fn = struct {
        pub const base_tag = Tag.@"fn";
        base: Inst,

        positionals: struct {
            fn_type: *Inst,
            body: Body,
        },
        kw_args: struct {},

        pub const Body = struct {
            instructions: []*Inst,
        };
    };

    pub const Export = struct {
        pub const base_tag = Tag.@"export";
        base: Inst,

        positionals: struct {
            symbol_name: *Inst,
            value: *Inst,
        },
        kw_args: struct {},
    };

    pub const Primitive = struct {
        pub const base_tag = Tag.primitive;
        base: Inst,

        positionals: struct {
            tag: BuiltinType,
        },
        kw_args: struct {},

        pub const BuiltinType = enum {
            @"isize",
            @"usize",
            @"c_short",
            @"c_ushort",
            @"c_int",
            @"c_uint",
            @"c_long",
            @"c_ulong",
            @"c_longlong",
            @"c_ulonglong",
            @"c_longdouble",
            @"c_void",
            @"f16",
            @"f32",
            @"f64",
            @"f128",
            @"bool",
            @"void",
            @"noreturn",
            @"type",
            @"anyerror",
            @"comptime_int",
            @"comptime_float",

            fn toType(self: BuiltinType) Type {
                return switch (self) {
                    .@"isize" => Type.initTag(.@"isize"),
                    .@"usize" => Type.initTag(.@"usize"),
                    .@"c_short" => Type.initTag(.@"c_short"),
                    .@"c_ushort" => Type.initTag(.@"c_ushort"),
                    .@"c_int" => Type.initTag(.@"c_int"),
                    .@"c_uint" => Type.initTag(.@"c_uint"),
                    .@"c_long" => Type.initTag(.@"c_long"),
                    .@"c_ulong" => Type.initTag(.@"c_ulong"),
                    .@"c_longlong" => Type.initTag(.@"c_longlong"),
                    .@"c_ulonglong" => Type.initTag(.@"c_ulonglong"),
                    .@"c_longdouble" => Type.initTag(.@"c_longdouble"),
                    .@"c_void" => Type.initTag(.@"c_void"),
                    .@"f16" => Type.initTag(.@"f16"),
                    .@"f32" => Type.initTag(.@"f32"),
                    .@"f64" => Type.initTag(.@"f64"),
                    .@"f128" => Type.initTag(.@"f128"),
                    .@"bool" => Type.initTag(.@"bool"),
                    .@"void" => Type.initTag(.@"void"),
                    .@"noreturn" => Type.initTag(.@"noreturn"),
                    .@"type" => Type.initTag(.@"type"),
                    .@"anyerror" => Type.initTag(.@"anyerror"),
                    .@"comptime_int" => Type.initTag(.@"comptime_int"),
                    .@"comptime_float" => Type.initTag(.@"comptime_float"),
                };
            }
        };
    };

    pub const FnType = struct {
        pub const base_tag = Tag.fntype;
        base: Inst,

        positionals: struct {
            param_types: []*Inst,
            return_type: *Inst,
        },
        kw_args: struct {
            cc: std.builtin.CallingConvention = .Unspecified,
        },
    };

    pub const IntCast = struct {
        pub const base_tag = Tag.intcast;
        base: Inst,

        positionals: struct {
            dest_type: *Inst,
            value: *Inst,
        },
        kw_args: struct {},
    };

    pub const BitCast = struct {
        pub const base_tag = Tag.bitcast;
        base: Inst,

        positionals: struct {
            dest_type: *Inst,
            operand: *Inst,
        },
        kw_args: struct {},
    };

    pub const ElemPtr = struct {
        pub const base_tag = Tag.elemptr;
        base: Inst,

        positionals: struct {
            array_ptr: *Inst,
            index: *Inst,
        },
        kw_args: struct {},
    };

    pub const Add = struct {
        pub const base_tag = Tag.add;
        base: Inst,

        positionals: struct {
            lhs: *Inst,
            rhs: *Inst,
        },
        kw_args: struct {},
    };
};

pub const ErrorMsg = struct {
    byte_offset: usize,
    msg: []const u8,
};

pub const Module = struct {
    decls: []*Inst,
    errors: []ErrorMsg,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Module, allocator: *Allocator) void {
        allocator.free(self.decls);
        allocator.free(self.errors);
        self.arena.deinit();
        self.* = undefined;
    }

    /// This is a debugging utility for rendering the tree to stderr.
    pub fn dump(self: Module) void {
        self.writeToStream(std.heap.page_allocator, std.io.getStdErr().outStream()) catch {};
    }

    const InstPtrTable = std.AutoHashMap(*Inst, struct { index: usize, fn_body: ?*Inst.Fn.Body });

    /// The allocator is used for temporary storage, but this function always returns
    /// with no resources allocated.
    pub fn writeToStream(self: Module, allocator: *Allocator, stream: var) !void {
        // First, build a map of *Inst to @ or % indexes
        var inst_table = InstPtrTable.init(allocator);
        defer inst_table.deinit();

        try inst_table.ensureCapacity(self.decls.len);

        for (self.decls) |decl, decl_i| {
            try inst_table.putNoClobber(decl, .{ .index = decl_i, .fn_body = null });

            if (decl.cast(Inst.Fn)) |fn_inst| {
                for (fn_inst.positionals.body.instructions) |inst, inst_i| {
                    try inst_table.putNoClobber(inst, .{ .index = inst_i, .fn_body = &fn_inst.positionals.body });
                }
            }
        }

        for (self.decls) |decl, i| {
            try stream.print("@{} ", .{i});
            try self.writeInstToStream(stream, decl, &inst_table);
            try stream.writeByte('\n');
        }
    }

    fn writeInstToStream(
        self: Module,
        stream: var,
        decl: *Inst,
        inst_table: *const InstPtrTable,
    ) @TypeOf(stream).Error!void {
        // TODO I tried implementing this with an inline for loop and hit a compiler bug
        switch (decl.tag) {
            .str => return self.writeInstToStreamGeneric(stream, .str, decl, inst_table),
            .int => return self.writeInstToStreamGeneric(stream, .int, decl, inst_table),
            .ptrtoint => return self.writeInstToStreamGeneric(stream, .ptrtoint, decl, inst_table),
            .fieldptr => return self.writeInstToStreamGeneric(stream, .fieldptr, decl, inst_table),
            .deref => return self.writeInstToStreamGeneric(stream, .deref, decl, inst_table),
            .as => return self.writeInstToStreamGeneric(stream, .as, decl, inst_table),
            .@"asm" => return self.writeInstToStreamGeneric(stream, .@"asm", decl, inst_table),
            .@"unreachable" => return self.writeInstToStreamGeneric(stream, .@"unreachable", decl, inst_table),
            .@"fn" => return self.writeInstToStreamGeneric(stream, .@"fn", decl, inst_table),
            .@"export" => return self.writeInstToStreamGeneric(stream, .@"export", decl, inst_table),
            .primitive => return self.writeInstToStreamGeneric(stream, .primitive, decl, inst_table),
            .fntype => return self.writeInstToStreamGeneric(stream, .fntype, decl, inst_table),
            .intcast => return self.writeInstToStreamGeneric(stream, .intcast, decl, inst_table),
            .bitcast => return self.writeInstToStreamGeneric(stream, .bitcast, decl, inst_table),
            .elemptr => return self.writeInstToStreamGeneric(stream, .elemptr, decl, inst_table),
            .add => return self.writeInstToStreamGeneric(stream, .add, decl, inst_table),
        }
    }

    fn writeInstToStreamGeneric(
        self: Module,
        stream: var,
        comptime inst_tag: Inst.Tag,
        base: *Inst,
        inst_table: *const InstPtrTable,
    ) !void {
        const SpecificInst = Inst.TagToType(inst_tag);
        const inst = @fieldParentPtr(SpecificInst, "base", base);
        const Positionals = @TypeOf(inst.positionals);
        try stream.writeAll("= " ++ @tagName(inst_tag) ++ "(");
        const pos_fields = @typeInfo(Positionals).Struct.fields;
        inline for (pos_fields) |arg_field, i| {
            if (i != 0) {
                try stream.writeAll(", ");
            }
            try self.writeParamToStream(stream, @field(inst.positionals, arg_field.name), inst_table);
        }

        comptime var need_comma = pos_fields.len != 0;
        const KW_Args = @TypeOf(inst.kw_args);
        inline for (@typeInfo(KW_Args).Struct.fields) |arg_field, i| {
            if (@typeInfo(arg_field.field_type) == .Optional) {
                if (@field(inst.kw_args, arg_field.name)) |non_optional| {
                    if (need_comma) try stream.writeAll(", ");
                    try stream.print("{}=", .{arg_field.name});
                    try self.writeParamToStream(stream, non_optional, inst_table);
                    need_comma = true;
                }
            } else {
                if (need_comma) try stream.writeAll(", ");
                try stream.print("{}=", .{arg_field.name});
                try self.writeParamToStream(stream, @field(inst.kw_args, arg_field.name), inst_table);
                need_comma = true;
            }
        }

        try stream.writeByte(')');
    }

    fn writeParamToStream(self: Module, stream: var, param: var, inst_table: *const InstPtrTable) !void {
        if (@typeInfo(@TypeOf(param)) == .Enum) {
            return stream.writeAll(@tagName(param));
        }
        switch (@TypeOf(param)) {
            *Inst => return self.writeInstParamToStream(stream, param, inst_table),
            []*Inst => {
                try stream.writeByte('[');
                for (param) |inst, i| {
                    if (i != 0) {
                        try stream.writeAll(", ");
                    }
                    try self.writeInstParamToStream(stream, inst, inst_table);
                }
                try stream.writeByte(']');
            },
            Inst.Fn.Body => {
                try stream.writeAll("{\n");
                for (param.instructions) |inst, i| {
                    try stream.print("  %{} ", .{i});
                    try self.writeInstToStream(stream, inst, inst_table);
                    try stream.writeByte('\n');
                }
                try stream.writeByte('}');
            },
            bool => return stream.writeByte("01"[@boolToInt(param)]),
            []u8, []const u8 => return std.zig.renderStringLiteral(param, stream),
            BigInt => return stream.print("{}", .{param}),
            else => |T| @compileError("unimplemented: rendering parameter of type " ++ @typeName(T)),
        }
    }

    fn writeInstParamToStream(self: Module, stream: var, inst: *Inst, inst_table: *const InstPtrTable) !void {
        const info = inst_table.getValue(inst).?;
        const prefix = if (info.fn_body == null) "@" else "%";
        try stream.print("{}{}", .{ prefix, info.index });
    }
};

pub fn parse(allocator: *Allocator, source: [:0]const u8) Allocator.Error!Module {
    var global_name_map = std.StringHashMap(usize).init(allocator);
    defer global_name_map.deinit();

    var parser: Parser = .{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .i = 0,
        .source = source,
        .decls = std.ArrayList(*Inst).init(allocator),
        .errors = std.ArrayList(ErrorMsg).init(allocator),
        .global_name_map = &global_name_map,
    };
    errdefer parser.arena.deinit();

    parser.parseRoot() catch |err| switch (err) {
        error.ParseFailure => {
            assert(parser.errors.items.len != 0);
        },
        else => |e| return e,
    };
    return Module{
        .decls = parser.decls.toOwnedSlice(),
        .errors = parser.errors.toOwnedSlice(),
        .arena = parser.arena,
    };
}

const Parser = struct {
    allocator: *Allocator,
    arena: std.heap.ArenaAllocator,
    i: usize,
    source: [:0]const u8,
    errors: std.ArrayList(ErrorMsg),
    decls: std.ArrayList(*Inst),
    global_name_map: *std.StringHashMap(usize),

    const Body = struct {
        instructions: std.ArrayList(*Inst),
        name_map: std.StringHashMap(usize),
    };

    fn parseBody(self: *Parser) !Inst.Fn.Body {
        var body_context = Body{
            .instructions = std.ArrayList(*Inst).init(self.allocator),
            .name_map = std.StringHashMap(usize).init(self.allocator),
        };
        defer body_context.instructions.deinit();
        defer body_context.name_map.deinit();

        try requireEatBytes(self, "{");
        skipSpace(self);

        while (true) : (self.i += 1) switch (self.source[self.i]) {
            ';' => _ = try skipToAndOver(self, '\n'),
            '%' => {
                self.i += 1;
                const ident = try skipToAndOver(self, ' ');
                skipSpace(self);
                try requireEatBytes(self, "=");
                skipSpace(self);
                const inst = try parseInstruction(self, &body_context);
                const ident_index = body_context.instructions.items.len;
                if (try body_context.name_map.put(ident, ident_index)) |_| {
                    return self.fail("redefinition of identifier '{}'", .{ident});
                }
                try body_context.instructions.append(inst);
                continue;
            },
            ' ', '\n' => continue,
            '}' => {
                self.i += 1;
                break;
            },
            else => |byte| return self.failByte(byte),
        };

        return Inst.Fn.Body{
            .instructions = body_context.instructions.toOwnedSlice(),
        };
    }

    fn parseStringLiteral(self: *Parser) ![]u8 {
        const start = self.i;
        try self.requireEatBytes("\"");

        while (true) : (self.i += 1) switch (self.source[self.i]) {
            '"' => {
                self.i += 1;
                const span = self.source[start..self.i];
                var bad_index: usize = undefined;
                const parsed = std.zig.parseStringLiteral(&self.arena.allocator, span, &bad_index) catch |err| switch (err) {
                    error.InvalidCharacter => {
                        self.i = start + bad_index;
                        const bad_byte = self.source[self.i];
                        return self.fail("invalid string literal character: '{c}'\n", .{bad_byte});
                    },
                    else => |e| return e,
                };
                return parsed;
            },
            '\\' => {
                self.i += 1;
                continue;
            },
            0 => return self.failByte(0),
            else => continue,
        };
    }

    fn parseIntegerLiteral(self: *Parser) !BigInt {
        const start = self.i;
        if (self.source[self.i] == '-') self.i += 1;
        while (true) : (self.i += 1) switch (self.source[self.i]) {
            '0'...'9' => continue,
            else => break,
        };
        const number_text = self.source[start..self.i];
        var result = try BigInt.init(&self.arena.allocator);
        result.setString(10, number_text) catch |err| {
            self.i = start;
            switch (err) {
                error.InvalidBase => unreachable,
                error.InvalidCharForDigit => return self.fail("invalid digit in integer literal", .{}),
                error.DigitTooLargeForBase => return self.fail("digit too large in integer literal", .{}),
                else => |e| return e,
            }
        };
        return result;
    }

    fn parseRoot(self: *Parser) !void {
        // The IR format is designed so that it can be tokenized and parsed at the same time.
        while (true) : (self.i += 1) switch (self.source[self.i]) {
            ';' => _ = try skipToAndOver(self, '\n'),
            '@' => {
                self.i += 1;
                const ident = try skipToAndOver(self, ' ');
                skipSpace(self);
                try requireEatBytes(self, "=");
                skipSpace(self);
                const inst = try parseInstruction(self, null);
                const ident_index = self.decls.items.len;
                if (try self.global_name_map.put(ident, ident_index)) |_| {
                    return self.fail("redefinition of identifier '{}'", .{ident});
                }
                try self.decls.append(inst);
                continue;
            },
            ' ', '\n' => continue,
            0 => break,
            else => |byte| return self.fail("unexpected byte: '{c}'", .{byte}),
        };
    }

    fn eatByte(self: *Parser, byte: u8) bool {
        if (self.source[self.i] != byte) return false;
        self.i += 1;
        return true;
    }

    fn skipSpace(self: *Parser) void {
        while (self.source[self.i] == ' ' or self.source[self.i] == '\n') {
            self.i += 1;
        }
    }

    fn requireEatBytes(self: *Parser, bytes: []const u8) !void {
        const start = self.i;
        for (bytes) |byte| {
            if (self.source[self.i] != byte) {
                self.i = start;
                return self.fail("expected '{}'", .{bytes});
            }
            self.i += 1;
        }
    }

    fn skipToAndOver(self: *Parser, byte: u8) ![]const u8 {
        const start_i = self.i;
        while (self.source[self.i] != 0) : (self.i += 1) {
            if (self.source[self.i] == byte) {
                const result = self.source[start_i..self.i];
                self.i += 1;
                return result;
            }
        }
        return self.fail("unexpected EOF", .{});
    }

    /// ParseFailure is an internal error code; handled in `parse`.
    const InnerError = error{ ParseFailure, OutOfMemory };

    fn failByte(self: *Parser, byte: u8) InnerError {
        if (byte == 0) {
            return self.fail("unexpected EOF", .{});
        } else {
            return self.fail("unexpected byte: '{c}'", .{byte});
        }
    }

    fn fail(self: *Parser, comptime format: []const u8, args: var) InnerError {
        @setCold(true);
        const msg = try std.fmt.allocPrint(&self.arena.allocator, format, args);
        (try self.errors.addOne()).* = .{
            .byte_offset = self.i,
            .msg = msg,
        };
        return error.ParseFailure;
    }

    fn parseInstruction(self: *Parser, body_ctx: ?*Body) InnerError!*Inst {
        const fn_name = try skipToAndOver(self, '(');
        inline for (@typeInfo(Inst.Tag).Enum.fields) |field| {
            if (mem.eql(u8, field.name, fn_name)) {
                const tag = @field(Inst.Tag, field.name);
                return parseInstructionGeneric(self, field.name, Inst.TagToType(tag), body_ctx);
            }
        }
        return self.fail("unknown instruction '{}'", .{fn_name});
    }

    fn parseInstructionGeneric(
        self: *Parser,
        comptime fn_name: []const u8,
        comptime InstType: type,
        body_ctx: ?*Body,
    ) !*Inst {
        const inst_specific = try self.arena.allocator.create(InstType);
        inst_specific.base = .{
            .src = self.i,
            .tag = InstType.base_tag,
        };

        if (@hasField(InstType, "ty")) {
            inst_specific.ty = opt_type orelse {
                return self.fail("instruction '" ++ fn_name ++ "' requires type", .{});
            };
        }

        const Positionals = @TypeOf(inst_specific.positionals);
        inline for (@typeInfo(Positionals).Struct.fields) |arg_field| {
            if (self.source[self.i] == ',') {
                self.i += 1;
                skipSpace(self);
            } else if (self.source[self.i] == ')') {
                return self.fail("expected positional parameter '{}'", .{arg_field.name});
            }
            @field(inst_specific.positionals, arg_field.name) = try parseParameterGeneric(
                self,
                arg_field.field_type,
                body_ctx,
            );
            skipSpace(self);
        }

        const KW_Args = @TypeOf(inst_specific.kw_args);
        inst_specific.kw_args = .{}; // assign defaults
        skipSpace(self);
        while (eatByte(self, ',')) {
            skipSpace(self);
            const name = try skipToAndOver(self, '=');
            inline for (@typeInfo(KW_Args).Struct.fields) |arg_field| {
                const field_name = arg_field.name;
                if (mem.eql(u8, name, field_name)) {
                    const NonOptional = switch (@typeInfo(arg_field.field_type)) {
                        .Optional => |info| info.child,
                        else => arg_field.field_type,
                    };
                    @field(inst_specific.kw_args, field_name) = try parseParameterGeneric(self, NonOptional, body_ctx);
                    break;
                }
            } else {
                return self.fail("unrecognized keyword parameter: '{}'", .{name});
            }
            skipSpace(self);
        }
        try requireEatBytes(self, ")");

        return &inst_specific.base;
    }

    fn parseParameterGeneric(self: *Parser, comptime T: type, body_ctx: ?*Body) !T {
        if (@typeInfo(T) == .Enum) {
            const start = self.i;
            while (true) : (self.i += 1) switch (self.source[self.i]) {
                ' ', '\n', ',', ')' => {
                    const enum_name = self.source[start..self.i];
                    return std.meta.stringToEnum(T, enum_name) orelse {
                        return self.fail("tag '{}' not a member of enum '{}'", .{ enum_name, @typeName(T) });
                    };
                },
                0 => return self.failByte(0),
                else => continue,
            };
        }
        switch (T) {
            Inst.Fn.Body => return parseBody(self),
            bool => {
                const bool_value = switch (self.source[self.i]) {
                    '0' => false,
                    '1' => true,
                    else => |byte| return self.fail("expected '0' or '1' for boolean value, found {c}", .{byte}),
                };
                self.i += 1;
                return bool_value;
            },
            []*Inst => {
                try requireEatBytes(self, "[");
                skipSpace(self);
                if (eatByte(self, ']')) return &[0]*Inst{};

                var instructions = std.ArrayList(*Inst).init(&self.arena.allocator);
                while (true) {
                    skipSpace(self);
                    try instructions.append(try parseParameterInst(self, body_ctx));
                    skipSpace(self);
                    if (!eatByte(self, ',')) break;
                }
                try requireEatBytes(self, "]");
                return instructions.toOwnedSlice();
            },
            *Inst => return parseParameterInst(self, body_ctx),
            []u8, []const u8 => return self.parseStringLiteral(),
            BigInt => return self.parseIntegerLiteral(),
            else => @compileError("Unimplemented: ir parseParameterGeneric for type " ++ @typeName(T)),
        }
        return self.fail("TODO parse parameter {}", .{@typeName(T)});
    }

    fn parseParameterInst(self: *Parser, body_ctx: ?*Body) !*Inst {
        const local_ref = switch (self.source[self.i]) {
            '@' => false,
            '%' => true,
            else => |byte| return self.fail("unexpected byte: '{c}'", .{byte}),
        };
        const map = if (local_ref)
            if (body_ctx) |bc|
                &bc.name_map
            else
                return self.fail("referencing a % instruction in global scope", .{})
        else
            self.global_name_map;

        self.i += 1;
        const name_start = self.i;
        while (true) : (self.i += 1) switch (self.source[self.i]) {
            0, ' ', '\n', ',', ')', ']' => break,
            else => continue,
        };
        const ident = self.source[name_start..self.i];
        const kv = map.get(ident) orelse {
            const bad_name = self.source[name_start - 1 .. self.i];
            self.i = name_start - 1;
            return self.fail("unrecognized identifier: {}", .{bad_name});
        };
        if (local_ref) {
            return body_ctx.?.instructions.items[kv.value];
        } else {
            return self.decls.items[kv.value];
        }
    }
};

pub fn emit_zir(allocator: *Allocator, old_module: ir.Module) !Module {
    var ctx: EmitZIR = .{
        .allocator = allocator,
        .decls = std.ArrayList(*Inst).init(allocator),
        .decl_table = std.AutoHashMap(*ir.Inst, *Inst).init(allocator),
        .arena = std.heap.ArenaAllocator.init(allocator),
        .old_module = &old_module,
    };
    defer ctx.decls.deinit();
    defer ctx.decl_table.deinit();
    errdefer ctx.arena.deinit();

    try ctx.emit();

    return Module{
        .decls = ctx.decls.toOwnedSlice(),
        .arena = ctx.arena,
        .errors = &[0]ErrorMsg{},
    };
}

const EmitZIR = struct {
    allocator: *Allocator,
    arena: std.heap.ArenaAllocator,
    old_module: *const ir.Module,
    decls: std.ArrayList(*Inst),
    decl_table: std.AutoHashMap(*ir.Inst, *Inst),

    fn emit(self: *EmitZIR) !void {
        for (self.old_module.exports) |module_export| {
            const export_value = try self.emitTypedValue(module_export.src, module_export.typed_value);
            const symbol_name = try self.emitStringLiteral(module_export.src, module_export.name);
            const export_inst = try self.arena.allocator.create(Inst.Export);
            export_inst.* = .{
                .base = .{ .src = module_export.src, .tag = Inst.Export.base_tag },
                .positionals = .{
                    .symbol_name = symbol_name,
                    .value = export_value,
                },
                .kw_args = .{},
            };
            try self.decls.append(&export_inst.base);
        }
    }

    fn resolveInst(self: *EmitZIR, inst_table: *const std.AutoHashMap(*ir.Inst, *Inst), inst: *ir.Inst) !*Inst {
        if (inst.cast(ir.Inst.Constant)) |const_inst| {
            if (self.decl_table.getValue(inst)) |decl| {
                return decl;
            }
            const new_decl = try self.emitTypedValue(inst.src, .{ .ty = inst.ty, .val = const_inst.val });
            try self.decl_table.putNoClobber(inst, new_decl);
            return new_decl;
        } else {
            return inst_table.getValue(inst).?;
        }
    }

    fn emitComptimeIntVal(self: *EmitZIR, src: usize, val: Value) !*Inst {
        const int_inst = try self.arena.allocator.create(Inst.Int);
        int_inst.* = .{
            .base = .{ .src = src, .tag = Inst.Int.base_tag },
            .positionals = .{
                .int = try val.toBigInt(&self.arena.allocator),
            },
            .kw_args = .{},
        };
        try self.decls.append(&int_inst.base);
        return &int_inst.base;
    }

    fn emitTypedValue(self: *EmitZIR, src: usize, typed_value: ir.TypedValue) Allocator.Error!*Inst {
        switch (typed_value.ty.zigTypeTag()) {
            .Pointer => {
                const ptr_elem_type = typed_value.ty.elemType();
                switch (ptr_elem_type.zigTypeTag()) {
                    .Array => {
                        // TODO more checks to make sure this can be emitted as a string literal
                        //const array_elem_type = ptr_elem_type.elemType();
                        //if (array_elem_type.eql(Type.initTag(.u8)) and
                        //    ptr_elem_type.hasSentinel(Value.initTag(.zero)))
                        //{
                        //}
                        const bytes = try typed_value.val.toAllocatedBytes(&self.arena.allocator);
                        return self.emitStringLiteral(src, bytes);
                    },
                    else => |t| std.debug.panic("TODO implement emitTypedValue for pointer to {}", .{@tagName(t)}),
                }
            },
            .ComptimeInt => return self.emitComptimeIntVal(src, typed_value.val),
            .Int => {
                const as_inst = try self.arena.allocator.create(Inst.As);
                as_inst.* = .{
                    .base = .{ .src = src, .tag = Inst.As.base_tag },
                    .positionals = .{
                        .dest_type = try self.emitType(src, typed_value.ty),
                        .value = try self.emitComptimeIntVal(src, typed_value.val),
                    },
                    .kw_args = .{},
                };
                try self.decls.append(&as_inst.base);

                return &as_inst.base;
            },
            .Type => {
                const ty = typed_value.val.toType();
                return self.emitType(src, ty);
            },
            .Fn => {
                const index = typed_value.val.cast(Value.Payload.Function).?.index;
                const module_fn = self.old_module.fns[index];

                var inst_table = std.AutoHashMap(*ir.Inst, *Inst).init(self.allocator);
                defer inst_table.deinit();

                var instructions = std.ArrayList(*Inst).init(self.allocator);
                defer instructions.deinit();

                for (module_fn.body) |inst| {
                    const new_inst = switch (inst.tag) {
                        .unreach => blk: {
                            const unreach_inst = try self.arena.allocator.create(Inst.Unreachable);
                            unreach_inst.* = .{
                                .base = .{ .src = inst.src, .tag = Inst.Unreachable.base_tag },
                                .positionals = .{},
                                .kw_args = .{},
                            };
                            break :blk &unreach_inst.base;
                        },
                        .constant => unreachable, // excluded from function bodies
                        .assembly => blk: {
                            const old_inst = inst.cast(ir.Inst.Assembly).?;
                            const new_inst = try self.arena.allocator.create(Inst.Asm);

                            const inputs = try self.arena.allocator.alloc(*Inst, old_inst.args.inputs.len);
                            for (inputs) |*elem, i| {
                                elem.* = try self.emitStringLiteral(inst.src, old_inst.args.inputs[i]);
                            }

                            const clobbers = try self.arena.allocator.alloc(*Inst, old_inst.args.clobbers.len);
                            for (clobbers) |*elem, i| {
                                elem.* = try self.emitStringLiteral(inst.src, old_inst.args.clobbers[i]);
                            }

                            const args = try self.arena.allocator.alloc(*Inst, old_inst.args.args.len);
                            for (args) |*elem, i| {
                                elem.* = try self.resolveInst(&inst_table, old_inst.args.args[i]);
                            }

                            new_inst.* = .{
                                .base = .{ .src = inst.src, .tag = Inst.Asm.base_tag },
                                .positionals = .{
                                    .asm_source = try self.emitStringLiteral(inst.src, old_inst.args.asm_source),
                                    .return_type = try self.emitType(inst.src, inst.ty),
                                },
                                .kw_args = .{
                                    .@"volatile" = old_inst.args.is_volatile,
                                    .output = if (old_inst.args.output) |o|
                                        try self.emitStringLiteral(inst.src, o)
                                    else
                                        null,
                                    .inputs = inputs,
                                    .clobbers = clobbers,
                                    .args = args,
                                },
                            };
                            break :blk &new_inst.base;
                        },
                        .ptrtoint => blk: {
                            const old_inst = inst.cast(ir.Inst.PtrToInt).?;
                            const new_inst = try self.arena.allocator.create(Inst.PtrToInt);
                            new_inst.* = .{
                                .base = .{ .src = inst.src, .tag = Inst.PtrToInt.base_tag },
                                .positionals = .{
                                    .ptr = try self.resolveInst(&inst_table, old_inst.args.ptr),
                                },
                                .kw_args = .{},
                            };
                            break :blk &new_inst.base;
                        },
                        .bitcast => blk: {
                            const old_inst = inst.cast(ir.Inst.BitCast).?;
                            const new_inst = try self.arena.allocator.create(Inst.BitCast);
                            new_inst.* = .{
                                .base = .{ .src = inst.src, .tag = Inst.BitCast.base_tag },
                                .positionals = .{
                                    .dest_type = try self.emitType(inst.src, inst.ty),
                                    .operand = try self.resolveInst(&inst_table, old_inst.args.operand),
                                },
                                .kw_args = .{},
                            };
                            break :blk &new_inst.base;
                        },
                    };
                    try instructions.append(new_inst);
                    try inst_table.putNoClobber(inst, new_inst);
                }

                const fn_type = try self.emitType(src, module_fn.fn_type);

                const fn_inst = try self.arena.allocator.create(Inst.Fn);
                fn_inst.* = .{
                    .base = .{ .src = src, .tag = Inst.Fn.base_tag },
                    .positionals = .{
                        .fn_type = fn_type,
                        .body = .{
                            .instructions = instructions.toOwnedSlice(),
                        },
                    },
                    .kw_args = .{},
                };
                try self.decls.append(&fn_inst.base);
                return &fn_inst.base;
            },
            else => |t| std.debug.panic("TODO implement emitTypedValue for {}", .{@tagName(t)}),
        }
    }

    fn emitType(self: *EmitZIR, src: usize, ty: Type) Allocator.Error!*Inst {
        switch (ty.tag()) {
            .isize => return self.emitPrimitiveType(src, .isize),
            .usize => return self.emitPrimitiveType(src, .usize),
            .c_short => return self.emitPrimitiveType(src, .c_short),
            .c_ushort => return self.emitPrimitiveType(src, .c_ushort),
            .c_int => return self.emitPrimitiveType(src, .c_int),
            .c_uint => return self.emitPrimitiveType(src, .c_uint),
            .c_long => return self.emitPrimitiveType(src, .c_long),
            .c_ulong => return self.emitPrimitiveType(src, .c_ulong),
            .c_longlong => return self.emitPrimitiveType(src, .c_longlong),
            .c_ulonglong => return self.emitPrimitiveType(src, .c_ulonglong),
            .c_longdouble => return self.emitPrimitiveType(src, .c_longdouble),
            .c_void => return self.emitPrimitiveType(src, .c_void),
            .f16 => return self.emitPrimitiveType(src, .f16),
            .f32 => return self.emitPrimitiveType(src, .f32),
            .f64 => return self.emitPrimitiveType(src, .f64),
            .f128 => return self.emitPrimitiveType(src, .f128),
            .anyerror => return self.emitPrimitiveType(src, .anyerror),
            else => switch (ty.zigTypeTag()) {
                .Bool => return self.emitPrimitiveType(src, .bool),
                .Void => return self.emitPrimitiveType(src, .void),
                .NoReturn => return self.emitPrimitiveType(src, .noreturn),
                .Type => return self.emitPrimitiveType(src, .type),
                .ComptimeInt => return self.emitPrimitiveType(src, .comptime_int),
                .ComptimeFloat => return self.emitPrimitiveType(src, .comptime_float),
                .Fn => {
                    const param_types = try self.allocator.alloc(Type, ty.fnParamLen());
                    defer self.allocator.free(param_types);

                    ty.fnParamTypes(param_types);
                    const emitted_params = try self.arena.allocator.alloc(*Inst, param_types.len);
                    for (param_types) |param_type, i| {
                        emitted_params[i] = try self.emitType(src, param_type);
                    }

                    const fntype_inst = try self.arena.allocator.create(Inst.FnType);
                    fntype_inst.* = .{
                        .base = .{ .src = src, .tag = Inst.FnType.base_tag },
                        .positionals = .{
                            .param_types = emitted_params,
                            .return_type = try self.emitType(src, ty.fnReturnType()),
                        },
                        .kw_args = .{
                            .cc = ty.fnCallingConvention(),
                        },
                    };
                    try self.decls.append(&fntype_inst.base);
                    return &fntype_inst.base;
                },
                else => std.debug.panic("TODO implement emitType for {}", .{ty}),
            },
        }
    }

    fn emitPrimitiveType(self: *EmitZIR, src: usize, tag: Inst.Primitive.BuiltinType) !*Inst {
        const primitive_inst = try self.arena.allocator.create(Inst.Primitive);
        primitive_inst.* = .{
            .base = .{ .src = src, .tag = Inst.Primitive.base_tag },
            .positionals = .{
                .tag = tag,
            },
            .kw_args = .{},
        };
        try self.decls.append(&primitive_inst.base);
        return &primitive_inst.base;
    }

    fn emitStringLiteral(self: *EmitZIR, src: usize, str: []const u8) !*Inst {
        const str_inst = try self.arena.allocator.create(Inst.Str);
        str_inst.* = .{
            .base = .{ .src = src, .tag = Inst.Str.base_tag },
            .positionals = .{
                .bytes = str,
            },
            .kw_args = .{},
        };
        try self.decls.append(&str_inst.base);
        return &str_inst.base;
    }
};
