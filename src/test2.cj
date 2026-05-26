package compile

import std.collection.*
import std.fs.*

// ==========================================
// 1. 抽象语法树 (AST) 节点类型定义
// ==========================================
class NodeType {
    public static let Program = 1
    public static let MainDecl = 2
    public static let FuncDecl = 3
    public static let Block = 4
    public static let VarDecl = 5
    public static let LetDecl = 6
    public static let Assign = 7
    public static let IfStat = 8
    public static let WhileStat = 9
    public static let ForStat = 10
    public static let BreakStat = 11
    public static let ContinueStat = 12
    public static let ReturnStat = 13
    public static let ReadStat = 14
    public static let WriteStat = 15
    public static let MatchStat = 16
    public static let BinOp = 17
    public static let Identifier = 18
    public static let Number = 19
    public static let ErrorNode = 0 
    
    public static func toString(node_type: Int64): String {
        if (node_type == 1) { return "Program (程序入口)" }
        if (node_type == 2) { return "MainDecl (主函数)" }
        if (node_type == 3) { return "FuncDecl (函数定义)" }
        if (node_type == 4) { return "Block (代码块)" }
        if (node_type == 5) { return "VarDecl (变量声明)" }
        if (node_type == 6) { return "LetDecl (常量声明)" }
        if (node_type == 7) { return "Assign (赋值)" }
        if (node_type == 8) { return "IfStat (条件分支)" }
        if (node_type == 9) { return "WhileStat (While循环)" }
        if (node_type == 10) { return "ForStat (For循环)" }
        if (node_type == 11) { return "BreakStat (Break跳出)" }
        if (node_type == 12) { return "ContinueStat (Continue)" }
        if (node_type == 13) { return "ReturnStat (返回)" }
        if (node_type == 14) { return "ReadStat (读取)" }
        if (node_type == 15) { return "WriteStat (输出)" }
        if (node_type == 16) { return "MatchStat (模式匹配)" }
        if (node_type == 17) { return "BinOp (二元运算)" }
        if (node_type == 18) { return "Identifier (标识符)" }
        if (node_type == 19) { return "Number (数字)" }
        return "ErrorNode (错误/回溯节点)"
    }
}

// ==========================================
// 2. 抽象语法树节点类
// ==========================================
class ASTNode {
    public var node_type: Int64 
    public var name: String
    public var children: ArrayList<ASTNode>

    public init(node_type: Int64, name!: String = "") {
        this.node_type = node_type
        this.name = name
        this.children = ArrayList<ASTNode>()
    }
}

// ==========================================
// 3. 语法分析器主体 (Parser)
// ==========================================
class parser2 {
    private var pointer: Int64
    public var error_cnt: Int64
    private var symbol_table: Map<String, Int64>  
    private var output_code: ArrayList<String> 
    private var next_var_addr: Int64               
    private var token_table: Array<Token>
    private var token_cnt: Int64
    private var out_path: String

    private let num2lexeme: Array<String> = ["标识符(ID)", "整数(NUM)", "界符(SYMBOL)", "操作符(OP)", "关键字(KEYWORD)"]
   
    public parser2(token_table: Array<Token>, token_cnt: Int64, out_path: String){
        this.pointer = 0
        this.error_cnt = 0
        this.symbol_table = HashMap<String, Int64>()
        this.output_code = ArrayList<String>()
        this.next_var_addr = 0
        this.token_table = token_table
        this.token_cnt = token_cnt
        this.out_path = out_path
    }

    private func is_err(node: ASTNode): Bool {
        return node.node_type == NodeType.ErrorNode
    }

    private func eat_semi() {
        if (pointer < token_cnt && token_table[pointer].name == ";") {
            pointer++
        }
    }

    public func run(){
        var root = parse_program()
        if(!is_err(root) && error_cnt == 0){
            println("  └─ ✓ 语法与语义分析成功！开始构建抽象语法树(AST)...")
            output_code.clear()
            // ✨ 核心修正：初始调用加入了 is_root: true 标识
            print_ast(root, prefix: "", is_last: true, is_root: true)
            write2file()
            println("\n--- 抽象语法树 (Abstract Syntax Tree) ---")
            for(line in output_code){ println(line) }
        }
        else{
            println("  └─ ❌ 语法与语义分析失败！累计发现 ${error_cnt} 处错误。")
        }
    }

