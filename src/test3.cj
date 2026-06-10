package compile
import std.collection.*
import std.fs.*
import std.convert.*

public class ASTDeserializer {
    public static func fromString(type_str: String): Int64 {
        let names = ["ErrorNode", "Program", "MainDecl", "Block", "VarDecl", "ArrayDecl", "Assign", "ArrayAssign", "IfStat", "ReadStat", "WriteStat", "BinOp", "Identifier", "ArrayAccess", "Number", "WhileStat", "ForStat", "DoWhileStat", "SwitchStat", "CaseStat", "FuncDecl", "FuncCall", "ReturnStat"]
        for (i in 0..names.size) { if (names[i] == type_str) { return i } }
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
            for (i in 0..runes.size) { if ((runes[i] >= r'A' && runes[i] <= r'Z') || (runes[i] >= r'a' && runes[i] <= r'z')) { first_letter_idx = i; break } }
            if (first_letter_idx == -1) { continue }
            let depth = first_letter_idx / 4 
            var rest = ""; for (i in first_letter_idx..runes.size) { rest += runes[i].toString() }
            
            var node_name = ""; var node_line: Int64 = 0
            let parts = rest.split(" <")
            if (parts.size > 1) { node_line = Int64.parse(parts[1].replace(">", "")) }
            let name_parts = parts[0].split(" ['")
            let type_str = name_parts[0].split(" ")[0] 
            if (name_parts.size > 1) { node_name = name_parts[1].replace("']", "") }

            let node = ASTNode(fromString(type_str), name: node_name, line: node_line)
            if (depth == 0) { root = node; stack.add(node); depths.add(0) } else {
                while (depths.size > 0 && depths[depths.size - 1] >= depth) { stack.remove((stack.size - 1)..stack.size); depths.remove((depths.size - 1)..depths.size) }
                stack[stack.size - 1].children.add(node); stack.add(node); depths.add(depth)
            }
        }
        return root
    }
}

// ✨ 重构：带有作用域信息的符号表
struct SymbolInfo {
    public var name: String
    public var kind: Int64  // 0: 全局, 1: 局部, 2: 函数, 3: 数组(全局), 4: 数组(局部)
    public var addr: Int64  // 绝对地址，或基于 base 的相对偏移量
    public var args_count: Int64 // 用于函数
    public init(n: String, k: Int64, a: Int64, ac: Int64) { name = n; kind = k; addr = a; args_count = ac }
}

public class SemanticAnalyzer {
    // 符号表栈：index 0 是全局，index 1 往后是局部作用域
    private var sym_stack: ArrayList<HashMap<String, SymbolInfo>> 
    private var pcode: ArrayList<String>         
    private var global_addr: Int64
    private var local_offset: Int64
    private var current_func_args: Int64

    public init() {
        this.sym_stack = ArrayList<HashMap<String, SymbolInfo>>()
        this.sym_stack.add(HashMap<String, SymbolInfo>()) // 推入全局作用域
        this.pcode = ArrayList<String>()
        this.global_addr = 0
        this.local_offset = 2 // 局部变量从 base+2 开始 (0是DL, 1是RA)
        this.current_func_args = 0
    }

    private func push_scope() { sym_stack.add(HashMap<String, SymbolInfo>()); local_offset = 2 }
    private func pop_scope() { sym_stack.remove((sym_stack.size - 1)..sym_stack.size) }
    
    private func add_symbol(name: String, kind: Int64, addr: Int64, args: Int64) {
        sym_stack[sym_stack.size - 1][name] = SymbolInfo(name, kind, addr, args)
    }

    private func find_symbol(name: String): Option<SymbolInfo> {
        var i = sym_stack.size - 1
        while (i >= 0) {
            if (sym_stack[i].contains(name)) { return Some(sym_stack[i][name]) }
            i--
        }
        return None
    }

