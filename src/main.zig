const std = @import("std");
const rv = @import("riscv_core.zig");

pub const std_options = struct {
    pub const log_level = .debug;
};

pub fn main() !void {
    var mem = [_]u8{
        0x67, 0x0c, 0x64, 0x00, // jalr x24, x8, 6
        0x00, 0x00, 0x00, 0x00, // padding
        0x67, 0x0c, 0x64, 0x00, // jalr x24, x8, 6
    };
    var core = rv.Core.init(&mem);
    core.x[8] = 3;
    core.step();
    core.step();
    core.dump();
}
