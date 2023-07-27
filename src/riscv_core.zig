const std = @import("std");

const dump_log = std.log.scoped(.dump);
const decode_log = std.log.scoped(.decode);

const xlen = 32;
const Register = std.meta.Int(.unsigned, xlen);

// instruction types
const InstrR = packed struct { opcode: u7, rd: u5, funct3: u3, rs1: u5, rs2: u5, funct7: u7 };
const InstrI = packed struct { opcode: u7, rd: u5, funct3: u3, rs1: u5, imm0_11: u12 };
const InstrS = packed struct { opcode: u7, imm0_4: u5, funct3: u3, rs1: u5, rs2: u5, imm5_11: u7 };
const InstrB = packed struct { opcode: u7, imm11: u1, imm1_4: u4, funct3: u3, rs1: u5, rs2: u5, imm5_10: u6, imm12: u1 };
const InstrU = packed struct { opcode: u7, rd: u5, imm12_31: u20 };
const InstrJ = packed struct { opcode: u7, rd: u5, imm12_19: u8, imm11: u1, imm1_10: u10, imm20: u1 };

const OpcodeType = enum(u7) {
    lui = 0b0110111,
    auipc = 0b0010111,
    jal = 0b1101111,
    jalr = 0b1100111,
    branch = 0b1100011,
    load = 0b0000011,
    store = 0b0100011,
    imm = 0b0010011,
    reg = 0b0110011,
    fence = 0b0001111,
    system = 0b1110011,
};

// cast the raw u32 instruction into its instruction type
fn castInstr(comptime InstrType: type, instr: u32) InstrType {
    return @as(InstrType, @bitCast(instr));
}

// sign extend into a 32 bit integer
// (there has GOT to be a better way)
fn signExtend(x: anytype) u32 {
    return @bitCast(@as(i32, @as(std.meta.Int(.signed, @typeInfo(@TypeOf(x)).Int.bits), @bitCast(x))));
}

fn getImmediate(instr: anytype) u32 {
    // the immediate is multiplied by 2 for B and J instructions before returning
    return switch (@TypeOf(instr)) {
        InstrI => instr.imm0_11,
        InstrS => @as(u12, instr.imm5_11) << 5 | instr.imm0_4,
        InstrB => @as(u13, instr.imm12) << 12 | @as(u13, instr.imm11) << 11 | @as(u13, instr.imm5_10) << 5 | @as(u13, instr.imm1_4) << 1,
        InstrU => @as(u32, instr.imm12_31) << 12,
        InstrJ => @as(u21, instr.imm20) << 20 | @as(u21, instr.imm12_19) << 12 | @as(u21, instr.imm11) << 11 | @as(u21, instr.imm1_10) << 1,
        else => @compileError("getImmediate: encountered wrong type"),
    };
}

fn unimplementedInstr(pc: u32, instr: u32) noreturn {
    @setCold(true);
    std.debug.panic("unimplemented instruction 0x{x} at 0x{x}", .{ instr, pc });
}

// simple RV32I core with a single hart
pub const Core = struct {
    pc: Register, // program counter
    x: [reg_count]Register, // registers x0 to x31

    const reg_count = 32;
    const Self = @This();

    pub fn init() Self {
        return Self{ .pc = 0, .x = .{0} ** reg_count };
    }

    pub fn execute(self: *Self, instr_raw: u32) void {
        const opcode: u7 = @truncate(instr_raw & 0x7f);
        switch (@as(OpcodeType, @enumFromInt(opcode))) {
            .lui => {
                const instr = castInstr(InstrU, instr_raw);
                self.x[instr.rd] = getImmediate(instr);
            },
            .auipc => {
                const instr = castInstr(InstrU, instr_raw);
                self.x[instr.rd] = self.pc +% getImmediate(instr);
            },
            .jal => {
                const instr = castInstr(InstrJ, instr_raw);
                self.x[instr.rd] = self.pc +% 4; // link
                // TODO: handle jumps to misaligned addresses
                self.pc +%= signExtend(getImmediate(instr));
                return; // return here to avoid incrementing pc at the end
            },
            .jalr => {
                const instr = castInstr(InstrI, instr_raw);
                if (instr.funct3 != 0) { // funct3 must be 0b000 for jalr
                    unimplementedInstr(self.pc, instr_raw);
                }
                self.x[instr.rd] = self.pc +% 4; // link
                // TODO: handle jumps to misaligned addresses
                self.pc = (self.x[instr.rs1] +% signExtend(getImmediate(instr))) >> 1 << 1;
                // (x >> 1 << 1) clears the least significant bit of x
                return;
            },
            .branch => {},
            .load => {},
            .store => {},
            .imm => {},
            .reg => {},
            .fence => {},
            .system => {},
        }
        self.pc += 4;
    }

    // dump the state of the core to the console
    pub fn dump(self: *Self) void {
        dump_log.debug("pc = 0x{x:0>8}", .{self.pc});
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            dump_log.debug("x{d:<2}= 0x{x:0>8}  " ** 2, .{ i, self.x[i], 16 + i, self.x[16 + i] });
        }
    }
};
