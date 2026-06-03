package compile

import std.collection.*
import std.fs.*
import std.convert.*

// ==========================================
// 1. AST 反序列化器 
// ==========================================
class ASTDeserializer {
    
    public static func fromString(type_str: String): Int64 {
        if (type_str == "Program") { return 1 }
        if (type_str == "MainDecl") { return 2 }
        if (type_str == "Block") { return 3 }
        if (type_str == "VarDecl") { return 4 }
        if (type_str == "ArrayDecl") { return 5 }
        if (type_str == "Assign") { return 6 }
        if (type_str == "ArrayAssign") { return 7 }
        if (type_str == "IfStat") { return 8 }
        if (type_str == "ReadStat") { return 9 }
        if (type_str == "WriteStat") { return 10 }
        if (type_str == "BinOp") { return 11 }
        if (type_str == "Identifier") { return 12 }
        if (type_str == "ArrayAccess") { return 13 }
        if (type_str == "Number") { return 14 }
        if (type_str == "WhileStat") { return 15 }
        if (type_str == "ForStat") { return 16 }
        return 0
    }

    public static func load_from_file(filepath: String): ASTNode {
        let bytes = File.readFrom(filepath)
        let content = String.fromUtf8(bytes)
        let lines = content.split("\n")
        
        var stack = ArrayList<ASTNode>()
        var depths = ArrayList<Int64>()
        var root = ASTNode(NodeType.ErrorNode) 

        for (line in lines) {
            // ✨ 修复 1：移除 trim()，直接通过判断跳过无效行
            if (line.size == 0 || line.startsWith("---") || line.startsWith("└─")) { continue }

            var first_letter_idx = -1
            let runes = line.toRuneArray()
            for (i in 0..runes.size) {
                if ((runes[i] >= r'A' && runes[i] <= r'Z') || (runes[i] >= r'a' && runes[i] <= r'z')) {
                    first_letter_idx = i; break
                }
            }
            
            // 如果这一行连字母都没有，说明是空白行，直接跳过
            if (first_letter_idx == -1) { continue }

            let depth = first_letter_idx / 4 

            var rest = ""
            for (i in first_letter_idx..runes.size) {
                rest += runes[i].toString()
            }
            
            let parts = rest.split(" ['")
            let type_str = parts[0].split(" ")[0] 
            var node_name = ""
            if (parts.size > 1) { node_name = parts[1].replace("']", "") }

            let node = ASTNode(fromString(type_str), name: node_name)

            if (depth == 0) {
                root = node
                stack.add(node); depths.add(0)
            } else {
                while (depths.size > 0 && depths[depths.size - 1] >= depth) {
                    // ✨ 修复 2：仓颉的 remove 需要传入 Range
                    stack.remove((stack.size - 1)..stack.size)
                    depths.remove((depths.size - 1)..depths.size)
                }
                stack[stack.size - 1].children.add(node)
                stack.add(node); depths.add(depth)
            }
        }
        return root
    }
}

// ==========================================
// 2. 语义分析与中间代码生成器
// ==========================================
class SemanticAnalyzer {
    private var symbol_table: Map<String, Int64> 
    private var pcode: ArrayList<String>         
    private var next_addr: Int64
    private var semantic_error_cnt: Int64

    public init() {
        this.symbol_table = HashMap<String, Int64>()
        this.pcode = ArrayList<String>()
        this.next_addr = 0
        this.semantic_error_cnt = 0
    }

