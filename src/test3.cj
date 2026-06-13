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
            if (line.size == 0 || line.startsWith("---")) { continue }
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

struct SymbolInfo {
    public var name: String; public var kind: Int64; public var addr: Int64; public var args_count: Int64 
    public init(n: String, k: Int64, a: Int64, ac: Int64) { name = n; kind = k; addr = a; args_count = ac }
}

public class SemanticAnalyzer {
    private var sym_stack: ArrayList<HashMap<String, SymbolInfo>> 
    private var pcode: ArrayList<String>         
    private var global_addr: Int64; private var local_offset: Int64; private var current_func_args: Int64

    public init() {
        this.sym_stack = ArrayList<HashMap<String, SymbolInfo>>()
        this.sym_stack.add(HashMap<String, SymbolInfo>()) 
        this.pcode = ArrayList<String>()
        this.global_addr = 0; this.local_offset = 2; this.current_func_args = 0
    }

    private func push_scope() { sym_stack.add(HashMap<String, SymbolInfo>()); local_offset = 2 }
    private func pop_scope() { sym_stack.remove((sym_stack.size - 1)..sym_stack.size) }
    private func add_symbol(name: String, kind: Int64, addr: Int64, args: Int64) { sym_stack[sym_stack.size - 1][name] = SymbolInfo(name, kind, addr, args) }
    private func find_symbol(name: String): Option<SymbolInfo> {
        var i = sym_stack.size - 1
        while (i >= 0) { if (sym_stack[i].contains(name)) { return Some(sym_stack[i][name]) }; i-- }
        return None
    }

