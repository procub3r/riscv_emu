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

fn illegalInstr(pc: u32, instr: u32) noreturn {
    @setCold(true);
    std.debug.panic("illegal instruction 0x{x} at 0x{x}", .{ instr, pc });
}

// simple RV32I core with a single hart
pub const Core = struct {
    pc: Register, // program counter
    x: [reg_count]Register, // registers x0 to x31
    memory: []u8,

    const reg_count = 32;
    const Self = @This();

    pub fn init(memory: []u8) Self {
        return Self{ .pc = 0, .x = .{0} ** reg_count, .memory = memory };
    }

    // (I might not be doing this right. works tho)
    fn load(self: *Self, addr: u32, comptime T: type) T {
        return std.mem.bytesAsValue(T, self.memory[addr..][0..@sizeOf(T)]).*;
    }

    fn store(self: *Self, addr: u32, value: anytype) void {
        const T = @TypeOf(value);
        std.mem.bytesAsValue(T, self.memory[addr..][0..@sizeOf(T)]).* = value;
    }

    pub fn step(self: *Self) void {
        if (self.pc >= self.memory.len) {
            std.debug.panic("pc 0x{x} exceeds memory bounds", .{self.pc});
        }
        self.execute(self.load(self.pc, u32));
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
                    illegalInstr(self.pc, instr_raw);
                }
                self.x[instr.rd] = self.pc +% 4; // link
                // TODO: handle jumps to misaligned addresses
                self.pc = (self.x[instr.rs1] +% signExtend(getImmediate(instr))) >> 1 << 1;
                // (x >> 1 << 1) clears the least significant bit of x
                return;
            },
            .branch => {
                const instr = castInstr(InstrB, instr_raw);
                const x: i32 = @bitCast(self.x[instr.rs1]);
                const y: i32 = @bitCast(self.x[instr.rs2]);
                const BranchType = enum(u3) { beq, bne, invalid0, invalid1, blt, bge, bltu, bgeu };
                const condition = switch (@as(BranchType, @enumFromInt(instr.funct3))) {
                    .beq => x == y,
                    .bne => x != y,
                    .blt => x < y,
                    .bge => x >= y,
                    // unsigned compare:
                    .bltu => self.x[instr.rs1] < self.x[instr.rs2],
                    .bgeu => self.x[instr.rs1] >= self.x[instr.rs2],
                    else => illegalInstr(self.pc, instr_raw),
                };
                if (condition) {
                    self.pc +%= signExtend(getImmediate(instr));
                    return;
                }
            },
            .load => {
                const instr = castInstr(InstrI, instr_raw);
                const LoadType = enum(u3) { lb, lh, lw, invalid0, lbu, lhu };
                const address = signExtend(getImmediate(instr)) +% self.x[instr.rs1];
                self.x[instr.rd] = switch (@as(LoadType, @enumFromInt(instr.funct3))) {
                    .lb => signExtend(self.load(address, u8)),
                    .lh => signExtend(self.load(address, u16)),
                    .lw => self.load(address, u32),
                    .lbu => self.load(address, u8),
                    .lhu => self.load(address, u16),
                    else => illegalInstr(self.pc, instr_raw),
                };
            },
            .store => {
                const instr = castInstr(InstrS, instr_raw);
                const StoreType = enum(u2) { sb, sh, sw };
                const address = signExtend(getImmediate(instr)) +% self.x[instr.rs1];
                switch (@as(StoreType, @enumFromInt(instr.funct3))) {
                    .sb => self.store(address, @as(u8, @truncate(self.x[instr.rs2]))),
                    .sh => self.store(address, @as(u16, @truncate(self.x[instr.rs2]))),
                    .sw => self.store(address, self.x[instr.rs2]),
                    else => illegalInstr(self.pc, instr_raw),
                }
            },
            .imm => {
                const instr = castInstr(InstrI, instr_raw);
                const ImmType = enum(u3) { addi, slli, slti, sltiu, xori, sr_li_ai, ori, andi };
                const imm = getImmediate(instr);
                const imm_upper = imm >> 5;
                const shamt: u5 = @truncate(imm);
                const imm_extended = signExtend(imm);
                const x: i32 = @bitCast(self.x[instr.rs1]);
                const y: i32 = @bitCast(imm_extended);
                self.x[instr.rd] = switch (@as(ImmType, @enumFromInt(instr.funct3))) {
                    .addi => x +% y,
                    .slti => @intFromBool(x < y),
                    .sltiu => @intFromBool(self.x[instr.rs1] < imm_extended),
                    .xori => x ^ y,
                    .ori => x | y,
                    .andi => x & y,
                    .slli => shiftLeft: {
                        if (imm_upper != 0) {
                            illegalInstr(self.pc, instr_raw);
                        }
                        break :shiftLeft x << shamt;
                    },
                    .sr_li_ai => shiftRight: {
                        if (imm_upper == 0) { // srli
                            break :shiftRight x >> shamt;
                        } else if (imm_upper == 0b0100000) {
                            if (@as(i32, @bitCast(x)) < 0) {
                                break :shiftRight ~(~x >> shamt);
                            } else {
                                break :shiftRight x >> shamt;
                            }
                        } else {
                            illegalInstr(self.pc, instr_raw);
                        }
                    },
                };
            },
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
