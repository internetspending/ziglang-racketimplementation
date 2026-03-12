const std = @import("std");
const ast = @import("ast.zig");
const value = @import("value.zig");
const env_mod = @import("env.zig");

const Expr = ast.Expr;
const Value = value.Value;
const Env = value.Env;
const PrimOp = value.PrimOp;

pub const InterpError = error{
    UnboundIdentifier,
    ArityMismatch,
    TypeError,
    DivisionByZero,
    NotAFunction,
    UserError,
    OutOfMemory,
};

/// Evaluates an expression in the given environment and returns its value.
/// @params `allocator` is used for allocating argument arrays during function application.
/// `expr` - expression to evaluate
/// `env` - environment
pub fn interp(allocator: std.mem.Allocator, expr: *const Expr, env: *const Env) InterpError!Value {
    switch (expr.*) {
        // wraps the raw number or string in a Value and returns it.
        .num => |n| return Value{ .num = n },
        .str => |s| return Value{ .str = s },

        // Fails with UnboundIdentifier if the name is not in scope.
        .id => |name| {
            return env_mod.lookup(env, name) catch return error.UnboundIdentifier;
        },

        // e.g. {fun (x) => x} -> closureV([x], body, env)
        .fun_expr => |f| {
            return Value{ .closure = .{
                .params = f.params,
                .body = f.body,
                .env = env,
            } };
        },

        // e.g. {if true 1 2} -> 1
        .if_expr => |i| {
            const test_val = try interp(allocator, i.test_expr, env);
            switch (test_val) {
                .boolean => |b| {
                    if (b) {
                        return interp(allocator, i.then_expr, env);
                    } else {
                        return interp(allocator, i.else_expr, env);
                    }
                },
                else => return error.TypeError,
            }
        },

        // e.g. {+ 1 2} -> evaluates +, evaluates 1, evaluates 2, then applies
        .app => |a| {
            const func_val = try interp(allocator, a.func, env);

            // Allocate an array and fill it with the evaluated argument values.
            var arg_vals = try allocator.alloc(Value, a.args.len);
            for (a.args, 0..) |arg_expr, i| {
                arg_vals[i] = try interp(allocator, arg_expr, env);
            }

            return applyValue(allocator, func_val, arg_vals);
        },
    }
}

/// Applies a function value to a list of already-evaluated argument values.
/// Handles two cases: user-defined closures and built-in primitive operators.
/// Anything else (numbers, strings, booleans) is not callable and returns NotAFunction.
fn applyValue(allocator: std.mem.Allocator, func: Value, args: []const Value) InterpError!Value {
    switch (func) {
        .closure => |c| {
            // Checks number of arguments
            if (c.params.len != args.len) return error.ArityMismatch;

            // Bind each parameter to its argument in the closure's environment,
            // then evaluate the body in that new environment.
            const new_env = env_mod.extendMulti(allocator, c.env.?, c.params, args) catch
                return error.OutOfMemory;
            return interp(allocator, c.body.?, new_env);
        },
        // Dispatch built-in operators to their handler.
        .primop => |op| return applyPrimop(op, args),
        // Numbers, strings, booleans are not functions.
        else => return error.NotAFunction,
    }
}

fn expectNum(v: Value) InterpError!f64 {
    return switch (v) {
        .num => |n| n,
        else => error.TypeError,
    };
}

fn expectStr(v: Value) InterpError![]const u8 {
    return switch (v) {
        .str => |s| s,
        else => error.TypeError,
    };
}

fn valueEqual(a: Value, b: Value) bool {
    return switch (a) {
        .num => |n1| switch (b) {
            .num => |n2| n1 == n2,
            else => false,
        },
        .boolean => |b1| switch (b) {
            .boolean => |b2| b1 == b2,
            else => false,
        },
        .str => |s1| switch (b) {
            .str => |s2| std.mem.eql(u8, s1, s2),
            else => false,
        },
        else => false,
    };
}