    // ✨ 核心修正：引入了 is_root 参数，彻底解决了无限空缩进导致的树枝丢失 Bug
    public func print_ast(node: ASTNode, prefix!: String, is_last!: Bool, is_root!: Bool): Unit {
        if (is_err(node)) { return }
        
        var marker = if (is_root) { "" } else if (is_last) { "└── " } else { "├── " }
        var info = NodeType.toString(node.node_type)
        if (node.name != "") { info += " ['${node.name}']" }
        
        output_code.add(prefix + marker + info)
        
        var child_prefix = prefix + if (is_root) { "" } else if (is_last) { "    " } else { "│   " }
        for (i in 0..node.children.size) {
            print_ast(node.children[i], prefix: child_prefix, is_last: (i == node.children.size - 1), is_root: false)
        }
    }

    public func write2file(){
        let targetPath = Path(out_path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        for(str in output_code){
            file.write((str+"\n").toArray())
        }
        file.close()
        println("  └─ 抽象语法树已成功写入文件：${out_path}")
    }

    private func parse_program(assert!: Bool = true): ASTNode {
        var root = ASTNode(NodeType.Program)
        while(pointer < token_cnt && token_table[pointer].name == "func") {
            var f = parse_fun_declaration(assert: assert)
            if(!is_err(f)) { root.children.add(f) }
        }
        var m = parse_main_declaration(assert: assert)
        if(!is_err(m)) { root.children.add(m) }
        return root
    }

    private func parse_fun_declaration(assert!: Bool = true): ASTNode {
        if(!term("func", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        if(!cat(0, assert: true, check_id: false)) { return ASTNode(NodeType.ErrorNode) } 
        var func_node = ASTNode(NodeType.FuncDecl, name: token_table[pointer-1].name)
        
        if(!term("(", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        while(pointer < token_cnt && token_table[pointer].name != ")") {
            if(!cat(0, assert: true, check_id: false)) { return ASTNode(NodeType.ErrorNode) }
            func_node.children.add(ASTNode(NodeType.Identifier, name: token_table[pointer-1].name)) 
            if(!term(":", assert: true)) { return ASTNode(NodeType.ErrorNode) }
            if(!term("int", assert: true)) { return ASTNode(NodeType.ErrorNode) }
            if(pointer < token_cnt && token_table[pointer].name == ",") { pointer++ }
        }
        if(!term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        if(pointer < token_cnt && token_table[pointer].name == ":") {
            pointer++
            if(!term("int", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        }
        
        var body = parse_function_body(assert: true)
        func_node.children.add(body)
        return func_node
    }

    private func parse_main_declaration(assert!: Bool = true): ASTNode {
        if(!term("main", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        var main_node = ASTNode(NodeType.MainDecl, name: "main")
        
        if(!term("(", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        while(pointer < token_cnt && token_table[pointer].name != ")") {
            if(!cat(0, assert: true, check_id: false)) { return ASTNode(NodeType.ErrorNode) }
            if(!term(":", assert: true)) { return ASTNode(NodeType.ErrorNode) }
            if(!term("int", assert: true)) { return ASTNode(NodeType.ErrorNode) }
            if(pointer < token_cnt && token_table[pointer].name == ",") { pointer++ }
        }
        if(!term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        if(pointer < token_cnt && token_table[pointer].name == ":") {
            pointer++
            if(!term("int", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        }
        
        var body = parse_function_body(assert: true)
        main_node.children.add(body)
        return main_node
    }

    private func parse_function_body(assert!: Bool = true): ASTNode {
        var block = ASTNode(NodeType.Block)
        if(!term("{", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        
        while(pointer < token_cnt && token_table[pointer].name != "}") {
            var stmt = parse_statement(assert: false)
            if(!is_err(stmt)) {
                block.children.add(stmt)
            } else {
                break 
            }
        }
        
        if(!term("}", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        return block
    }

    private func parse_statement(assert!: Bool = true): ASTNode {
        var save = pointer
        
        var node = parse_declaration_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_if_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_while_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_for_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_read_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_write_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_compound_stat(assert: false) 
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_jump_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_match_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        node = parse_nested_func_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save
        return parse_expression_stat(assert: assert)
    }

    private func parse_declaration_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        
        if(term("var", assert: assert)){
            if(!cat(0, assert: true, check_id: false)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
            var var_name = token_table[pointer-1].name
            
            if(symbol_table.contains(var_name)){
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 重复声明！")
                error_cnt++
            } else {
                symbol_table[var_name] = next_var_addr
                next_var_addr++
            }
            
            var var_node = ASTNode(NodeType.VarDecl, name: var_name)
            
            if(pointer < token_cnt && token_table[pointer].name == "[") {
                pointer++ 
                if(cat(1, assert: true)) { 
                    var_node.children.add(ASTNode(NodeType.Number, name: token_table[pointer-1].name))
                } else { pointer = save; return ASTNode(NodeType.ErrorNode) }
                if(!term("]", assert: true)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
                eat_semi() 
                return var_node 
            }
            
            if(pointer < token_cnt && token_table[pointer].name == ":") {
                pointer++
                if(!term("int", assert: true)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
            }
            
            if(pointer < token_cnt && token_table[pointer].name == "="){
                pointer++
                var expr = parse_expression(assert: true)
                if(is_err(expr)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
                var_node.children.add(expr)
            }
            eat_semi() 
            return var_node 
        }
        
        pointer = save
        if(term("let", assert: assert)){
            if(!cat(0, assert: true, check_id: false)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
            var var_name = token_table[pointer-1].name
            
            if(symbol_table.contains(var_name)){
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 重复声明！")
                error_cnt++
            } else {
                symbol_table[var_name] = next_var_addr
                next_var_addr++
            }
            
            var let_node = ASTNode(NodeType.LetDecl, name: var_name)
            
            if(!term("=", assert: true)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
            var expr = parse_expression(assert: true)
            if(is_err(expr)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
            let_node.children.add(expr)
            eat_semi() 
            return let_node 
        }
        
        pointer = save
        return ASTNode(NodeType.ErrorNode)
    }

    private func parse_if_stat(assert!: Bool = true): ASTNode {
        if(!term("if", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        if(!term("(", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        var cond = parse_expression(assert: true)
        if(!term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }

        var then_block = parse_statement(assert: true)
        
        var if_node = ASTNode(NodeType.IfStat)
        if_node.children.add(cond)
        if_node.children.add(then_block)

        if(term("else", assert: false)){
            var else_block = parse_statement(assert: true)
            if_node.children.add(else_block)
        }
        return if_node
    }

    private func parse_while_stat(assert!: Bool = true): ASTNode {
        if(!term("while", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        if(!term("(", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        var cond = parse_expression(assert: true)
        if(!term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        var body = parse_statement(assert: true)
        
        var node = ASTNode(NodeType.WhileStat)
        node.children.add(cond)
        node.children.add(body)
        return node
    }

    private func parse_for_stat(assert!: Bool = true): ASTNode {
        if(!term("for", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        if(!term("(", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        if(!cat(0, assert: true, check_id: false)) { return ASTNode(NodeType.ErrorNode) } 
        var loop_var = token_table[pointer-1].name
        
        if(!symbol_table.contains(loop_var)) {
            symbol_table[loop_var] = next_var_addr
            next_var_addr++
        }
        
        if(!term("in", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        var expr = parse_expression(assert: true)
        if(!term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        
        var body = parse_statement(assert: true)
        
        var node = ASTNode(NodeType.ForStat)
        node.children.add(ASTNode(NodeType.Identifier, name: loop_var))
        node.children.add(expr)
        node.children.add(body)
        return node
    }

    private func parse_jump_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        if(term("break", assert: assert)) { 
            eat_semi() 
            return ASTNode(NodeType.BreakStat) 
        }
        
        pointer = save
        if(term("continue", assert: assert)) { 
            eat_semi() 
            return ASTNode(NodeType.ContinueStat) 
        }
        
        pointer = save
        if(term("return", assert: assert)) {
            var node = ASTNode(NodeType.ReturnStat)
            var expr = parse_expression(assert: false)
            if(!is_err(expr)) { node.children.add(expr) }
            eat_semi()
            return node 
        }
        pointer = save
        return ASTNode(NodeType.ErrorNode)
    }

    private func parse_match_stat(assert!: Bool = true): ASTNode {
        if(!term("match", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        var match_node = ASTNode(NodeType.MatchStat)
        
        if(!term("(", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        var cond = parse_expression(assert: true)
        match_node.children.add(cond)
        if(!term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        
        if(!term("{", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        while(pointer < token_cnt && token_table[pointer].name == "case") {
            pointer++ 
            var case_val = parse_expression(assert: true)
            if(!term(":", assert: true)) { return ASTNode(NodeType.ErrorNode) }
            var case_stmt = parse_statement(assert: true)
            
            match_node.children.add(case_val)
            match_node.children.add(case_stmt)
        }
        if(!term("}", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        return match_node
    }

    private func parse_nested_func_stat(assert!: Bool = true): ASTNode {
        if(!term("func", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        pointer-- 
        return parse_fun_declaration(assert: true)
    }

    private func parse_read_stat(assert!: Bool = true): ASTNode {
        if(!term("read", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        
        let has_paren = term("(", assert: false)
        if(!cat(0, assert: true, check_id: false)){ return ASTNode(NodeType.ErrorNode) }
        
        var var_name = token_table[pointer-1].name
        if(!symbol_table.contains(var_name)){
            error_cnt++
            println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 使用前未声明！")
        } 
        
        if(has_paren && !term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }
        
        var node = ASTNode(NodeType.ReadStat)
        node.children.add(ASTNode(NodeType.Identifier, name: var_name))
        eat_semi() 
        return node 
    }

    private func parse_write_stat(assert!: Bool = true): ASTNode {
        if(!term("write", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        var expr = parse_expression(assert: true)
        var node = ASTNode(NodeType.WriteStat)
        node.children.add(expr)
        eat_semi() 
        return node 
    }

    private func parse_compound_stat(assert!: Bool = true): ASTNode {
        return parse_function_body(assert: assert)
    }

    private func parse_expression_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        if(pointer + 1 < token_cnt && token_table[pointer + 1].name == "="){
            if(!cat(0, assert: assert, check_id: false)) {return ASTNode(NodeType.ErrorNode)}
            var var_name = token_table[pointer-1].name
            if(!term("=", assert: true)) {return ASTNode(NodeType.ErrorNode)}
            
            var expr = parse_bool_expr(assert: true) 
            if(is_err(expr)) { return ASTNode(NodeType.ErrorNode) }
            
            if(!symbol_table.contains(var_name)){
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 赋值前未声明！")
            }
            
            var assign_node = ASTNode(NodeType.Assign, name: "=")
            assign_node.children.add(ASTNode(NodeType.Identifier, name: var_name))
            assign_node.children.add(expr)
            eat_semi() 
            return assign_node 
        }
        pointer = save
        var pure_expr = parse_expression(assert: false)
        if(!is_err(pure_expr)) {
            eat_semi() 
            return pure_expr 
        }
        pointer = save
        return ASTNode(NodeType.ErrorNode)
    }

    private func parse_expression(assert!: Bool = true): ASTNode { 
        return parse_bool_expr(assert: assert) 
    }

    private func parse_bool_expr(assert!: Bool = true): ASTNode {
        var left = parse_additive_expr(assert: assert) 
        if(is_err(left)) { return left }
        
        var save = pointer
        if(pointer < token_cnt){
            var op = token_table[pointer].name
            if(op == ">" || op == ">=" || op == "<" || op == "<=" || op == "==" || op == "!="){
                pointer++
                var right = parse_additive_expr(assert: assert) 
                
                var op_node = ASTNode(NodeType.BinOp, name: op)
                op_node.children.add(left)
                op_node.children.add(right)
                return op_node 
            }
        }
        pointer = save
        return left
    }

    private func parse_additive_expr(assert!: Bool = true): ASTNode {
        var left = parse_term(assert: assert) 
        if(is_err(left)) { return left }
        
        while(true){
            if(term("+", assert: false)){
                var right = parse_term(assert: true) 
                var op_node = ASTNode(NodeType.BinOp, name: "+")
                op_node.children.add(left)
                op_node.children.add(right)
                left = op_node 
            } else if(term("-", assert: false)){
                var right = parse_term(assert: true) 
                var op_node = ASTNode(NodeType.BinOp, name: "-")
                op_node.children.add(left)
                op_node.children.add(right)
                left = op_node 
            } else {
                break
            }
        }
        return left
    }

    private func parse_term(assert!: Bool = true): ASTNode {
        var left = parse_factor(assert: assert) 
        if(is_err(left)) { return left }
        
        while(true){
            if(term("*", assert: false)){
                var right = parse_factor(assert: true) 
                var op_node = ASTNode(NodeType.BinOp, name: "*")
                op_node.children.add(left)
                op_node.children.add(right)
                left = op_node 
            } else if(term("/", assert: false)){
                var right = parse_factor(assert: true) 
                var op_node = ASTNode(NodeType.BinOp, name: "/")
                op_node.children.add(left)
                op_node.children.add(right)
                left = op_node 
            } else {
                break
            }
        }
        return left
    }

    private func parse_factor(assert!: Bool = true): ASTNode {
        var save = pointer
        if(term("(", assert: false)){
            var expr = parse_additive_expr(assert: true)
            if(!term(")", assert: true)) { return ASTNode(NodeType.ErrorNode) }
            return expr
        }
        pointer = save
        if(cat(0, assert: false, check_id: false)){  
            var var_name = token_table[pointer-1].name
            if(!symbol_table.contains(var_name)){
                if(assert) { 
                    error_cnt++
                    println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 在表达式中未声明先引用！")
                }
                return ASTNode(NodeType.Number, name: "0") 
            }
            return ASTNode(NodeType.Identifier, name: var_name)
        }
        pointer = save
        if(cat(1, assert: assert)){  
            var val_str = token_table[pointer-1].name
            return ASTNode(NodeType.Number, name: val_str)
        }
        pointer = save
        return ASTNode(NodeType.ErrorNode)
    }

    private func term(tok: String, assert!: Bool = true): Bool {
        if (pointer >= token_cnt || token_table[pointer].lexeme == 5) {
            if (assert) {
                error_cnt++
                let line_num = if(pointer > 0) { token_table[pointer-1].line } else { UInt64(1) }
                println("第 ${line_num} 行语法错：期望得到终结符 '${tok}'，实际得到：'文件流结束(EOF)'")
            }
            return false
        }
        
        if (token_table[pointer].name == tok) {
            pointer++ 
            return true
        } else {
            if (assert) {
                error_cnt++
                println("第 ${token_table[pointer].line} 行语法错：期望得到终结符 '${tok}'，实际得到：'${token_table[pointer].name}'")
            }
            return false
        }
    }

    private func cat(lexeme: Int64, assert!: Bool = true, check_id!: Bool = true): Bool {
        if (pointer >= token_cnt || token_table[pointer].lexeme == 5) {
            if (assert) {
                error_cnt++
                let line_num = if(pointer > 0) { token_table[pointer-1].line } else { UInt64(1) }
                println("第 ${line_num} 行类型错：期望读取 [${num2lexeme[lexeme]}] 类别，实际得到：'文件流结束(EOF)'")
            }
            return false
        }

        let current_token = token_table[pointer]
        if (current_token.lexeme == lexeme && (lexeme != 0 || !check_id || symbol_table.contains(current_token.name))) {
            pointer++ 
            return true
        } else {
            if (assert) {
                error_cnt++
                if (current_token.lexeme != lexeme) {
                    println("第 ${current_token.line} 行类型错：期望读取 [${num2lexeme[lexeme]}] 类别，实际得到：[${num2lexeme[current_token.lexeme]}]")
                }
                if (lexeme == 0 && check_id && !symbol_table.contains(current_token.name)) {
                    println("第 ${current_token.line} 行错误：变量 '${current_token.name}' 在表达式中未声明先引用！")
                }
            }
            return false
        }
    }
}