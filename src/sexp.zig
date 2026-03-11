pub const Sexp = union(enum) {
    num: f64,
    sym: []const u8,
    str: []const u8,
    list: []const Sexp,
};