    public func run(root: ASTNode, out_path: String) {
        // ✨ 程序顶层编译逻辑
        // 1. 先扫一遍全局变量，并生成初始分配指令
        for (child in root.children) {
            if (child.node_type == NodeType.VarDecl) {
                add_symbol(child.name, 0, global_addr, 0)
                pcode.add("LOADI " + (if(child.children.size>0){child.children[0].name}else{"0"}))
                pcode.add("STOG ${global_addr}"); global_addr++
            } else if (child.node_type == NodeType.ArrayDecl) {
                var size = if (child.children.size>0){Int64.parse(child.children[0].name)}else{10}
                add_symbol(child.name, 3, global_addr, 0)
                for (i in 0..size) { pcode.add("LOADI 0"); pcode.add("STOG ${global_addr+i}") }
                global_addr += size
            } else if (child.node_type == NodeType.Block && child.name == "MultiDecl") {
                for (v in child.children) {
                    add_symbol(v.name, 0, global_addr, 0); pcode.add("LOADI 0"); pcode.add("STOG ${global_addr}"); global_addr++
                }
            }
        }
        
        // 2. 全局预先登记函数，允许互相调用
        for (child in root.children) {
            if (child.node_type == NodeType.FuncDecl) {
                // addr 先用 -1 占位，等真正生成指令时再填
                add_symbol(child.name, 2, -1, child.children.size - 1)
            }
        }

        // 3. 注入启动 main() 的指令
        let start_main_idx = pcode.size
        pcode.add("CAL ?") // 待回填的 main 入口
        pcode.add("STOP")

        // 4. 深度编译所有函数
        var main_addr = 0
        for (child in root.children) {
            if (child.node_type == NodeType.FuncDecl) {
                let func_name = child.name
                let f_addr = pcode.size
                if (func_name == "main") { main_addr = f_addr }
                
                // 更新全局符号表中的真实入口地址
                var top_scope = sym_stack[0]
                var old_info = top_scope[func_name]
                top_scope[func_name] = SymbolInfo(old_info.name, 2, f_addr, old_info.args_count)

                push_scope()
                current_func_args = child.children.size - 1
                // 绑定参数到当前作用域：参数地址位于 base - args_count 到 base - 1
                for (i in 0..current_func_args) {
                    let p_name = child.children[i].name
                    let p_offset = -current_func_args + i
                    add_symbol(p_name, 1, p_offset, 0)
                }

                let enter_idx = pcode.size
                pcode.add("ENTER ?") // 等待分配了多少局部变量后再回填
                
                gen_code(child.children[current_func_args]) // 生成函数体(Block)
                
                pcode[enter_idx] = "ENTER ${local_offset - 2}" // 减去默认的 2
                pcode.add("LOADI 0") // 默认返回值 0
                pcode.add("RETURN ${current_func_args}") // 强行加兜底返回
                pop_scope()
            }
        }

        // 回填 main
        pcode[start_main_idx] = "CAL ${main_addr}"

        // 写入文件
        let targetPath = Path(out_path); if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        for (i in 0..pcode.size) { file.write(("${i}:\t${pcode[i]}\n").toArray()) }
        file.close()
    }

