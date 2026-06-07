package compile

import std.collection.*
import std.fs.*

class NodeType {
    public static let Program = 1
    public static let MainDecl = 2
    public static let Block = 3
    public static let VarDecl = 4
    public static let ArrayDecl = 5     
    public static let Assign = 6
    public static let ArrayAssign = 7   
    public static let IfStat = 8
    public static let ReadStat = 9
    public static let WriteStat = 10
    public static let BinOp = 11
    public static let Identifier = 12
    public static let ArrayAccess = 13  
    public static let Number = 14
    public static let WhileStat = 15   
    public static let ForStat = 16    
    public static let ErrorNode = 0 
    
    public static func toString(node_type: Int64): String {
        if (node_type == 1) { return "Program" }
        if (node_type == 2) { return "MainDecl" }
        if (node_type == 3) { return "Block" }
        if (node_type == 4) { return "VarDecl" }
        if (node_type == 5) { return "ArrayDecl" }
        if (node_type == 6) { return "Assign" }
        if (node_type == 7) { return "ArrayAssign" }
        if (node_type == 8) { return "IfStat" }
        if (node_type == 9) { return "ReadStat" }
        if (node_type == 10) { return "WriteStat" }
        if (node_type == 11) { return "BinOp" }
        if (node_type == 12) { return "Identifier" }
        if (node_type == 13) { return "ArrayAccess" }
        if (node_type == 14) { return "Number" }
        if (node_type == 15) { return "WhileStat" }
        if (node_type == 16) { return "ForStat" }
        return "ErrorNode"
    }
}

class ASTNode {
    public var node_type: Int64 
    public var name: String
    public var line: Int64 // ✨ 新增：节点行号属性
    public var children: ArrayList<ASTNode>

    public init(node_type: Int64, name!: String = "", line!: Int64 = 0) {
        this.node_type = node_type; this.name = name; this.line = line
        this.children = ArrayList<ASTNode>()
    }
}

class parser2 {
    private var pointer: Int64
    public var error_cnt: Int64
    private var output_ast: ArrayList<String> 
    private var token_table: Array<Token>
    private var token_cnt: Int64
    private var out_path: String

    private let num2lexeme: Array<String> = ["标识符", "整数", "界符", "操作符", "关键字"]
   
    public parser2(token_table: Array<Token>, token_cnt: Int64, out_path: String){
        this.pointer = 0; this.error_cnt = 0
        this.output_ast = ArrayList<String>()
        this.token_table = token_table; this.token_cnt = token_cnt; this.out_path = out_path
    }

    private func is_err(node: ASTNode): Bool { return node.node_type == NodeType.ErrorNode }
    private func eat_semi() { if (pointer < token_cnt && token_table[pointer].name == ";") { pointer++ } }
    
    // ✨ 抓取行号工具函数
    private func get_ln(): Int64 {
        if (pointer > 0 && pointer <= token_cnt) { return Int64(token_table[pointer-1].line) }
        return 1
    }

