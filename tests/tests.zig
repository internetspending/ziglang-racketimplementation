const std = @import("std");
const ast = @import("../src/ast.zig");
const value = @import("../src/value.zig");
const env = @import("../src/env.zig");
const examples = @import("../examples.zig");

const Expr = ast.Expr;
const makeExpr = ast.makeExpr;
const Value = value.Value;
const Env = value.Env;
const serialize = value.serialize;

// ---------------------------------------------------------------------------
// serialize
// ---------------------------------------------------------------------------

// serialize: a whole number drops the decimal point
test "serialize num 34 -> \"34\"" {
    const result = try serialize(std.testing.allocator, .{ .num = 34.0 });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("34", result);
}

// serialize: a fractional number keeps the decimal
test "serialize num 2.5 -> \"2.5\"" {
    const result = try serialize(std.testing.allocator, .{ .num = 2.5 });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("2.5", result);
}

// serialize: negative number
test "serialize num -1.5 -> \"-1.5\"" {
    const result = try serialize(std.testing.allocator, .{ .num = -1.5 });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("-1.5", result);
}

// serialize: true
test "serialize boolean true -> \"true\"" {
    const result = try serialize(std.testing.allocator, .{ .boolean = true });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("true", result);
}

// serialize: false
test "serialize boolean false -> \"false\"" {
    const result = try serialize(std.testing.allocator, .{ .boolean = false });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("false", result);
}

// serialize: string wraps in double-quotes
test "serialize str \"hello\" -> \"\\\"hello\\\"\"" {
    const result = try serialize(std.testing.allocator, .{ .str = "hello" });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"hello\"", result);
}

// serialize: closure renders as canonical #<procedure>
test "serialize closure -> \"#<procedure>\"" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const body = try makeExpr(arena.allocator(), Expr{ .num = 0 });
    const dummy_env = try arena.allocator().create(Env);
    dummy_env.* = .{ .name = "", .val = .{ .num = 0 }, .next = null };
    const cl = Value{ .closure = .{ .params = &.{}, .body = body, .env = dummy_env } };
    const result = try serialize(std.testing.allocator, cl);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("#<procedure>", result);
}

// serialize: primitive operator renders as canonical #<primop>
test "serialize primop -> \"#<primop>\"" {
    const result = try serialize(std.testing.allocator, .{ .primop = .plus });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("#<primop>", result);
}

// ---------------------------------------------------------------------------
// lookup
// ---------------------------------------------------------------------------

// lookup: finds a name in a single-frame environment
test "lookup finds bound name" {
    const node = Env{ .name = "x", .val = .{ .num = 42.0 }, .next = null };
    const result = try env.lookup(&node, "x");
    try std.testing.expect(result == .num);
    try std.testing.expectEqual(@as(f64, 42.0), result.num);
}

// lookup: returns error for a name not in the environment
test "lookup returns UnboundIdentifier for missing name" {
    const node = Env{ .name = "x", .val = .{ .num = 1 }, .next = null };
    try std.testing.expectError(error.UnboundIdentifier, env.lookup(&node, "y"));
}

// lookup: inner binding shadows an outer binding with the same name
test "lookup: inner binding shadows outer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outer = Env{ .name = "x", .val = .{ .num = 1.0 }, .next = null };
    const inner = try env.extend(arena.allocator(), &outer, "x", .{ .num = 99.0 });
    const result = try env.lookup(inner, "x");
    try std.testing.expectEqual(@as(f64, 99.0), result.num);
}

// ---------------------------------------------------------------------------
// extendMulti
// ---------------------------------------------------------------------------

// extendMulti: adds several bindings at once, all are findable afterward
test "extendMulti binds all names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const names = [_][]const u8{ "a", "b" };
    const vals = [_]Value{ .{ .num = 1.0 }, .{ .num = 2.0 } };
    const extended = try env.extendMulti(arena.allocator(), null, &names, &vals);
    const a = try env.lookup(extended, "a");
    const b = try env.lookup(extended, "b");
    try std.testing.expectEqual(@as(f64, 1.0), a.num);
    try std.testing.expectEqual(@as(f64, 2.0), b.num);
}

// extendMulti: mismatched lengths signal an arity error
test "extendMulti returns ArityMismatch for mismatched lengths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const names = [_][]const u8{"x"};
    const vals = [_]Value{ .{ .num = 1.0 }, .{ .num = 2.0 } };
    try std.testing.expectError(error.ArityMismatch, env.extendMulti(arena.allocator(), null, &names, &vals));
}

// ---------------------------------------------------------------------------
// makeTopEnv
// ---------------------------------------------------------------------------

// makeTopEnv: arithmetic primitives are present and tagged as primop
test "top_env: + is primop.plus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const top = try env.makeTopEnv(arena.allocator());
    const result = try env.lookup(top, "+");
    try std.testing.expect(result == .primop);
    try std.testing.expectEqual(value.PrimOp.plus, result.primop);
}

// makeTopEnv: true is bound to the boolean value true
test "top_env: true is boolean true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const top = try env.makeTopEnv(arena.allocator());
    const result = try env.lookup(top, "true");
    try std.testing.expect(result == .boolean);
    try std.testing.expectEqual(true, result.boolean);
}

// makeTopEnv: false is bound to the boolean value false
test "top_env: false is boolean false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const top = try env.makeTopEnv(arena.allocator());
    const result = try env.lookup(top, "false");
    try std.testing.expect(result == .boolean);
    try std.testing.expectEqual(false, result.boolean);
}

// makeTopEnv: error primitive is present
test "top_env: error is primop.error_fn" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const top = try env.makeTopEnv(arena.allocator());
    const result = try env.lookup(top, "error");
    try std.testing.expect(result == .primop);
    try std.testing.expectEqual(value.PrimOp.error_fn, result.primop);
}

// ---------------------------------------------------------------------------
// AST structure (examples.zig)
// ---------------------------------------------------------------------------

// {+ 1 2} is an app node whose func is the id "+"
test "buildPlusExample: app node with id func and 2 args" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const expr = try examples.buildPlusExample(arena.allocator());
    try std.testing.expect(expr.* == .app);
    try std.testing.expect(expr.app.func.* == .id);
    try std.testing.expectEqualStrings("+", expr.app.func.id);
    try std.testing.expectEqual(@as(usize, 2), expr.app.args.len);
}

// {if true 1 2} is an if_expr node whose test is the id "true"
test "buildIfExample: if_expr node with id test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const expr = try examples.buildIfExample(arena.allocator());
    try std.testing.expect(expr.* == .if_expr);
    try std.testing.expect(expr.if_expr.test_expr.* == .id);
}

// {fun (x) => x} is a fun_expr with exactly one parameter named "x"
test "buildIdentityFun: fun_expr with param x" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const expr = try examples.buildIdentityFun(arena.allocator());
    try std.testing.expect(expr.* == .fun_expr);
    try std.testing.expectEqual(@as(usize, 1), expr.fun_expr.params.len);
    try std.testing.expectEqualStrings("x", expr.fun_expr.params[0]);
}

// {{fun (x) => x} 5} is an app whose func is a fun_expr, applied to 5
test "buildIdentityApp: app of identity fun to 5" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const expr = try examples.buildIdentityApp(arena.allocator());
    try std.testing.expect(expr.* == .app);
    try std.testing.expect(expr.app.func.* == .fun_expr);
    try std.testing.expectEqual(@as(usize, 1), expr.app.args.len);
    try std.testing.expectEqual(@as(f64, 5.0), expr.app.args[0].num);
}
