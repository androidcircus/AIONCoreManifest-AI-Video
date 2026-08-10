/**
 * pisa_compiler.cpp – Offline MAUD compiler for CogniForge VX
 * Ingest: NVVM IR (LLVM bitcode) from CUDA kernels, or SPIR‑V.
 * Output: MAUD binary (Prometheus ISA) that the SM emulator executes.
 * Based on MIT MIAOW LLVM backend, extended with tensor intrinsics.
 * Dr. Fei‑Fei Li, AI Lab.
 *
 * Build: clang++ -O3 -o pisa_compiler pisa_compiler.cpp \
 *        $(llvm-config --cxxflags --ldflags --libs core irreader passes)
 */

#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/Instructions.h>
#include <llvm/IR/Constants.h>
#include <llvm/IRReader/IRReader.h>
#include <llvm/Support/SourceMgr.h>
#include <llvm/Support/CommandLine.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Transforms/Utils/Cloning.h>
#include <fstream>
#include <vector>
#include <unordered_map>

using namespace llvm;

/* ---------- MAUD opcode definitions (MIAOW ISA) ---------- */
enum MaudOpcode : uint32_t {
    MAUD_S_MOV_B32      = 0x01000000,
    MAUD_V_ADD_F32      = 0x02000001,
    MAUD_V_MUL_F32      = 0x02000002,
    MAUD_V_FMA_F32      = 0x02000003,
    MAUD_TENSOR_MMA     = 0x03000001,  // custom tensor core op
    MAUD_DS_WRITE_B32   = 0x04000001,
    MAUD_DS_READ_B32    = 0x04000002,
    MAUD_S_BARRIER      = 0x05000001,
    MAUD_S_ENDPGM       = 0xFFFFFFFF
};

/* ---------- MAUD instruction encoding ---------- */
struct MaudInst {
    uint64_t bits;                // 64‑bit instruction word
};

/* Encode a 32‑bit opcode + 32‑bit operand format */
static MaudInst encode_maud(uint32_t opcode, uint32_t dst, uint32_t src0, uint32_t src1 = 0) {
    MaudInst inst;
    inst.bits = ((uint64_t)opcode << 32) | ((uint64_t)dst << 20) | (src0 << 10) | src1;
    return inst;
}

/* ---------- MAUD binary container ---------- */
struct MaudBinary {
    std::vector<MaudInst> code;
    uint32_t num_vgprs = 0;
    uint32_t num_sgprs = 0;
    uint32_t shared_mem_bytes = 0;
};

/* ---------- Virtual register allocator (simple infinite regs) ---------- */
class VirtualRegAlloc {
    uint32_t next_vgpr = 0;
    uint32_t next_sgpr = 0;
    std::unordered_map<const Value*, uint32_t> vreg_map;  // LLVM value -> VGPR index
    std::unordered_map<const Value*, uint32_t> sreg_map;  // scalar regs
public:
    uint32_t getVGPR(const Value *v) {
        auto it = vreg_map.find(v);
        if (it != vreg_map.end()) return it->second;
        uint32_t reg = next_vgpr++;
        vreg_map[v] = reg;
        return reg;
    }
    uint32_t getSGPR(const Value *v) {
        auto it = sreg_map.find(v);
        if (it != sreg_map.end()) return it->second;
        uint32_t reg = next_sgpr++;
        sreg_map[v] = reg;
        return reg;
    }
    uint32_t getNumVGPRs() const { return next_vgpr; }
    uint32_t getNumSGPRs() const { return next_sgpr; }
};

/* ---------- Core compiler: translate LLVM IR function to MAUD ---------- */
static MaudBinary compileKernel(Function &F) {
    MaudBinary bin;
    VirtualRegAlloc regs;

    // Map LLVM basic blocks to MAUD instruction offsets (for branches later)
    std::unordered_map<const BasicBlock*, size_t> blockStart;

    // Process all instructions in function
    for (auto &BB : F) {
        blockStart[&BB] = bin.code.size();
        for (auto &I : BB) {
            if (auto *op = dyn_cast<BinaryOperator>(&I)) {
                uint32_t dst = regs.getVGPR(op);
                uint32_t src0 = regs.getVGPR(op->getOperand(0));
                uint32_t src1 = regs.getVGPR(op->getOperand(1));
                uint32_t opcode;
                switch (op->getOpcode()) {
                    case Instruction::FAdd: opcode = MAUD_V_ADD_F32; break;
                    case Instruction::FMul: opcode = MAUD_V_MUL_F32; break;
                    case Instruction::FSub:
                    case Instruction::FDiv: // not directly supported; lower in preprocessing
                        opcode = MAUD_V_ADD_F32; break; // placeholder
                    default: opcode = MAUD_S_MOV_B32; break;
                }
                bin.code.push_back(encode_maud(opcode, dst, src0, src1));
            }
            else if (auto *ret = dyn_cast<ReturnInst>(&I)) {
                bin.code.push_back(encode_maud(MAUD_S_ENDPGM, 0, 0, 0));
            }
            // Other instructions (load/store, calls) lowered later.
        }
    }

    bin.num_vgprs = regs.getNumVGPRs();
    bin.num_sgprs = regs.getNumSGPRs();
    return bin;
}

