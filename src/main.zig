const std = @import("std");
const rv = @import("riscv_core.zig");

pub const std_options = struct {
    pub const log_level = .debug;
};

pub fn main() !void {
    var core = rv.Core.init();
    core.execute(0b00110010101000101000001010010011);
    core.dump();
    core.execute(0b00110010101100101010001110010011);
    core.dump();
}