    private func gen_code(node: ASTNode): Unit {
        if (node.node_type == NodeType.Block) {
            if (node.name == "MultiDecl") { for(c in node.children){gen_code(c)} } 
            else { for (child in node.children) { gen_code(child) } }
        }
        else if (node.node_type == NodeType.VarDecl) {
            if (sym_stack.size > 1) { // 局部变量
                add_symbol(node.name, 1, local_offset, 0)
                if (node.children.size > 0) { gen_code(node.children[0]) } else { pcode.add("LOADI 0") }
                pcode.add("STO ${local_offset}"); local_offset++
            }
        }
        else if (node.node_type == NodeType.ArrayDecl) {
            if (sym_stack.size > 1) { 
                var size = if (node.children.size>0){Int64.parse(node.children[0].name)}else{10}
                add_symbol(node.name, 4, local_offset, 0)
                for (i in 0..size) { pcode.add("LOADI 0"); pcode.add("STO ${local_offset+i}") }
                local_offset += size 
            }
        }
        else if (node.node_type == NodeType.Assign) {
            let var_name = node.children[0].name
            gen_code(node.children[1])
            if (let Some(sym) <- find_symbol(var_name)) {
                if (sym.kind == 0) { pcode.add("STOG ${sym.addr}") } else { pcode.add("STO ${sym.addr}") }
            }
        }
        else if (node.node_type == NodeType.ArrayAssign) {
            let arr_name = node.children[0].name
            gen_code(node.children[1]); gen_code(node.children[0].children[0]) 
            if (let Some(sym) <- find_symbol(arr_name)) {
                if (sym.kind == 3) { pcode.add("STOG_ARR ${sym.addr}") } else { pcode.add("STO_ARR ${sym.addr}") }
            }
        }
        else if (node.node_type == NodeType.Identifier) {
            if (let Some(sym) <- find_symbol(node.name)) {
                if (sym.kind == 0) { pcode.add("LOADG ${sym.addr}") } else { pcode.add("LOAD ${sym.addr}") }
            }
        }
        else if (node.node_type == NodeType.ArrayAccess) {
            gen_code(node.children[0])
            if (let Some(sym) <- find_symbol(node.name)) {
                if (sym.kind == 3) { pcode.add("LOADG_ARR ${sym.addr}") } else { pcode.add("LOAD_ARR ${sym.addr}") }
            }
        }
        else if (node.node_type == NodeType.FuncCall) {
            for (arg in node.children) { gen_code(arg) } // 压入实参
            if (let Some(sym) <- find_symbol(node.name)) { pcode.add("CAL ${sym.addr}") }
        }
        else if (node.node_type == NodeType.ReturnStat) {
            if (node.children.size > 0) { gen_code(node.children[0]) } else { pcode.add("LOADI 0") }
            pcode.add("RETURN ${current_func_args}")
        }
        else if (node.node_type == NodeType.DoWhileStat) {
            let start = pcode.size
            gen_code(node.children[0]); gen_code(node.children[1])
            pcode.add("BRT ${start}") 
        }
        else if (node.node_type == NodeType.SwitchStat) {
            gen_code(node.children[0]) // switch 表达式压栈
            let end_jumps = ArrayList<Int64>()
            for (c in node.children) {
                if (c.node_type == NodeType.CaseStat) {
                    pcode.add("COPY") // 复制栈顶以供后续比对
                    gen_code(c.children[0])
                    pcode.add("EQ")
                    let fail_jump = pcode.size; pcode.add("BRF ?")
                    gen_code(c.children[1]) // 执行 case 块
                    end_jumps.add(pcode.size); pcode.add("BR ?") // 执行完跳出
                    pcode[fail_jump] = "BRF ${pcode.size}"
                } else if (c.node_type == NodeType.Block && c.name == "default") {
                    gen_code(c)
                }
            }
            pcode.add("POP") // 丢弃最初的 switch 表达式结果
            for (idx in end_jumps) { pcode[idx] = "BR ${pcode.size}" }
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
            add_symbol(loop_var, 1, local_offset, 0); let var_addr = local_offset; local_offset++
            pcode.add("LOADI 0"); pcode.add("STO ${var_addr}")
            let start = pcode.size; pcode.add("LOAD ${var_addr}"); pcode.add("LOADI 10"); pcode.add("LES")
            let cx = pcode.size; pcode.add("BRF ?") 
            gen_code(node.children[2]); pcode.add("LOAD ${var_addr}"); pcode.add("LOADI 1"); pcode.add("ADD"); pcode.add("STO ${var_addr}")
            pcode.add("BR ${start}"); pcode[cx] = "BRF ${pcode.size}" 
        }
        else if (node.node_type == NodeType.ReadStat) {
            pcode.add("IN") 
            let target = node.children[0]
            if (target.node_type == NodeType.ArrayAccess) {
                gen_code(target.children[0]) 
                if (let Some(sym) <- find_symbol(target.name)) { if (sym.kind == 3) { pcode.add("STOG_ARR ${sym.addr}") } else { pcode.add("STO_ARR ${sym.addr}") } }
            } else {
                if (let Some(sym) <- find_symbol(target.name)) { if (sym.kind == 0) { pcode.add("STOG ${sym.addr}") } else { pcode.add("STO ${sym.addr}") } }
            }
        }
        else if (node.node_type == NodeType.WriteStat) { gen_code(node.children[0]); pcode.add("OUT") }
        else if (node.node_type == NodeType.Number) { pcode.add("LOADI ${node.name}") }
        else if (node.node_type == NodeType.BinOp) {
            gen_code(node.children[0]); gen_code(node.children[1]); let op = node.name
            if (op == "+") { pcode.add("ADD") } else if (op == "-") { pcode.add("SUB") } else if (op == "*") { pcode.add("MULT") } else if (op == "/") { pcode.add("DIV") } else if (op == ">") { pcode.add("GT") } else if (op == "<") { pcode.add("LES") } else if (op == ">=") { pcode.add("GE") } else if (op == "<=") { pcode.add("LE") } else if (op == "==") { pcode.add("EQ") } else if (op == "!=") { pcode.add("NOTEQ") }
        }
    }
}