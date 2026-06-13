package compile
import std.collection.*
import std.fs.*

public class NodeType {
    public static let Program = 1; public static let Block = 3; public static let VarDecl = 4
    public static let ArrayDecl = 5; public static let Assign = 6; public static let ArrayAssign = 7   
    public static let IfStat = 8; public static let ReadStat = 9; public static let WriteStat = 10
    public static let BinOp = 11; public static let Identifier = 12; public static let ArrayAccess = 13  
    public static let Number = 14; public static let WhileStat = 15; public static let ForStat = 16
    // ✨ 新增节点类型
    public static let DoWhileStat = 17; public static let SwitchStat = 18; public static let CaseStat = 19
    public static let FuncDecl = 20; public static let FuncCall = 21; public static let ReturnStat = 22
    public static let ErrorNode = 0 
    
    public static func toString(t: Int64): String {
        let names = ["ErrorNode", "Program", "MainDecl", "Block", "VarDecl", "ArrayDecl", "Assign", "ArrayAssign", "IfStat", "ReadStat", "WriteStat", "BinOp", "Identifier", "ArrayAccess", "Number", "WhileStat", "ForStat", "DoWhileStat", "SwitchStat", "CaseStat", "FuncDecl", "FuncCall", "ReturnStat"]
        if (t >= 0 && t < names.size) { return names[t] }
        return "Unknown"
    }
}

public class ASTNode {
    public var node_type: Int64 
    public var name: String
    public var line: Int64 
    public var children: ArrayList<ASTNode>
    public init(node_type: Int64, name!: String = "", line!: Int64 = 0) {
        this.node_type = node_type; this.name = name; this.line = line
        this.children = ArrayList<ASTNode>()
    }
}

public class parser2 {
    private var pointer: Int64 = 0
    public var error_cnt: Int64 = 0
    private var output_ast: ArrayList<String> = ArrayList<String>()
    private var token_table: Array<Token>
    private var token_cnt: Int64
    private var out_path: String

    public parser2(token_table: Array<Token>, token_cnt: Int64, out_path: String){
        this.token_table = token_table; this.token_cnt = token_cnt; this.out_path = out_path
    }

    private func is_err(node: ASTNode): Bool { return node.node_type == NodeType.ErrorNode }
    private func eat_semi() { if (pointer < token_cnt && token_table[pointer].name == ";") { pointer++ } }
    private func get_ln(): Int64 { if (pointer > 0 && pointer <= token_cnt) { return Int64(token_table[pointer-1].line) }; return 1 }

    public func run(){
        var root = parse_program()
        output_ast.clear()
        print_ast(root, prefix: "", is_last: true, is_root: true)
        let targetPath = Path(out_path); if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        for(str in output_ast){ file.write((str+"\n").toArray()) }; file.close()
    }

    public func print_ast(node: ASTNode, prefix!: String, is_last!: Bool, is_root!: Bool): Unit {
        if (is_err(node)) { return }
        var marker = if (is_root) { "" } else if (is_last) { "└── " } else { "├── " }
        var info = NodeType.toString(node.node_type)
        if (node.name != "") { info += " ['${node.name}']" }
        info += " <${node.line}>" 
        output_ast.add(prefix + marker + info)
        var child_prefix = prefix + if (is_root) { "" } else if (is_last) { "    " } else { "│   " }
        for (i in 0..node.children.size) { print_ast(node.children[i], prefix: child_prefix, is_last: (i == node.children.size - 1), is_root: false) }
    }

    // ✨ 顶层架构重构：支持全局变量和多函数
    private func parse_program(): ASTNode {
        var root = ASTNode(NodeType.Program, line: 1)
        while (pointer < token_cnt) {
            var decl = parse_func_decl(assert: false)
            if (!is_err(decl)) { root.children.add(decl); continue }
            decl = parse_declaration_stat(assert: false)
            if (!is_err(decl)) { root.children.add(decl); continue }
            break // 遇到无法解析的直接结束
        }
        return root
    }

