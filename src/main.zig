const std = @import("std");
const rv = @import("riscv_core.zig");

pub const std_options = struct {
    pub const log_level = .debug;
};

pub fn main() !void {
    var core = rv.Core.init();
    // lui x24, 0x1337
    core.execute(0b00000001001100110111110000110111);
    core.dump();
    // auipc x8, 0x1337
    core.execute(0b00000001001100110111010000010111);
    // auipc x8, 0x1337
    core.execute(0b00000001001100110111010000010111);
    core.dump();
}
