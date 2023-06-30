const std = @import("std");

pub const xlen = 32;
pub const Register = std.meta.Int(.unsigned, xlen);

// simple RV32I core with a single hart
pub const Core = struct {
    pc: Register, // program counter
    x: [reg_count]Register, // registers x0 to x31

    const reg_count = 32;
    const Self = @This();

    pub fn init() Self {
        var core = Self{
            .pc = 0,
            .x = .{0} ** reg_count,
        };
        return core;
    }

    // dump the state of the core to the console
    pub fn dump(self: *Self) void {
        std.debug.print("register dump:\n", .{});
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            var j: usize = 0;
            while (j < 4) : (j += 1) {
                std.debug.print("x{d:<2}: 0x{x:0>8}\t", .{ i * 4 + j, self.x[i * 4 + j] });
            }
            std.debug.print("\n", .{});
        }
    }
};
