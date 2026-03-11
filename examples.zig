const std = @import("std");
const ast = @import("src/ast.zig");
const Expr = ast.Expr;
const makeExpr = ast.makeExpr;

/// {+ 1 2}
pub fn buildPlusExample(allocator: std.mem.Allocator) !*Expr {
    const plus_id = try makeExpr(allocator, Expr{ .id = "+" });
    const one = try makeExpr(allocator, Expr{ .num = 1.0 });
    const two = try makeExpr(allocator, Expr{ .num = 2.0 });

    const args = try allocator.alloc(*Expr, 2);
    args[0] = one;
    args[1] = two;

    return try makeExpr(allocator, Expr{
        .app = .{
            .func = plus_id,
            .args = args,
        },
    });
}

/// {if true 1 2}
pub fn buildIfExample(allocator: std.mem.Allocator) !*Expr {
    const true_id = try makeExpr(allocator, Expr{ .id = "true" });
    const one = try makeExpr(allocator, Expr{ .num = 1.0 });
    const two = try makeExpr(allocator, Expr{ .num = 2.0 });

    return try makeExpr(allocator, Expr{
        .if_expr = .{
            .test_expr = true_id,
            .then_expr = one,
            .else_expr = two,
        },
    });
}

/// {fun (x) => x}
pub fn buildIdentityFun(allocator: std.mem.Allocator) !*Expr {
    const body = try makeExpr(allocator, Expr{ .id = "x" });

    const params = try allocator.alloc([]const u8, 1);
    params[0] = "x";

    return try makeExpr(allocator, Expr{
        .fun_expr = .{
            .params = params,
            .body = body,
        },
    });
}

/// {{fun (x) => x} 5}
pub fn buildIdentityApp(allocator: std.mem.Allocator) !*Expr {
    const fun_expr = try buildIdentityFun(allocator);
    const five = try makeExpr(allocator, Expr{ .num = 5.0 });

    const args = try allocator.alloc(*Expr, 1);
    args[0] = five;

    return try makeExpr(allocator, Expr{
        .app = .{
            .func = fun_expr,
            .args = args,
        },
    });
}

/// "hello"
pub fn buildStringExample(allocator: std.mem.Allocator) !*Expr {
    return try makeExpr(allocator, Expr{ .str = "hello" });
}