    public func run(root: ASTNode, out_path: String) {
        // 全局变量分配
        for (child in root.children) {
            if (child.node_type == NodeType.VarDecl) {
                add_symbol(child.name, 0, global_addr, 0)
                if (child.children.size > 0) { gen_code(child.children[0]) } else { pcode.add("LOADI 0") }
                pcode.add("STOG ${global_addr}"); global_addr++
            } else if (child.node_type == NodeType.ArrayDecl) {
                var size = if (child.children.size>0){Int64.parse(child.children[0].name)}else{10}
                add_symbol(child.name, 3, global_addr, 0)
                for (i in 0..size) { pcode.add("LOADI 0"); pcode.add("STOG ${global_addr+i}") }
                global_addr += size
            } else if (child.node_type == NodeType.Block && child.name == "MultiDecl") {
                for (v in child.children) {
                    if (v.node_type == NodeType.ArrayDecl) {
                        var size = if (v.children.size>0){Int64.parse(v.children[0].name)}else{10}
                        add_symbol(v.name, 3, global_addr, 0)
                        for (i in 0..size) { pcode.add("LOADI 0"); pcode.add("STOG ${global_addr+i}") }
                        global_addr += size
                    } else {
                        add_symbol(v.name, 0, global_addr, 0)
                        if (v.children.size > 0) { gen_code(v.children[0]) } else { pcode.add("LOADI 0") }
                        pcode.add("STOG ${global_addr}"); global_addr++
                    }
                }
            }
        }
        
        for (child in root.children) {
            if (child.node_type == NodeType.FuncDecl) { add_symbol(child.name, 2, -1, child.children.size - 1) }
        }

        for (i in 0..global_addr) {
            pcode.add("LOADI 0")
        }

        let start_main_idx = pcode.size
        pcode.add("CAL ?") 
        pcode.add("STOP")

        var main_addr = 0
        for (child in root.children) {
            if (child.node_type == NodeType.FuncDecl) {
                let func_name = child.name; let f_addr = pcode.size
                if (func_name == "main") { main_addr = f_addr }
                var top_scope = sym_stack[0]; var old_info = top_scope[func_name]
                top_scope[func_name] = SymbolInfo(old_info.name, 2, f_addr, old_info.args_count)
                push_scope(); current_func_args = child.children.size - 1
                for (i in 0..current_func_args) {
                    add_symbol(child.children[i].name, 1, -current_func_args + i, 0)
                }
                let enter_idx = pcode.size
                pcode.add("ENTER ?") 
                gen_code(child.children[current_func_args]) 
                pcode[enter_idx] = "ENTER ${local_offset - 2}" 
                pcode.add("LOADI 0"); pcode.add("RETURN ${current_func_args}") 
                pop_scope()
            }
        }

        if (main_addr == 0) { pcode[start_main_idx] = "STOP" } else { pcode[start_main_idx] = "CAL ${main_addr}" }

        let targetPath = Path(out_path); if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path); for (i in 0..pcode.size) { file.write(("${i}:\t${pcode[i]}\n").toArray()) }; file.close()
    }

    private func gen_code(node: ASTNode): Unit {
        if (node.node_type == NodeType.Block) {
            if (node.name == "MultiDecl") { for(c in node.children){gen_code(c)} } 
            else { for (child in node.children) { gen_code(child) } }
        }
        else if (node.node_type == NodeType.VarDecl) {
            if (sym_stack.size > 1) { 
                add_symbol(node.name, 1, local_offset, 0)
                if (node.children.size > 0) { gen_code(node.children[0]) } else { pcode.add("LOADI 0") }
                pcode.add("STO ${local_offset}"); local_offset++
            }
        }
        else if (node.node_type == NodeType.ArrayDecl) {
            if (sym_stack.size > 1) { 
                var size = if (node.children.size>0){Int64.parse(node.children[0].name)}else{10}
                add_symbol(node.name, 4, local_offset, 0)
                for (i in 0..size) { pcode.add("LOADI 0"); pcode.add("STO ${local_offset+i}") }; local_offset += size 
            }
        }
        else if (node.node_type == NodeType.Assign) {
            gen_code(node.children[1])
            if (let Some(sym) <- find_symbol(node.children[0].name)) {
                if (sym.kind == 0) { pcode.add("STOG ${sym.addr}") } else { pcode.add("STO ${sym.addr}") }
            }
        }
        else if (node.node_type == NodeType.ArrayAssign) {
            // 🚨 修复Bug 2：先算下标(Offset)，再算值(Value)，完美契合 VM 出栈顺序
            gen_code(node.children[0].children[0]) 
            gen_code(node.children[1]) 
            if (let Some(sym) <- find_symbol(node.children[0].name)) {
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
            for (arg in node.children) { gen_code(arg) } 
            if (let Some(sym) <- find_symbol(node.name)) { pcode.add("CAL ${sym.addr}") }
        }
        else if (node.node_type == NodeType.ReturnStat) {
            if (node.children.size > 0) { gen_code(node.children[0]) } else { pcode.add("LOADI 0") }
            pcode.add("RETURN ${current_func_args}")
        }
        else if (node.node_type == NodeType.DoWhileStat) {
            let start = pcode.size; gen_code(node.children[0]); gen_code(node.children[1]); pcode.add("BRT ${start}") 
        }
        else if (node.node_type == NodeType.SwitchStat) {
            gen_code(node.children[0]) 
            let end_jumps = ArrayList<Int64>()
            for (c in node.children) {
                if (c.node_type == NodeType.CaseStat) {
                    pcode.add("COPY"); gen_code(c.children[0]); pcode.add("EQ")
                    let fail_jump = pcode.size; pcode.add("BRF ?")
                    gen_code(c.children[1]) 
                    end_jumps.add(pcode.size); pcode.add("BR ?"); pcode[fail_jump] = "BRF ${pcode.size}"
                } else if (c.node_type == NodeType.Block && c.name == "default") { gen_code(c) }
            }
            pcode.add("POP") 
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
            let target = node.children[0]
            if (target.node_type == NodeType.ArrayAccess) {
                gen_code(target.children[0]) 
                pcode.add("IN")             
                if (let Some(sym) <- find_symbol(target.name)) { if (sym.kind == 3) { pcode.add("STOG_ARR ${sym.addr}") } else { pcode.add("STO_ARR ${sym.addr}") } }
            } else {
                pcode.add("IN") 
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