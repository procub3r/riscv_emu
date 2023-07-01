const std = @import("std");

const dump_log = std.log.scoped(.dump);
const decode_log = std.log.scoped(.decode);

pub const xlen = 32;
pub const Register = std.meta.Int(.unsigned, xlen);

// simple RV32I core with a single hart
pub const Core = struct {
    pc: Register, // program counter
    x: [reg_count]Register, // registers x0 to x31

    const reg_count = 32;
    const Self = @This();

    pub fn init() Self {
        return Self{ .pc = 0, .x = .{0} ** reg_count };
    }

    pub fn execute(self: *Self, instr: u32) void {
        const opcode = instr & 0x7f;
        switch (opcode) {
            // register immediate instructions
            0b0010011 => {
                const rd = (instr & 0xf80) >> 7;
                const funct3 = (instr & 0x7000) >> 12;
                const rs1 = (instr & 0xf8000) >> 15;
                const imm: u12 = @truncate((instr & 0xfff00000) >> 20);
                switch (funct3) {
                    0b000 => {
                        decode_log.info("addi x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, imm });
                        self.x[rd] = self.x[rs1] +% imm;
                    },
                    0b010 => {
                        decode_log.info("slti x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, imm });
                        const rs1_signed: i32 = @bitCast(self.x[rs1]);
                        const imm_signed: i12 = @bitCast(imm);
                        self.x[rd] = @intFromBool(rs1_signed < imm_signed);
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    // dump the state of the core to the console
    pub fn dump(self: *Self) void {
        dump_log.debug("register dump", .{});
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            dump_log.debug("x{d:<2}= 0x{x:0>4}  " ** 2, .{ i, self.x[i], 16 + i, self.x[16 + i] });
        }
    }
};
