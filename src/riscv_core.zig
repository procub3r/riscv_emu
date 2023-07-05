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
                        // TODO: test this instruction
                        decode_log.info("slti x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, imm });
                        const rs1_signed: i32 = @bitCast(self.x[rs1]);
                        const imm_signed: i12 = @bitCast(imm);
                        const imm_signed_extended: i32 = @intCast(imm_signed);
                        self.x[rd] = @intFromBool(rs1_signed < imm_signed_extended);
                    },
                    0b011 => {
                        decode_log.info("sltiu x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, imm });
                        const imm_signed: i12 = @bitCast(imm);
                        const imm_signed_extended: i32 = @intCast(imm_signed);
                        const imm_extended: u32 = @bitCast(imm_signed_extended);
                        self.x[rd] = @intFromBool(rs1 < imm_extended);
                    },
                    0b100 => {
                        decode_log.info("xori x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, imm });
                        const imm_signed: i12 = @bitCast(imm);
                        const imm_signed_extended: i32 = @intCast(imm_signed);
                        const imm_extended: u32 = @bitCast(imm_signed_extended);
                        self.x[rd] = rs1 ^ imm_extended;
                    },
                    0b110 => {
                        decode_log.info("ori x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, imm });
                        const imm_signed: i12 = @bitCast(imm);
                        const imm_signed_extended: i32 = @intCast(imm_signed);
                        const imm_extended: u32 = @bitCast(imm_signed_extended);
                        self.x[rd] = rs1 | imm_extended;
                    },
                    0b111 => {
                        decode_log.info("andi x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, imm });
                        const imm_signed: i12 = @bitCast(imm);
                        const imm_signed_extended: i32 = @intCast(imm_signed);
                        const imm_extended: u32 = @bitCast(imm_signed_extended);
                        self.x[rd] = rs1 & imm_extended;
                    },
                    0b001 => {
                        const shamt: u5 = @truncate(imm); // lower 5 bits of imm
                        decode_log.info("slli x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, shamt });
                        self.x[rd] = rs1 << shamt;
                    },
                    0b101 => {
                        if (imm == 0) {
                            const shamt: u5 = @truncate(imm); // lower 5 bits of imm
                            decode_log.info("srli x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, shamt });
                            self.x[rd] = rs1 >> shamt;
                        } else if (imm == 0x400) {
                            const shamt: u5 = @truncate(imm); // lower 5 bits of imm
                            decode_log.info("srai x{d}, x{d}, 0x{x:0>4}", .{ rd, rs1, shamt });
                            decode_log.warn("Instruction srai not implemented", .{});
                        }
                    },
                    else => {},
                }
            },
            else => {
                decode_log.warn("Unimplimented opcode 0b{b:0>7}", .{opcode});
            },
        }
    }

    // dump the state of the core to the console
    pub fn dump(self: *Self) void {
        dump_log.debug("register dump", .{});
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            dump_log.debug("x{d:<2}= 0x{x:0>8}  " ** 2, .{ i, self.x[i], 16 + i, self.x[16 + i] });
        }
    }
};