    public func run(){
        var root = parse_program()
        println("  └─ 语法分析结束！共发现 ${error_cnt} 处【纯语法结构】错误。")
        println("  └─ 🚀 正在生成 AST 树...")
        
        output_ast.clear()
        print_ast(root, prefix: "", is_last: true, is_root: true)
        
        let targetPath = Path(out_path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        println("\n--- 纯抽象语法树 (AST) ---")
        for(str in output_ast){ file.write((str+"\n").toArray()) }
        file.close()
    }

    public func print_ast(node: ASTNode, prefix!: String, is_last!: Bool, is_root!: Bool): Unit {
        if (is_err(node)) { return }
        var marker = if (is_root) { "" } else if (is_last) { "└── " } else { "├── " }
        var info = NodeType.toString(node.node_type)
        if (node.name != "") { info += " ['${node.name}']" }
        // ✨ 将行号拼接到节点后面，例如 <15>
        info += " <${node.line}>" 
        
        output_ast.add(prefix + marker + info)
        var child_prefix = prefix + if (is_root) { "" } else if (is_last) { "    " } else { "│   " }
        for (i in 0..node.children.size) { print_ast(node.children[i], prefix: child_prefix, is_last: (i == node.children.size - 1), is_root: false) }
    }

    private func parse_program(assert!: Bool = true): ASTNode {
        var root = ASTNode(NodeType.Program, line: get_ln())
        if(!term("main", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        var main_node = ASTNode(NodeType.MainDecl, name: "main", line: get_ln())
        if(term("(", assert: true) && term(")", assert: true)) {
            main_node.children.add(parse_function_body(assert: true))
        }
        root.children.add(main_node)
        return root
    }

    private func parse_function_body(assert!: Bool = true): ASTNode {
        var block = ASTNode(NodeType.Block, line: get_ln())
        if(!term("{", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        
        while(pointer < token_cnt && token_table[pointer].name != "}") {
            var stmt = parse_statement(assert: false)
            if(!is_err(stmt)) { 
                block.children.add(stmt) 
            } else { 
                error_cnt++
                let ln = token_table[pointer].line
                println("第 ${ln} 行纯语法错：无法识别的语句结构 (在 '${token_table[pointer].name}' 附近)")
                pointer++ 
                while(pointer < token_cnt && token_table[pointer].name != "}" && token_table[pointer].name != ";" && token_table[pointer].name != "var" && token_table[pointer].name != "if" && token_table[pointer].name != "while" && token_table[pointer].name != "for" && token_table[pointer].name != "read" && token_table[pointer].name != "write") {
                    pointer++
                }
                if (pointer < token_cnt && token_table[pointer].name == ";") { pointer++ } 
            }
        }
        term("}", assert: true); return block
    }

    private func parse_statement(assert!: Bool = true): ASTNode {
        var save = pointer
        var node = parse_declaration_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save; node = parse_if_stat(assert: false)
        if(!is_err(node)) { return node }

        pointer = save; node = parse_while_stat(assert: false)
        if(!is_err(node)) { return node }

        pointer = save; node = parse_for_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save; node = parse_read_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save; node = parse_write_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save; return parse_expression_stat(assert: assert)
    }

    private func parse_declaration_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        if(term("var", assert: assert)){
            if(!cat(0, assert: true)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
            var var_name = token_table[pointer-1].name
            let ln = get_ln() // 记住变量声明所在行号
            
            var is_array = false
            var arr_size = ASTNode(NodeType.ErrorNode)
            
            if (term("[", assert: false)) {
                is_array = true; arr_size = parse_expression(assert: true); term("]", assert: true)
            }
            if (term(":", assert: false)) {
                if (pointer < token_cnt && (token_table[pointer].name == "int" || token_table[pointer].name == "float")) { pointer++ }
            }
            
            var var_node = ASTNode(if(is_array){NodeType.ArrayDecl}else{NodeType.VarDecl}, name: var_name, line: ln)
            if (is_array && !is_err(arr_size)) { var_node.children.add(arr_size) }

            if(pointer < token_cnt && token_table[pointer].name == "="){
                pointer++; var expr = parse_expression(assert: true)
                if(!is_err(expr)) { var_node.children.add(expr) }
            }
            eat_semi(); return var_node 
        }
        pointer = save; return ASTNode(NodeType.ErrorNode)
    }

    private func parse_if_stat(assert!: Bool = true): ASTNode {
        if(!term("if", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln()
        term("(", assert: true); var cond = parse_expression(assert: true); term(")", assert: true)
        var if_node = ASTNode(NodeType.IfStat, line: ln)
        if_node.children.add(cond); if_node.children.add(parse_function_body(assert: true))
        if(term("else", assert: false)){ if_node.children.add(parse_function_body(assert: true)) }
        return if_node
    }

    private func parse_while_stat(assert!: Bool = true): ASTNode {
        if(!term("while", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln()
        term("(", assert: true); var cond = parse_expression(assert: true); term(")", assert: true)
        var while_node = ASTNode(NodeType.WhileStat, line: ln)
        while_node.children.add(cond)
        while_node.children.add(parse_function_body(assert: true))
        return while_node
    }

    private func parse_for_stat(assert!: Bool = true): ASTNode {
        if(!term("for", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln()
        term("(", assert: true)
        if(!cat(0, assert: true)) { return ASTNode(NodeType.ErrorNode) } 
        var loop_var = token_table[pointer-1].name
        let var_ln = get_ln()
        term("in", assert: true)
        var expr = parse_expression(assert: true)
        term(")", assert: true)
        
        var for_node = ASTNode(NodeType.ForStat, line: ln)
        for_node.children.add(ASTNode(NodeType.Identifier, name: loop_var, line: var_ln))
        for_node.children.add(expr)
        for_node.children.add(parse_function_body(assert: true))
        return for_node
    }

   private func parse_read_stat(assert!: Bool = true): ASTNode {
        if(!term("read", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln()
        
        // 试探是否有左括号，例如 read(
        let has_paren = term("(", assert: false)
        
        // 匹配变量名 (cat(0) 代表 Identifier)
        if(!cat(0, assert: true)){ return ASTNode(NodeType.ErrorNode) }
        var var_name = token_table[pointer-1].name
        
        var target_node: ASTNode
        
        // ✨ 核心修改：试探是否有中括号，支持数组读取如 read(arr[i])
        if (term("[", assert: false)) {
            // 构建 ArrayAccess 节点，并解析中括号内的表达式作为其子节点
            target_node = ASTNode(NodeType.ArrayAccess, name: var_name, line: get_ln())
            target_node.children.add(parse_expression(assert: true))
            term("]", assert: true)
        } else {
            // 普通变量读取
            target_node = ASTNode(NodeType.Identifier, name: var_name, line: get_ln())
        }
        
        // 如果前面有左括号，这里必须匹配右括号
        if(has_paren) { term(")", assert: true) }
        
        var node = ASTNode(NodeType.ReadStat, line: ln)
        node.children.add(target_node)
        eat_semi() 
        return node 
    }

    private func parse_write_stat(assert!: Bool = true): ASTNode {
        if(!term("write", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let ln = get_ln()
        
        // ✨ 核心修改：显式处理可选的括号，兼容 write(arr[i]) 和 write arr[i]
        let has_paren = term("(", assert: false)
        
        var node = ASTNode(NodeType.WriteStat, line: ln)
        
        // 解析括号内部的表达式 (由于 parse_expression 已经能识别数组访问，这里直接调用即可)
        node.children.add(parse_expression(assert: true))
        
        if(has_paren) { term(")", assert: true) }
        
        eat_semi() 
        return node 
    }

    private func parse_expression_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        if(cat(0, assert: false)){
            var var_name = token_table[pointer-1].name
            let ln = get_ln()
            var is_assign = false
            var is_array_assign = false
            var idx_expr = ASTNode(NodeType.ErrorNode)

            if (term("[", assert: false)) {
                idx_expr = parse_expression(assert: true); term("]", assert: true)
                if (term("=", assert: false)) { is_assign = true; is_array_assign = true } else { pointer = save }
            } else if (term("=", assert: false)) {
                is_assign = true
            } else { pointer = save }

            if (is_assign) {
                var expr = parse_bool_expr(assert: true) 
                var assign_node = ASTNode(if(is_array_assign){NodeType.ArrayAssign}else{NodeType.Assign}, name: "=", line: ln)
                if (is_array_assign) {
                    var arr_acc = ASTNode(NodeType.ArrayAccess, name: var_name, line: ln); arr_acc.children.add(idx_expr)
                    assign_node.children.add(arr_acc)
                } else { assign_node.children.add(ASTNode(NodeType.Identifier, name: var_name, line: ln)) }
                assign_node.children.add(expr); eat_semi(); return assign_node 
            }
        }
        pointer = save; var pure_expr = parse_expression(assert: false)
        if(!is_err(pure_expr)) { eat_semi(); return pure_expr }
        pointer = save; return ASTNode(NodeType.ErrorNode)
    }

    private func parse_expression(assert!: Bool = true): ASTNode { return parse_bool_expr(assert: assert) }

    private func parse_bool_expr(assert!: Bool = true): ASTNode {
        var left = parse_additive_expr(assert: assert) 
        if(is_err(left) || pointer >= token_cnt) { return left }
        var op = token_table[pointer].name
        if(op == ">" || op == ">=" || op == "<" || op == "<=" || op == "==" || op == "!="){
            pointer++; var op_node = ASTNode(NodeType.BinOp, name: op, line: get_ln())
            op_node.children.add(left); op_node.children.add(parse_additive_expr(assert: assert)); return op_node 
        }
        return left
    }

    private func parse_additive_expr(assert!: Bool = true): ASTNode {
        var left = parse_term(assert: assert) 
        if(is_err(left)) { return left }
        while(pointer < token_cnt && (token_table[pointer].name == "+" || token_table[pointer].name == "-")){
            var op_node = ASTNode(NodeType.BinOp, name: token_table[pointer].name, line: get_ln())
            pointer++; op_node.children.add(left); op_node.children.add(parse_term(assert: true)); left = op_node 
        }
        return left
    }

    private func parse_term(assert!: Bool = true): ASTNode {
        var left = parse_factor(assert: assert) 
        if(is_err(left)) { return left }
        while(pointer < token_cnt && (token_table[pointer].name == "*" || token_table[pointer].name == "/")){
            var op_node = ASTNode(NodeType.BinOp, name: token_table[pointer].name, line: get_ln())
            pointer++; op_node.children.add(left); op_node.children.add(parse_factor(assert: true)); left = op_node 
        }
        return left
    }

    private func parse_factor(assert!: Bool = true): ASTNode {
        var save = pointer
        if(term("(", assert: false)){
            var expr = parse_additive_expr(assert: true); term(")", assert: true); return expr
        }
        pointer = save
        if(cat(0, assert: false)){  
            var var_name = token_table[pointer-1].name
            let ln = get_ln()
            if(term("[", assert: false)) {
                var arr_node = ASTNode(NodeType.ArrayAccess, name: var_name, line: ln)
                arr_node.children.add(parse_expression(assert: true)); term("]", assert: true)
                return arr_node
            }
            return ASTNode(NodeType.Identifier, name: var_name, line: ln)
        }
        pointer = save
        if(cat(1, assert: assert)){ return ASTNode(NodeType.Number, name: token_table[pointer-1].name, line: get_ln()) }
        pointer = save; return ASTNode(NodeType.ErrorNode)
    }

    private func term(tok: String, assert!: Bool = true): Bool {
        if (pointer >= token_cnt || token_table[pointer].lexeme == 5) {
            if (assert) { error_cnt++; let ln = if(pointer > 0) { token_table[pointer-1].line } else { UInt64(1) }; println("第 ${ln} 行语法错：缺少 '${tok}'") }
            return false
        }
        if (token_table[pointer].name == tok) { pointer++; return true } 
        else {
            if (assert) { error_cnt++; println("第 ${token_table[pointer].line} 行语法错：期望 '${tok}'，实际得到：'${token_table[pointer].name}'") }
            return false
        }
    }

    private func cat(lexeme: Int64, assert!: Bool = true): Bool {
        if (pointer >= token_cnt || token_table[pointer].lexeme == 5) {
            if (assert) { error_cnt++; let ln = if(pointer > 0) { token_table[pointer-1].line } else { UInt64(1) }; println("第 ${ln} 行类型错：缺少 [${num2lexeme[lexeme]}]") }
            return false
        }
        let current_token = token_table[pointer]
        if (current_token.lexeme == lexeme) {
            pointer++; return true
        } else {
            if (assert) { error_cnt++; println("第 ${current_token.line} 行语法错：期望 [${num2lexeme[lexeme]}]，实际得到 [${num2lexeme[current_token.lexeme]}]") }
            return false
        }
    }
}