    // ✨ 解析带参数的函数声明
    private func parse_func_decl(assert!: Bool = true): ASTNode {
        if (!term("func", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln()
        if (!cat(0, assert: true)) { return ASTNode(NodeType.ErrorNode) }
        let func_name = token_table[pointer-1].name
        var func_node = ASTNode(NodeType.FuncDecl, name: func_name, line: ln)
        
        term("(", assert: true)
        while (pointer < token_cnt && token_table[pointer].name != ")") {
            if (cat(0, assert: true)) {
                func_node.children.add(ASTNode(NodeType.Identifier, name: token_table[pointer-1].name, line: get_ln()))
            }
            if (term(",", assert: false)) { continue } else { break }
        }
        term(")", assert: true)
        func_node.children.add(parse_function_body(assert: true))
        return func_node
    }

    private func parse_function_body(assert!: Bool = true): ASTNode {
        var block = ASTNode(NodeType.Block, line: get_ln())
        if(!term("{", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        while(pointer < token_cnt && token_table[pointer].name != "}") {
            var stmt = parse_statement(assert: false)
            if(!is_err(stmt)) { block.children.add(stmt) } else { pointer++ }
        }
        term("}", assert: true); return block
    }

    private func parse_statement(assert!: Bool = true): ASTNode {
        var save = pointer; var node = parse_declaration_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_if_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_while_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_do_while_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_for_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_switch_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_read_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_write_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; node = parse_return_stat(assert: false); if(!is_err(node)) { return node }
        pointer = save; return parse_expression_stat(assert: assert)
    }

    // ✨ 增强的声明：支持 var a=1, b=2
    private func parse_declaration_stat(assert!: Bool = true): ASTNode {
        if(!term("var", assert: assert)){ return ASTNode(NodeType.ErrorNode) }
        var block_node = ASTNode(NodeType.Block, name: "MultiDecl", line: get_ln())
        
        while (pointer < token_cnt) {
            if(!cat(0, assert: true)) { return ASTNode(NodeType.ErrorNode) }
            var var_name = token_table[pointer-1].name
            let ln = get_ln()
            
            var is_array = false; var arr_size = ASTNode(NodeType.ErrorNode)
            if (term("[", assert: false)) { is_array = true; arr_size = parse_expression(assert: true); term("]", assert: true) }
            
            var var_node = ASTNode(if(is_array){NodeType.ArrayDecl}else{NodeType.VarDecl}, name: var_name, line: ln)
            if (is_array && !is_err(arr_size)) { var_node.children.add(arr_size) }
            if(term("=", assert: false)){ var_node.children.add(parse_expression(assert: true)) }
            
            block_node.children.add(var_node)
            if (term(",", assert: false)) { continue } else { break }
        }
        eat_semi(); return block_node 
    }

    private func parse_if_stat(assert!: Bool = true): ASTNode {
        if(!term("if", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln(); term("(", assert: true); var cond = parse_expression(assert: true); term(")", assert: true)
        var if_node = ASTNode(NodeType.IfStat, line: ln); if_node.children.add(cond); if_node.children.add(parse_function_body(assert: true))
        if(term("else", assert: false)){ if_node.children.add(parse_function_body(assert: true)) }
        return if_node
    }

    private func parse_while_stat(assert!: Bool = true): ASTNode {
        if(!term("while", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln(); term("(", assert: true); var cond = parse_expression(assert: true); term(")", assert: true)
        var while_node = ASTNode(NodeType.WhileStat, line: ln); while_node.children.add(cond); while_node.children.add(parse_function_body(assert: true)); return while_node
    }

    // ✨ 解析 Do-While
    private func parse_do_while_stat(assert!: Bool = true): ASTNode {
        if(!term("do", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln(); var do_node = ASTNode(NodeType.DoWhileStat, line: ln)
        do_node.children.add(parse_function_body(assert: true))
        term("while", assert: true); term("(", assert: true)
        do_node.children.add(parse_expression(assert: true)); term(")", assert: true); eat_semi()
        return do_node
    }

    // ✨ 解析 Switch-Case
    private func parse_switch_stat(assert!: Bool = true): ASTNode {
        if(!term("switch", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln(); var sw_node = ASTNode(NodeType.SwitchStat, line: ln)
        term("(", assert: true); sw_node.children.add(parse_expression(assert: true)); term(")", assert: true)
        term("{", assert: true)
        while (pointer < token_cnt && token_table[pointer].name != "}") {
            if (term("case", assert: false)) {
                var c_node = ASTNode(NodeType.CaseStat, line: get_ln())
                c_node.children.add(parse_expression(assert: true)); term(":", assert: true)
                var blk = ASTNode(NodeType.Block, line: get_ln())
                while (pointer < token_cnt && token_table[pointer].name != "case" && token_table[pointer].name != "default" && token_table[pointer].name != "}") { blk.children.add(parse_statement(assert: true)) }
                c_node.children.add(blk); sw_node.children.add(c_node)
            } else if (term("default", assert: false)) {
                term(":", assert: true); var def_node = ASTNode(NodeType.Block, name: "default", line: get_ln())
                while (pointer < token_cnt && token_table[pointer].name != "}") { def_node.children.add(parse_statement(assert: true)) }
                sw_node.children.add(def_node)
            } else { pointer++ }
        }
        term("}", assert: true); return sw_node
    }

    private func parse_for_stat(assert!: Bool = true): ASTNode {
        if(!term("for", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln(); term("(", assert: true); cat(0, assert: true); var loop_var = token_table[pointer-1].name
        let var_ln = get_ln(); term("in", assert: true); var expr = parse_expression(assert: true); term(")", assert: true)
        var for_node = ASTNode(NodeType.ForStat, line: ln)
        for_node.children.add(ASTNode(NodeType.Identifier, name: loop_var, line: var_ln))
        for_node.children.add(expr); for_node.children.add(parse_function_body(assert: true)); return for_node
    }

    private func parse_return_stat(assert!: Bool = true): ASTNode {
        if(!term("return", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        var ret_node = ASTNode(NodeType.ReturnStat, line: get_ln())
        if (pointer < token_cnt && token_table[pointer].name != ";") { ret_node.children.add(parse_expression(assert: false)) }
        eat_semi(); return ret_node
    }

    private func parse_read_stat(assert!: Bool = true): ASTNode {
        if(!term("read", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln(); let has_paren = term("(", assert: false); cat(0, assert: true)
        var target_node = ASTNode(if(term("[", assert: false)){NodeType.ArrayAccess}else{NodeType.Identifier}, name: token_table[pointer-1].name, line: get_ln())
        if (target_node.node_type == NodeType.ArrayAccess) { target_node.children.add(parse_expression(assert: true)); term("]", assert: true) }
        if(has_paren) { term(")", assert: true) }; var node = ASTNode(NodeType.ReadStat, line: ln); node.children.add(target_node); eat_semi(); return node 
    }

    private func parse_write_stat(assert!: Bool = true): ASTNode {
        if(!term("write", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln(); let has_paren = term("(", assert: false)
        var node = ASTNode(NodeType.WriteStat, line: ln); node.children.add(parse_expression(assert: true))
        if(has_paren) { term(")", assert: true) }; eat_semi(); return node 
    }

    private func parse_expression_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        if(cat(0, assert: false)){
            var var_name = token_table[pointer-1].name; let ln = get_ln()
            var is_assign = false; var is_array_assign = false; var idx_expr = ASTNode(NodeType.ErrorNode)
            if (term("[", assert: false)) {
                idx_expr = parse_expression(assert: true); term("]", assert: true)
                if (term("=", assert: false)) { is_assign = true; is_array_assign = true } else { pointer = save }
            } else if (term("=", assert: false)) { is_assign = true } else { pointer = save }

            if (is_assign) {
                var expr = parse_bool_expr(assert: true) 
                var assign_node = ASTNode(if(is_array_assign){NodeType.ArrayAssign}else{NodeType.Assign}, name: "=", line: ln)
                if (is_array_assign) {
                    var arr_acc = ASTNode(NodeType.ArrayAccess, name: var_name, line: ln); arr_acc.children.add(idx_expr); assign_node.children.add(arr_acc)
                } else { assign_node.children.add(ASTNode(NodeType.Identifier, name: var_name, line: ln)) }
                assign_node.children.add(expr); eat_semi(); return assign_node 
            }
        }
        pointer = save; var pure_expr = parse_expression(assert: false); if(!is_err(pure_expr)) { eat_semi(); return pure_expr }
        pointer = save; return ASTNode(NodeType.ErrorNode)
    }

    private func parse_expression(assert!: Bool = true): ASTNode { return parse_bool_expr(assert: assert) }
    private func parse_bool_expr(assert!: Bool = true): ASTNode {
        var left = parse_additive_expr(assert: assert); if(is_err(left) || pointer >= token_cnt) { return left }
        var op = token_table[pointer].name
        if(op == ">" || op == ">=" || op == "<" || op == "<=" || op == "==" || op == "!="){
            pointer++; var op_node = ASTNode(NodeType.BinOp, name: op, line: get_ln())
            op_node.children.add(left); op_node.children.add(parse_additive_expr(assert: assert)); return op_node 
        }
        return left
    }
    private func parse_additive_expr(assert!: Bool = true): ASTNode {
        var left = parse_term(assert: assert); if(is_err(left)) { return left }
        while(pointer < token_cnt && (token_table[pointer].name == "+" || token_table[pointer].name == "-")){
            var op_node = ASTNode(NodeType.BinOp, name: token_table[pointer].name, line: get_ln())
            pointer++; op_node.children.add(left); op_node.children.add(parse_term(assert: true)); left = op_node 
        }
        return left
    }
    private func parse_term(assert!: Bool = true): ASTNode {
        var left = parse_factor(assert: assert); if(is_err(left)) { return left }
        while(pointer < token_cnt && (token_table[pointer].name == "*" || token_table[pointer].name == "/")){
            var op_node = ASTNode(NodeType.BinOp, name: token_table[pointer].name, line: get_ln())
            pointer++; op_node.children.add(left); op_node.children.add(parse_factor(assert: true)); left = op_node 
        }
        return left
    }

    private func parse_factor(assert!: Bool = true): ASTNode {
        var save = pointer
        if(term("(", assert: false)){ var expr = parse_additive_expr(assert: true); term(")", assert: true); return expr }
        pointer = save
        if(cat(0, assert: false)){  
            var var_name = token_table[pointer-1].name; let ln = get_ln()
            // ✨ 解析函数调用: ID ( args )
            if (term("(", assert: false)) {
                var call_node = ASTNode(NodeType.FuncCall, name: var_name, line: ln)
                while (pointer < token_cnt && token_table[pointer].name != ")") {
                    call_node.children.add(parse_expression(assert: true))
                    if (!term(",", assert: false)) { break }
                }
                term(")", assert: true); return call_node
            }
            if(term("[", assert: false)) {
                var arr_node = ASTNode(NodeType.ArrayAccess, name: var_name, line: ln)
                arr_node.children.add(parse_expression(assert: true)); term("]", assert: true); return arr_node
            }
            return ASTNode(NodeType.Identifier, name: var_name, line: ln)
        }
        pointer = save
        if(cat(1, assert: assert)){ return ASTNode(NodeType.Number, name: token_table[pointer-1].name, line: get_ln()) }
        pointer = save; return ASTNode(NodeType.ErrorNode)
    }

    private func term(tok: String, assert!: Bool = true): Bool {
        if (pointer >= token_cnt || token_table[pointer].lexeme == 5) { return false }
        if (token_table[pointer].name == tok) { pointer++; return true } else { return false }
    }
    private func cat(lexeme: Int64, assert!: Bool = true): Bool {
        if (pointer >= token_cnt || token_table[pointer].lexeme == 5) { return false }
        if (token_table[pointer].lexeme == lexeme) { pointer++; return true } else { return false }
    }
}