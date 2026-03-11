const std = @import("std");

/// Defining types for the AST of SZMX4.
/// Expr represents all SZMX4 expression forms after parsing/desugaring.
/// Primitive operators and booleans are not special AST nodes; they are
/// represented as identifiers and looked up in the environment.
///
/// let is omitted from the core AST because it should be desugared into
/// function application.
pub const Expr = union(enum) {
    /// Numeric literal, like 34 or 2.5
    num: f64,

    /// Identifier, like x, true, false, +
    id: []const u8,

    /// String literal, like "hello"
    str: []const u8,

    /// Conditional expression: {if test then else}
    if_expr: struct {
        test_expr: *Expr,
        then_expr: *Expr,
        else_expr: *Expr,
    },

    /// Function literal: {fun (x y z) => body}
    fun_expr: struct {
        params: []const []const u8,
        body: *Expr,
    },

    /// Function application: {func arg1 arg2 ...}
    app: struct {
        func: *Expr,
        args: []*Expr,
    },
};

/// Allocates an Expr node and returns a pointer to it.
pub fn makeExpr(allocator: std.mem.Allocator, expr: Expr) !*Expr {
    const ptr = try allocator.create(Expr);
    ptr.* = expr;
    return ptr;
}
