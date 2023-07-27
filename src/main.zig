const std = @import("std");
const rv = @import("riscv_core.zig");

pub const std_options = struct {
    pub const log_level = .debug;
};

pub fn main() !void {
    var core = rv.Core.init();
    // jalr x24, x8, 6
    core.x[8] = 3;
    core.execute(0b00000000011001000000110001100111);
    core.dump();
}