/* ---------- Preprocessing: lower complex LLVM IR to simple operations ---------- */
static void preprocess(Module &M) {
    // Apply passes: scalar replacement, loop unroll, etc.
    LoopAnalysisManager LAM;
    FunctionAnalysisManager FAM;
    CGSCCAnalysisManager CGAM;
    ModuleAnalysisManager MAM;
    PassBuilder PB;
    PB.registerModuleAnalyses(MAM);
    PB.registerCGSCCAnalyses(CGAM);
    PB.registerFunctionAnalyses(FAM);
    PB.registerLoopAnalyses(LAM);
    PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);
    ModulePassManager MPM = PB.buildPerModuleDefaultPipeline(OptimizationLevel::O3);
    MPM.run(M, MAM);
}

/* ---------- Tensor core pattern recognition ---------- */
static void lowerTensorOps(Function &F) {
    // Detect wmma/mma patterns and replace with MAUD_TENSOR_MMA calls.
    // In our NVVM IR, we expect calls to @llvm.nvvm.wmma.mma.sync.*
    for (auto &BB : F) {
        for (auto &I : BB) {
            if (auto *call = dyn_cast<CallInst>(&I)) {
                Function *callee = call->getCalledFunction();
                if (callee && callee->getName().startswith("llvm.nvvm.wmma")) {
                    // Replace with a placeholder; actual lowering emits MAUD_TENSOR_MMA
                }
            }
        }
    }
}

/* ---------- Serialize MAUD binary to file ---------- */
static void writeBinary(const MaudBinary &bin, const std::string &path) {
    std::ofstream out(path, std::ios::binary);
    // Header: magic "MAUD", version, regs, code size
    uint32_t magic = 0x4455414D; // "MAUD"
    uint32_t version = 1;
    uint32_t codeSize = bin.code.size() * sizeof(MaudInst);
    out.write(reinterpret_cast<const char*>(&magic), 4);
    out.write(reinterpret_cast<const char*>(&version), 4);
    out.write(reinterpret_cast<const char*>(&bin.num_vgprs), 4);
    out.write(reinterpret_cast<const char*>(&bin.num_sgprs), 4);
    out.write(reinterpret_cast<const char*>(&bin.shared_mem_bytes), 4);
    out.write(reinterpret_cast<const char*>(&codeSize), 4);
    for (auto &inst : bin.code)
        out.write(reinterpret_cast<const char*>(&inst.bits), 8);
    out.close();
}

/* ---------- Command-line tool ---------- */
static cl::opt<std::string> InputFile(cl::Positional, cl::desc("<input .bc/.ll>"), cl::Required);
static cl::opt<std::string> OutputFile("o", cl::desc("Output .maud file"), cl::value_desc("filename"));
static cl::opt<std::string> KernelName("kernel", cl::desc("Kernel name"), cl::value_desc("function"));

int main(int argc, char **argv) {
    cl::ParseCommandLineOptions(argc, argv, "CogniForge PISA MAUD Compiler\n");

    // Parse LLVM IR
    LLVMContext ctx;
    SMDiagnostic err;
    std::unique_ptr<Module> mod = parseIRFile(InputFile, err, ctx);
    if (!mod) {
        err.print(argv[0], errs());
        return 1;
    }

    preprocess(*mod);

    // Find kernel function
    Function *kernel = mod->getFunction(KernelName.empty() ? "kernel" : KernelName);
    if (!kernel) {
        errs() << "Kernel function not found\n";
        return 1;
    }

    lowerTensorOps(*kernel);

    MaudBinary bin = compileKernel(*kernel);

    std::string outPath = OutputFile.empty() ? "kernel.maud" : OutputFile;
    writeBinary(bin, outPath);
    outs() << "MAUD binary written to " << outPath << " (" << bin.code.size() << " instructions)\n";

    return 0;
}
