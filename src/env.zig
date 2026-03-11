const std = @import("std");
const value = @import("value.zig");

pub const Value = value.Value;
pub const Env = value.Env;

/// Looks up a name in the environment chain, returning its value.
/// Searches from the innermost binding outward, so inner bindings shadow outer ones.
/// Returns error.UnboundIdentifier if the name is not found.
pub fn lookup(env: ?*const Env, name: []const u8) !Value {
    var current = env;
    while (current) |node| {
        if (std.mem.eql(u8, node.name, name)) return node.val;
        current = node.next;
    }
    return error.UnboundIdentifier;
}

/// Extends the environment with a single new name-value binding.
/// Returns a pointer to the new innermost frame; the original env is unchanged.
pub fn extend(allocator: std.mem.Allocator, env: ?*const Env, name: []const u8, val: Value) !*const Env {
    const node = try allocator.create(Env);
    node.* = .{ .name = name, .val = val, .next = env };
    return node;
}

/// Extends the environment with multiple bindings simultaneously (used for function application).
/// Requires names.len == vals.len; returns error.ArityMismatch otherwise.
pub fn extendMulti(
    allocator: std.mem.Allocator,
    env: ?*const Env,
    names: []const []const u8,
    vals: []const Value,
) !*const Env {
    if (names.len != vals.len) return error.ArityMismatch;
    var cur = env;
    for (names, vals) |name, val| {
        cur = try extend(allocator, cur, name, val);
    }
    return cur.?;
}

/// Builds the SZMX4 top-level environment, binding all required primitives and boolean names.
/// Per the spec: +, -, *, /, <=, substring, strlen, equal?, error, true, false.
pub fn makeTopEnv(allocator: std.mem.Allocator) !*const Env {
    const Binding = struct { name: []const u8, val: Value };
    const bindings = [_]Binding{
        .{ .name = "+", .val = .{ .primop = .plus } },
        .{ .name = "-", .val = .{ .primop = .minus } },
        .{ .name = "*", .val = .{ .primop = .times } },
        .{ .name = "/", .val = .{ .primop = .div } },
        .{ .name = "<=", .val = .{ .primop = .leq } },
        .{ .name = "substring", .val = .{ .primop = .substring } },
        .{ .name = "strlen", .val = .{ .primop = .strlen } },
        .{ .name = "equal?", .val = .{ .primop = .equal_huh } },
        .{ .name = "error", .val = .{ .primop = .error_fn } },
        .{ .name = "true", .val = .{ .boolean = true } },
        .{ .name = "false", .val = .{ .boolean = false } },
    };

    var env: ?*const Env = null;
    for (bindings) |b| {
        const node = try allocator.create(Env);
        node.* = .{ .name = b.name, .val = b.val, .next = env };
        env = node;
    }
    return env.?;
}
