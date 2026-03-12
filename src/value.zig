const std = @import("std");
const Expr = @import("ast.zig").Expr;

/// The primitive operators available in the SZMX4 top-level environment.
/// These are first-class values that can be passed and applied like closures.
pub const PrimOp = enum {
    plus, // (+ a b) -> real
    minus, // (- a b) -> real
    times, // (* a b) -> real
    div, // (/ a b) -> real
    leq, // (<= a b) -> boolean
    substring, // (substring s start stop) -> string
    strlen, // (strlen s) -> real
    equal_huh, // (equal? a b) -> boolean
    error_fn, // (error v) -> nothing
    aref, // (aref arr i) -> value
    aset, // (aset arr i v) -> arr
    seq, // (seq e1 e2) -> value of e2

};

/// Env is defined here alongside Value to avoid circular imports,
/// since closures must capture the environment where they were defined.
pub const Env = struct {
    name: []const u8,
    val: Value,
    next: ?*const Env,
};

/// A runtime Value in SZMX4 — the result of evaluating any expression.
/// Primitive operators and booleans are values (not AST nodes), looked
/// up from the environment at runtime.
pub const Value = union(enum) {
    /// Real number, like 34 or 2.5
    num: f64,

    /// Boolean: true or false (bound by name in the top-level environment)
    boolean: bool,

    /// String literal, like "hello"
    str: []const u8,

    /// A closure: a function value paired with its defining environment
    closure: struct {
        params: []const []const u8,
        body: ?*const Expr,
        env: ?*const Env,
    },

    /// A primitive operator, like + or <=
    primop: PrimOp,
};

/// Serializes a Value to a newly-allocated string, as required by top-interp.
/// Numbers drop the decimal point when whole (34.0 -> "34", 2.5 -> "2.5").
/// Strings include wrapping double-quotes. Closures and primops use canonical forms.
pub fn serialize(allocator: std.mem.Allocator, val: Value) ![]const u8 {
    return switch (val) {
        .num => |n| blk: {
            // Render whole numbers without a decimal point to match Racket's ~v behavior
            if (n == @trunc(n) and !std.math.isInf(n) and !std.math.isNan(n)) {
                break :blk std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(n))});
            } else {
                break :blk std.fmt.allocPrint(allocator, "{d}", .{n});
            }
        },
        .boolean => |b| allocator.dupe(u8, if (b) "true" else "false"),
        .str => |s| std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .closure => allocator.dupe(u8, "#<procedure>"),
        .primop => allocator.dupe(u8, "#<primop>"),
    };
}
