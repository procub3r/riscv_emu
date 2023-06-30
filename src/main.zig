const std = @import("std");
const rv = @import("riscv_core.zig");

pub fn main() !void {
    var core = rv.Core.init();
    core.x[24] = 0x7331;
    core.dump();
}