/// Handles the built-in primitive operations.
fn applyPrimop(op: PrimOp, args: []const Value) InterpError!Value {
    switch (op) {
        .plus => {
            if (args.len != 2) return error.ArityMismatch;
            const a = switch (args[0]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            const b = switch (args[1]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            return Value{ .num = a + b };
        },

        .minus => {
            if (args.len != 2) return error.ArityMismatch;
            const a = switch (args[0]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            const b = switch (args[1]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            return Value{ .num = a - b };
        },

        .times => {
            if (args.len != 2) return error.ArityMismatch;
            const a = switch (args[0]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            const b = switch (args[1]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            return Value{ .num = a * b };
        },

        .div => {
            if (args.len != 2) return error.ArityMismatch;
            const a = switch (args[0]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            const b = switch (args[1]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            if (b == 0) return error.DivisionByZero;
            return Value{ .num = a / b };
        },

        .leq => {
            if (args.len != 2) return error.ArityMismatch;
            const a = switch (args[0]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            const b = switch (args[1]) {
                .num => |n| n,
                else => return error.TypeError,
            };
            return Value{ .boolean = a <= b };
        },

        .strlen => {
            if (args.len != 1) return error.ArityMismatch;
            const s = switch (args[0]) {
                .str => |str| str,
                else => return error.TypeError,
            };
            return Value{ .num = @as(f64, @floatFromInt(s.len)) };
        },

        .substring => {
            if (args.len != 3) return error.ArityMismatch;
            const s = switch (args[0]) {
                .str => |str| str,
                else => return error.TypeError,
            };
            const start = switch (args[1]) {
                .num => |n| @as(usize, @intFromFloat(n)),
                else => return error.TypeError,
            };
            const stop = switch (args[2]) {
                .num => |n| @as(usize, @intFromFloat(n)),
                else => return error.TypeError,
            };
            if (start > stop or stop > s.len) return error.TypeError;
            return Value{ .str = s[start..stop] };
        },

        .equal_huh => {
            if (args.len != 2) return error.ArityMismatch;

            switch (args[0]) {
                .num => |a| {
                    const b = switch (args[1]) {
                        .num => |n| n,
                        else => return Value{ .boolean = false },
                    };
                    return Value{ .boolean = a == b };
                },
                .boolean => |a| {
                    const b = switch (args[1]) {
                        .boolean => |bv| bv,
                        else => return Value{ .boolean = false },
                    };
                    return Value{ .boolean = a == b };
                },
                .str => |a| {
                    const b = switch (args[1]) {
                        .str => |sv| sv,
                        else => return Value{ .boolean = false },
                    };
                    return Value{ .boolean = std.mem.eql(u8, a, b) };
                },
                else => return Value{ .boolean = false },
            }
        },

        .aref => {
            if (args.len != 2) return error.ArityMismatch;
            const arr = switch (args[0]) {
                .closure => |c| c.params,
                else => return error.TypeError,
            };
            const index = switch (args[1]) {
                .num => |n| @as(usize, @intFromFloat(n)),
                else => return error.TypeError,
            };
            if (index >= arr.len) return error.TypeError;
            return Value{ .str = arr[index] };
        },

        .aset => {
            if (args.len != 3) return error.ArityMismatch;
            const arr = switch (args[0]) {
                .closure => |c| c.params,
                else => return error.TypeError,
            };
            const index = switch (args[1]) {
                .num => |n| @as(usize, @intFromFloat(n)),
                else => return error.TypeError,
            };
            if (index >= arr.len) return error.TypeError;
            const new_val = switch (args[2]) {
                .str => |s| s,
                else => return error.TypeError,
            };

            @constCast(arr)[index] = new_val;
            return Value{
                .closure = .{
                    .params = arr,
                    .body = null, // body and env are not relevant for this primop
                    .env = null,
                },
            };
        },

        .seq => {
            if (args.len != 2) return error.ArityMismatch;
            // evaluate first expression, ignoring its value
            _ = args[0];

            // Return the value of the second expression, interp should have alreayd evaluated it
            // before passing to applyPrimop so no need to really do anything else

            return args[1];
        },

        .error_fn => {
            if (args.len != 1) return error.ArityMismatch;
            return error.UserError;
        },
    }
}

pub fn topInterp(allocator: std.mem.Allocator, expr: *const Expr) ![]const u8 {
    const top_env = try env_mod.makeTopEnv(allocator);
    const result = try interp(allocator, expr, top_env);
    return value.serialize(allocator, result);
}