    public func run(root: ASTNode, out_path: String) {
        println("  └─ 🔍 正在执行静态语义检查 (符号表一致性校验)...")
        
        check_semantics(root)
        
        if (semantic_error_cnt > 0) {
            println("  └─ ❌ 语义分析失败！共发现 ${semantic_error_cnt} 处语义错误，中止代码生成。")
            return
        }
        
        println("  └─ ✓ 语义分析通过！0 处错误。")
        println("  └─ 🚀 正在基于 AST 生成栈式虚拟机 P-Code 指令...")
        
        this.symbol_table.clear(); this.next_addr = 0; this.pcode.clear()
        gen_code(root)

        let targetPath = Path(out_path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        
        println("\n--- 目标中间代码 (P-Code) ---")
        for (i in 0..pcode.size) {
            let code_line = "${i}:\t${pcode[i]}"
            println(code_line)
            file.write((code_line + "\n").toArray())
        }
        file.close()
        println("\n  └─ 中间代码已成功保存至：${out_path}")
    }

    // ------------------------------------------
    // [阶段 1]：纯粹的语义一致性检查
    // ✨ 修复 3：递归函数显式声明 : Unit
    // ------------------------------------------
    private func check_semantics(node: ASTNode): Unit {
        if (node.node_type == NodeType.ErrorNode) { return }

        if (node.node_type == NodeType.VarDecl || node.node_type == NodeType.ArrayDecl) {
            if (symbol_table.contains(node.name)) {
                println("语义错：变量 '${node.name}' 重复声明！")
                semantic_error_cnt++
            } else {
                symbol_table[node.name] = next_addr; next_addr++
            }
        }
        else if (node.node_type == NodeType.Assign || node.node_type == NodeType.ArrayAssign) {
            let var_name = node.children[0].name
            if (!symbol_table.contains(var_name)) {
                println("语义错：变量 '${var_name}' 赋值前未声明！")
                semantic_error_cnt++
            }
        }
        else if (node.node_type == NodeType.ReadStat) {
            let var_name = node.children[0].name
            if (!symbol_table.contains(var_name)) {
                println("语义错：在 read 语句中引用了未声明的变量 '${var_name}'！")
                semantic_error_cnt++
            }
        }
        else if (node.node_type == NodeType.Identifier || node.node_type == NodeType.ArrayAccess) {
            if (!symbol_table.contains(node.name)) {
                println("语义错：在表达式中未声明先引用了变量 '${node.name}'！")
                semantic_error_cnt++
            }
        }

        for (child in node.children) { check_semantics(child) }
    }

    // ------------------------------------------
    // [阶段 2]：中间代码生成 
    // ✨ 修复 3：递归函数显式声明 : Unit
    // ------------------------------------------
    private func gen_code(node: ASTNode): Unit {
        if (node.node_type == NodeType.Program) {
            gen_code(node.children[0])
            pcode.add("STOP") 
        }
        else if (node.node_type == NodeType.MainDecl || node.node_type == NodeType.Block) {
            for (child in node.children) { gen_code(child) }
        }
        else if (node.node_type == NodeType.VarDecl) {
            symbol_table[node.name] = next_addr; next_addr++
            if (node.children.size > 0) { 
                gen_code(node.children[0]) 
                // ✨ 修复 4：移除 ?? 0，直接安全获取 Map 的值
                pcode.add("STO ${symbol_table[node.name]}") 
            }
        }
        else if (node.node_type == NodeType.ArrayDecl) {
            symbol_table[node.name] = next_addr
            next_addr += 10 
        }
        else if (node.node_type == NodeType.Assign) {
            gen_code(node.children[1]) 
            pcode.add("STO ${symbol_table[node.children[0].name]}")
        }
        else if (node.node_type == NodeType.ReadStat) {
            pcode.add("IN") 
            pcode.add("STO ${symbol_table[node.children[0].name]}") 
        }
        else if (node.node_type == NodeType.WriteStat) {
            gen_code(node.children[0]) 
            pcode.add("OUT") 
        }
        else if (node.node_type == NodeType.Number) {
            pcode.add("LOADI ${node.name}") 
        }
        else if (node.node_type == NodeType.Identifier) {
            pcode.add("LOAD ${symbol_table[node.name]}") 
        }
        else if (node.node_type == NodeType.BinOp) {
            gen_code(node.children[0]) 
            gen_code(node.children[1]) 
            let op = node.name
            if (op == "+") { pcode.add("ADD") }        
            else if (op == "-") { pcode.add("SUB") }   
            else if (op == "*") { pcode.add("MULT") }  
            else if (op == "/") { pcode.add("DIV") }   
            else if (op == ">") { pcode.add("GT") }    
            else if (op == "<") { pcode.add("LES") }   
            else if (op == ">=") { pcode.add("GE") }   
            else if (op == "<=") { pcode.add("LE") }   
            else if (op == "==") { pcode.add("EQ") }   
            else if (op == "!=") { pcode.add("NOTEQ") }
        }
        else if (node.node_type == NodeType.IfStat) {
            gen_code(node.children[0]) 
            let cx1 = pcode.size
            pcode.add("BRF ?") 
            
            gen_code(node.children[1]) 
            
            if (node.children.size > 2) { 
                let cx2 = pcode.size
                pcode.add("BR ?") 
                pcode[cx1] = "BRF ${pcode.size}" 
                gen_code(node.children[2]) 
                pcode[cx2] = "BR ${pcode.size}"  
            } else {
                pcode[cx1] = "BRF ${pcode.size}" 
            }
        }
        else if (node.node_type == NodeType.WhileStat) {
            let start = pcode.size 
            gen_code(node.children[0]) 
            let cx = pcode.size
            pcode.add("BRF ?") 
            
            gen_code(node.children[1]) 
            pcode.add("BR ${start}")
            
            pcode[cx] = "BRF ${pcode.size}" 
        }
    }
}