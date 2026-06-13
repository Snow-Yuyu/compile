package compile
import std.fs.*
import std.collection.*
import std.convert.*

public struct Instruction {
    public var opt: String; public var operand: Int64
    public init(opt: String, operand: Int64) { this.opt = opt; this.operand = operand }
}

public class VirtualMachine {
    private var codes: ArrayList<Instruction> 
    private var stack: Array<Int64>           
    private var ip: Int64                     
    private var top: Int64                    
    private var base: Int64
    private var output_buffer: ArrayList<String>

    public init() {
        this.codes = ArrayList<Instruction>()
        this.stack = Array<Int64>(10000, { _ => 0 })
        this.ip = 0; this.top = 0; this.base = 0
        this.output_buffer = ArrayList<String>()
    }

    public func load_codes(path: String) {
        let bytes = File.readFrom(path); let content = String.fromUtf8(bytes); let lines = content.split("\n")
        for (line in lines) {
            if (line.size == 0) { continue }
            let parts = line.split(":"); if (parts.size < 2) { continue }
            var current = ""; var tokens = ArrayList<String>()
            for (r in parts[1].toRuneArray()) {
                if (r == r' ' || r == r'\t' || r == r'\r') { if (current != "") { tokens.add(current); current = "" } } else { current += String(r) }
            }
            if (current != "") { tokens.add(current) }
            if (tokens.size > 0) { codes.add(Instruction(tokens[0], if(tokens.size > 1){Int64.parse(tokens[1])}else{0})) }
        }
    }

    public func run(out_path: String) {
        println("==============================================")
        println("         栈式抽象机启动        ")
        println("==============================================")
        
        output_buffer.add("=== 栈式抽象机运行结果 ===")
        
        while (ip < codes.size) {
            let inst = codes[ip]; ip++
            match (inst.opt) {
                case "LOAD" => stack[top] = stack[base + inst.operand]; top++
                case "STO" => top--; stack[base + inst.operand] = stack[top]
                case "LOAD_ARR" => top--; let offset = stack[top]; stack[top] = stack[base + inst.operand + offset]; top++
                case "STO_ARR" => top--; let val = stack[top]; top--; let offset = stack[top]; stack[base + inst.operand + offset] = val
                
                case "LOADG" => stack[top] = stack[inst.operand]; top++
                case "STOG" => top--; stack[inst.operand] = stack[top]
                case "LOADG_ARR" => top--; let offset = stack[top]; stack[top] = stack[inst.operand + offset]; top++
                case "STOG_ARR" => top--; let val = stack[top]; top--; let offset = stack[top]; stack[inst.operand + offset] = val
                
                case "LOADI" => stack[top] = inst.operand; top++
                case "POP" => top--
                case "COPY" => stack[top] = stack[top-1]; top++
                    
                case "ADD" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = a + b; top++
                case "SUB" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = a - b; top++
                case "MULT" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = a * b; top++
                case "DIV" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = a / b; top++
                case "EQ" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = if(a == b){1}else{0}; top++
                case "NOTEQ" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = if(a != b){1}else{0}; top++
                case "GT" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = if(a > b){1}else{0}; top++
                case "LES" => top--; let b = stack[top]; top--; let a = stack[top]; stack[top] = if(a < b){1}else{0}; top++

                case "BR" => ip = inst.operand
                case "BRF" => top--; if (stack[top] == 0) { ip = inst.operand }
                case "BRT" => top--; if (stack[top] != 0) { ip = inst.operand }

                case "CAL" => stack[top] = base; stack[top+1] = ip; base = top; ip = inst.operand
                case "ENTER" => top = base + 2 + inst.operand 
                case "RETURN" => 
                    let rv = stack[top - 1]; ip = stack[base + 1]; let prev_base = stack[base] 
                    top = base - inst.operand; stack[top] = rv; top++; base = prev_base
                    
                case "IN" => 
                    print(">> (等待输入) 请输入整数: ")
                    let input_str = readln()
                    let input_val = Int64.parse(input_str) 
                    stack[top] = input_val; top++
                    output_buffer.add(">> 用户输入: ${input_val}")

                case "OUT" => 
                    top--
                    let out_val = stack[top]
                    println("<< 计算输出: ${out_val}")
                    output_buffer.add("<< 计算输出: ${out_val}")

                case "STOP" => 
                    println("==============================================")
                    break 

                case _ => 
                    let err_msg = "[VM 崩溃] 未知指令: ${inst.opt}"
                    println(err_msg); output_buffer.add(err_msg)
                    break
            }
        }
        
        write_output_file(out_path)
    }

    private func write_output_file(path: String) {
        let targetPath = Path(path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(path)
        for (line in output_buffer) {
            file.write((line + "\n").toArray())
        }
        file.close()
        println("  └─ 虚拟机运行结果已成功导出至：${path}")
    }
}