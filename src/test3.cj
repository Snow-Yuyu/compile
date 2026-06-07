package compile

import std.collection.*
import std.fs.*
import std.convert.*

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
            if (line.size == 0 || line.startsWith("---") || line.startsWith("└─")) { continue }

            var first_letter_idx = -1
            let runes = line.toRuneArray()
            for (i in 0..runes.size) {
                if ((runes[i] >= r'A' && runes[i] <= r'Z') || (runes[i] >= r'a' && runes[i] <= r'z')) {
                    first_letter_idx = i; break
                }
            }
            if (first_letter_idx == -1) { continue }
            let depth = first_letter_idx / 4 

            var rest = ""
            for (i in first_letter_idx..runes.size) { rest += runes[i].toString() }
            
            // ✨ 解析我们在 test2 存进去的 <行号>
            var node_name = ""
            var node_line: Int64 = 0
            
            let parts = rest.split(" <")
            if (parts.size > 1) {
                let line_str = parts[1].replace(">", "")
                node_line = Int64.parse(line_str)
            }
            
            let type_and_name = parts[0]
            let name_parts = type_and_name.split(" ['")
            let type_str = name_parts[0].split(" ")[0] 
            if (name_parts.size > 1) { node_name = name_parts[1].replace("']", "") }

            // 完美重建带有行号的节点
            let node = ASTNode(fromString(type_str), name: node_name, line: node_line)

            if (depth == 0) {
                root = node
                stack.add(node); depths.add(0)
            } else {
                while (depths.size > 0 && depths[depths.size - 1] >= depth) {
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
    private var is_array_map: Map<String, Bool>  
    private var pcode: ArrayList<String>         
    private var next_addr: Int64
    private var semantic_error_cnt: Int64

    public init() {
        this.symbol_table = HashMap<String, Int64>()
        this.is_array_map = HashMap<String, Bool>() 
        this.pcode = ArrayList<String>()
        this.next_addr = 0
        this.semantic_error_cnt = 0
    }

    public func run(root: ASTNode, out_path: String) {
        println("  └─ 🔍 正在执行静态语义检查 (符号表一致性与类型校验)...")
        
        check_semantics(root)
        
        if (semantic_error_cnt > 0) {
            println("  └─ ❌ 语义分析失败！共发现 ${semantic_error_cnt} 处语义错误，中止代码生成。")
            return
        }
        
        println("  └─ ✓ 语义分析通过！0 处错误。")
        println("  └─ 🚀 正在基于 AST 生成栈式虚拟机 P-Code 指令...")
        
        this.symbol_table.clear(); this.is_array_map.clear(); this.next_addr = 0; this.pcode.clear()
        gen_code(root)

        let targetPath = Path(out_path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        
        for (i in 0..pcode.size) {
            let code_line = "${i}:\t${pcode[i]}"
            file.write((code_line + "\n").toArray())
        }
        file.close()
        println("\n  └─ 中间代码已成功保存至：${out_path}")
    }

    // ------------------------------------------
    // [阶段 1]：严格的语义与类型一致性检查
    // ------------------------------------------
    private func check_semantics(node: ASTNode): Unit {
        if (node.node_type == NodeType.ErrorNode) { return }

        if (node.node_type == NodeType.VarDecl || node.node_type == NodeType.ArrayDecl) {
            if (symbol_table.contains(node.name)) {
                println("第 ${node.line} 行语义错：变量 '${node.name}' 重复声明！")
                semantic_error_cnt++
            } else {
                symbol_table[node.name] = next_addr; next_addr++
                if (node.node_type == NodeType.ArrayDecl) { is_array_map[node.name] = true }
            }
        }
        else if (node.node_type == NodeType.Assign) {
            let var_name = node.children[0].name
            if (!symbol_table.contains(var_name)) {
                println("第 ${node.line} 行语义错：变量 '${var_name}' 赋值前未声明！")
                semantic_error_cnt++
            } 
            else if (is_array_map.contains(var_name)) {
                println("第 ${node.line} 行语义错：类型不匹配！'${var_name}' 是数组，不能直接赋值，缺少下标！")
                semantic_error_cnt++
            }
        }
        else if (node.node_type == NodeType.ArrayAssign) {
            let arr_node = node.children[0]
            if (!symbol_table.contains(arr_node.name)) {
                println("第 ${node.line} 行语义错：数组 '${arr_node.name}' 赋值前未声明！")
                semantic_error_cnt++
            }
            else if (!is_array_map.contains(arr_node.name)) {
                println("第 ${node.line} 行语义错：类型不匹配！'${arr_node.name}' 是普通变量，不能使用 [] 访问！")
                semantic_error_cnt++
            }
        }
        else if (node.node_type == NodeType.ReadStat) {
            let target_node = node.children[0]
            
            // 情况 A：如果是普通的变量读取 (Identifier)
            if (target_node.node_type == NodeType.Identifier) {
                let var_name = target_node.name
                if (!symbol_table.contains(var_name)) {
                    println("第 ${node.line} 行语义错：在 read 语句中引用了未声明的变量 '${var_name}'！")
                    semantic_error_cnt++
                }
                else if (is_array_map.contains(var_name)) {
                    println("第 ${node.line} 行语义错：类型不匹配！不能直接 read 整个数组 '${var_name}'！")
                    semantic_error_cnt++
                }
            }
            // 情况 B：如果是数组元素读取 (ArrayAccess，比如 arr[i])
            else if (target_node.node_type == NodeType.ArrayAccess) {
                // 放行！具体的声明和越界检查，交给最底下自动遍历 children 时的 ArrayAccess 逻辑去处理
            }
        }
        else if (node.node_type == NodeType.ForStat) {
            let loop_var = node.children[0].name
            if (!symbol_table.contains(loop_var)) {
                symbol_table[loop_var] = next_addr; next_addr++
            }
            
            // ✨ 核心修复：手动检查循环遍历的数组对象，拦截错误用法，但放行合法的数组
            let arr_node = node.children[1]
            if (!symbol_table.contains(arr_node.name)) {
                println("第 ${arr_node.line} 行语义错：for 循环遍历的对象 '${arr_node.name}' 未声明！")
                semantic_error_cnt++
            } else if (!is_array_map.contains(arr_node.name)) {
                println("第 ${arr_node.line} 行语义错：类型不匹配！for 循环只能遍历数组，'${arr_node.name}' 是普通变量！")
                semantic_error_cnt++
            }
            
            // ⚠️ 重点：跳过检查 children[1] (也就是跳过默认把 arr 当成普通表达式去检查)，只去检查循环体
            check_semantics(node.children[2]); return 
        }
        else if (node.node_type == NodeType.ArrayAccess) {
            if (!symbol_table.contains(node.name)) {
                println("第 ${node.line} 行语义错：在表达式中未声明先引用了数组 '${node.name}'！")
                semantic_error_cnt++
            }
            else if (!is_array_map.contains(node.name)) {
                println("第 ${node.line} 行语义错：类型不匹配！'${node.name}' 是普通变量，不能使用 [] 访问！")
                semantic_error_cnt++
            }
            check_semantics(node.children[0]); return 
        }
        else if (node.node_type == NodeType.Identifier) {
            if (!symbol_table.contains(node.name)) {
                println("第 ${node.line} 行语义错：在表达式中未声明先引用了变量 '${node.name}'！")
                semantic_error_cnt++
            }
            else if (is_array_map.contains(node.name)) {
                println("第 ${node.line} 行语义错：类型不匹配！'${node.name}' 是数组名，不能直接参与表达式计算！")
                semantic_error_cnt++
            }
        }

        for (child in node.children) { check_semantics(child) }
    }

    // ------------------------------------------
    // [阶段 2]：中间代码生成 
    // ------------------------------------------
    private func gen_code(node: ASTNode): Unit {
        if (node.node_type == NodeType.Program) {
            gen_code(node.children[0]); pcode.add("STOP") 
        }
        else if (node.node_type == NodeType.MainDecl || node.node_type == NodeType.Block) {
            for (child in node.children) { gen_code(child) }
        }
        else if (node.node_type == NodeType.VarDecl) {
            symbol_table[node.name] = next_addr; next_addr++
            if (node.children.size > 0) { 
                gen_code(node.children[0]); pcode.add("STO ${symbol_table[node.name]}") 
            } else {
                // ✨ 普通变量显式内存分配：未赋初值时，显式生成清零指令
                pcode.add("LOADI 0"); pcode.add("STO ${symbol_table[node.name]}")
            }
        }
        else if (node.node_type == NodeType.ArrayDecl) {
            // 1. 动态获取语法树中真实声明的数组大小
            var arr_size: Int64 = 10
            if (node.children.size > 0 && node.children[0].node_type == NodeType.Number) {
                arr_size = Int64.parse(node.children[0].name)
            }
            
            symbol_table[node.name] = next_addr
            
            // 2. ✨ 数组显式内存分配：在 P-Code 中生成一段连续的初始化指令，真正在内存中占位！
            for (i in 0..arr_size) {
                pcode.add("LOADI 0")
                pcode.add("STO ${next_addr + i}")
            }
            
            next_addr += arr_size 
        }
        else if (node.node_type == NodeType.Assign) {
            gen_code(node.children[1]); pcode.add("STO ${symbol_table[node.children[0].name]}")
        }
        else if (node.node_type == NodeType.ArrayAssign) {
            gen_code(node.children[1]); gen_code(node.children[0].children[0]) 
            pcode.add("STO_ARR ${symbol_table[node.children[0].name]}") 
        }
        else if (node.node_type == NodeType.ReadStat) {
            pcode.add("IN") // 从键盘读入数据，压入栈顶
            
            let target_node = node.children[0]
            if (target_node.node_type == NodeType.ArrayAccess) {
                // ✨ 如果是向数组读入：先算出中括号里的下标压栈，再调用 STO_ARR
                gen_code(target_node.children[0]) 
                pcode.add("STO_ARR ${symbol_table[target_node.name]}") 
            } else {
                // 普通标量变量读入
                pcode.add("STO ${symbol_table[target_node.name]}") 
            }
        }
        else if (node.node_type == NodeType.WriteStat) {
            gen_code(node.children[0]); pcode.add("OUT") 
        }
        else if (node.node_type == NodeType.Number) {
            pcode.add("LOADI ${node.name}") 
        }
        else if (node.node_type == NodeType.Identifier) {
            pcode.add("LOAD ${symbol_table[node.name]}") 
        }
        else if (node.node_type == NodeType.ArrayAccess) {
            gen_code(node.children[0]); pcode.add("LOAD_ARR ${symbol_table[node.name]}") 
        }
        else if (node.node_type == NodeType.BinOp) {
            gen_code(node.children[0]); gen_code(node.children[1]) 
            let op = node.name
            if (op == "+") { pcode.add("ADD") } else if (op == "-") { pcode.add("SUB") } else if (op == "*") { pcode.add("MULT") } else if (op == "/") { pcode.add("DIV") } else if (op == ">") { pcode.add("GT") } else if (op == "<") { pcode.add("LES") } else if (op == ">=") { pcode.add("GE") } else if (op == "<=") { pcode.add("LE") } else if (op == "==") { pcode.add("EQ") } else if (op == "!=") { pcode.add("NOTEQ") }
        }
        else if (node.node_type == NodeType.IfStat) {
            gen_code(node.children[0]); let cx1 = pcode.size; pcode.add("BRF ?") 
            gen_code(node.children[1]) 
            if (node.children.size > 2) { 
                let cx2 = pcode.size; pcode.add("BR ?"); pcode[cx1] = "BRF ${pcode.size}"; gen_code(node.children[2]); pcode[cx2] = "BR ${pcode.size}"  
            } else { pcode[cx1] = "BRF ${pcode.size}" }
        }
        else if (node.node_type == NodeType.WhileStat) {
            let start = pcode.size; gen_code(node.children[0]); let cx = pcode.size; pcode.add("BRF ?") 
            gen_code(node.children[1]); pcode.add("BR ${start}"); pcode[cx] = "BRF ${pcode.size}" 
        }
        else if (node.node_type == NodeType.ForStat) {
            let loop_var = node.children[0].name
            if (!symbol_table.contains(loop_var)) { symbol_table[loop_var] = next_addr; next_addr++ }
            let var_addr = symbol_table[loop_var]
            pcode.add("LOADI 0"); pcode.add("STO ${var_addr}")
            let start = pcode.size
            pcode.add("LOAD ${var_addr}"); pcode.add("LOADI 10"); pcode.add("LES")
            let cx = pcode.size; pcode.add("BRF ?") 
            gen_code(node.children[2]) 
            pcode.add("LOAD ${var_addr}"); pcode.add("LOADI 1"); pcode.add("ADD"); pcode.add("STO ${var_addr}")
            pcode.add("BR ${start}"); pcode[cx] = "BRF ${pcode.size}" 
        }
    }
}