package compile

import std.collection.*
import std.fs.*

// ==========================================
// 1. 抽象语法树节点字典
// ==========================================
class NodeType {
    public static let Program = 1
    public static let MainDecl = 2
    public static let Block = 3
    public static let VarDecl = 4
    public static let ArrayDecl = 5     // 数组声明
    public static let Assign = 6
    public static let ArrayAssign = 7   // 数组赋值
    public static let IfStat = 8
    public static let ReadStat = 9
    public static let WriteStat = 10
    public static let BinOp = 11
    public static let Identifier = 12
    public static let ArrayAccess = 13  // 数组访问
    public static let Number = 14
    public static let ErrorNode = 0 
    
    public static func toString(node_type: Int64): String {
        if (node_type == 1) { return "Program (程序)" }
        if (node_type == 2) { return "MainDecl (主函数)" }
        if (node_type == 3) { return "Block (代码块)" }
        if (node_type == 4) { return "VarDecl (变量声明)" }
        if (node_type == 5) { return "ArrayDecl (数组声明)" }
        if (node_type == 6) { return "Assign (赋值)" }
        if (node_type == 7) { return "ArrayAssign (数组赋值)" }
        if (node_type == 8) { return "IfStat (条件)" }
        if (node_type == 9) { return "ReadStat (读取)" }
        if (node_type == 10) { return "WriteStat (输出)" }
        if (node_type == 11) { return "BinOp (二元运算)" }
        if (node_type == 12) { return "Identifier (变量)" }
        if (node_type == 13) { return "ArrayAccess (数组元素)" }
        if (node_type == 14) { return "Number (数字)" }
        return "ErrorNode (错误节点)"
    }
}

class ASTNode {
    public var node_type: Int64 
    public var name: String
    public var children: ArrayList<ASTNode>

    public init(node_type: Int64, name!: String = "") {
        this.node_type = node_type; this.name = name
        this.children = ArrayList<ASTNode>()
    }
}

// ==========================================
// 2. 语法与语义分析器
// ==========================================
class parser2 {
    private var pointer: Int64
    public var error_cnt: Int64
    private var symbol_table: Map<String, Int64>  // 🧠 开启符号表：用于查重、查未声明
    private var output_ast: ArrayList<String> 
    private var next_var_addr: Int64               
    private var token_table: Array<Token>
    private var token_cnt: Int64
    private var out_path: String

    private let num2lexeme: Array<String> = ["标识符", "整数", "界符", "操作符", "关键字"]
   
    public parser2(token_table: Array<Token>, token_cnt: Int64, out_path: String){
        this.pointer = 0; this.error_cnt = 0; this.next_var_addr = 0
        this.symbol_table = HashMap<String, Int64>()
        this.output_ast = ArrayList<String>()
        this.token_table = token_table; this.token_cnt = token_cnt; this.out_path = out_path
    }

    private func is_err(node: ASTNode): Bool { return node.node_type == NodeType.ErrorNode }
    private func eat_semi() { if (pointer < token_cnt && token_table[pointer].name == ";") { pointer++ } }

    public func run(){
        var root = parse_program()
        println("  └─ 分析结束！共一次性发现 ${error_cnt} 处错误。")
        println("  └─ 🚀 正在生成 AST 树 (带伤建树模式)...")
        
        output_ast.clear()
        print_ast(root, prefix: "", is_last: true, is_root: true)
        
        let targetPath = Path(out_path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        println("\n--- 抽象语法树 (AST) ---")
        for(str in output_ast){ println(str); file.write((str+"\n").toArray()) }
        file.close()
    }

    public func print_ast(node: ASTNode, prefix!: String, is_last!: Bool, is_root!: Bool): Unit {
        if (is_err(node)) { return }
        var marker = if (is_root) { "" } else if (is_last) { "└── " } else { "├── " }
        var info = NodeType.toString(node.node_type)
        if (node.name != "") { info += " ['${node.name}']" }
        output_ast.add(prefix + marker + info)
        var child_prefix = prefix + if (is_root) { "" } else if (is_last) { "    " } else { "│   " }
        for (i in 0..node.children.size) { print_ast(node.children[i], prefix: child_prefix, is_last: (i == node.children.size - 1), is_root: false) }
    }

    // ==========================================
    // 3. 核心：带恐慌模式的代码块解析
    // ==========================================
    private func parse_program(assert!: Bool = true): ASTNode {
        var root = ASTNode(NodeType.Program)
        if(!term("main", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        var main_node = ASTNode(NodeType.MainDecl, name: "main")
        if(term("(", assert: true) && term(")", assert: true)) {
            main_node.children.add(parse_function_body(assert: true))
        }
        root.children.add(main_node)
        return root
    }

    private func parse_function_body(assert!: Bool = true): ASTNode {
        var block = ASTNode(NodeType.Block)
        if(!term("{", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        
        while(pointer < token_cnt && token_table[pointer].name != "}") {
            var stmt = parse_statement(assert: false)
            if(!is_err(stmt)) { 
                block.children.add(stmt) 
            } else { 
                // 🚑 核心修复：语句级恐慌模式！绝不 break！
                error_cnt++
                let ln = token_table[pointer].line
                println("第 ${ln} 行语法错：无法识别的语句结构 (在 '${token_table[pointer].name}' 附近)")
                
                pointer++ // 越过当前无法识别的垃圾单词
                
                // 一直往前找，直到看见下一个安全标记，再重新开始解析
                while(pointer < token_cnt &&
                      token_table[pointer].name != "}" &&
                      token_table[pointer].name != ";" &&
                      token_table[pointer].name != "var" &&
                      token_table[pointer].name != "if" &&
                      token_table[pointer].name != "while" &&
                      token_table[pointer].name != "read" &&
                      token_table[pointer].name != "write") {
                    pointer++
                }
                if (pointer < token_cnt && token_table[pointer].name == ";") { pointer++ } // 顺便吃掉分号
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
        
        pointer = save; node = parse_read_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save; node = parse_write_stat(assert: false)
        if(!is_err(node)) { return node }
        
        pointer = save; return parse_expression_stat(assert: assert)
    }

    // ==========================================
    // 4. 完美支持类型、数组、赋初值的声明解析
    // ==========================================
    private func parse_declaration_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        if(term("var", assert: assert)){
            if(!cat(0, assert: true, check_id: false)) { pointer = save; return ASTNode(NodeType.ErrorNode) }
            var var_name = token_table[pointer-1].name
            
            // 1. 可选的数组下标 (如 [2])
            var is_array = false
            var arr_size = ASTNode(NodeType.ErrorNode)
            if (term("[", assert: false)) {
                is_array = true
                arr_size = parse_expression(assert: true)
                term("]", assert: true)
            }

            // 2. 可选的类型注解 (如 : int)
            if (term(":", assert: false)) {
                if (pointer < token_cnt && (token_table[pointer].name == "int" || token_table[pointer].name == "float")) {
                    pointer++ // 吃掉类型关键字
                }
            }

            // 3. 语义分析：查重
            if(symbol_table.contains(var_name)){ 
                error_cnt++; println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 重复声明！") 
            } else { 
                symbol_table[var_name] = next_var_addr; next_var_addr++ 
            }
            
            var var_node = ASTNode(if(is_array){NodeType.ArrayDecl}else{NodeType.VarDecl}, name: var_name)
            if (is_array && !is_err(arr_size)) { var_node.children.add(arr_size) }

            // 4. 可选的赋初值 (如 = 10)
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
        term("(", assert: true); var cond = parse_expression(assert: true); term(")", assert: true)
        var if_node = ASTNode(NodeType.IfStat)
        if_node.children.add(cond); if_node.children.add(parse_function_body(assert: true))
        if(term("else", assert: false)){ if_node.children.add(parse_function_body(assert: true)) }
        return if_node
    }

    private func parse_read_stat(assert!: Bool = true): ASTNode {
        if(!term("read", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        let has_paren = term("(", assert: false)
        if(!cat(0, assert: true, check_id: false)){ return ASTNode(NodeType.ErrorNode) }
        var var_name = token_table[pointer-1].name
        
        if(!symbol_table.contains(var_name)){ error_cnt++; println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 使用前未声明！") } 
        if(has_paren) { term(")", assert: true) }
        var node = ASTNode(NodeType.ReadStat); node.children.add(ASTNode(NodeType.Identifier, name: var_name))
        eat_semi(); return node 
    }

    private func parse_write_stat(assert!: Bool = true): ASTNode {
        if(!term("write", assert: assert)) { return ASTNode(NodeType.ErrorNode) }
        var node = ASTNode(NodeType.WriteStat); node.children.add(parse_expression(assert: true))
        eat_semi(); return node 
    }

    private func parse_expression_stat(assert!: Bool = true): ASTNode {
        var save = pointer
        if(cat(0, assert: false, check_id: false)){
            var var_name = token_table[pointer-1].name
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
                if(!symbol_table.contains(var_name)){ error_cnt++; println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 赋值前未声明！") }
                var assign_node = ASTNode(if(is_array_assign){NodeType.ArrayAssign}else{NodeType.Assign}, name: "=")
                if (is_array_assign) {
                    var arr_acc = ASTNode(NodeType.ArrayAccess, name: var_name); arr_acc.children.add(idx_expr)
                    assign_node.children.add(arr_acc)
                } else { assign_node.children.add(ASTNode(NodeType.Identifier, name: var_name)) }
                assign_node.children.add(expr); eat_semi(); return assign_node 
            }
        }
        pointer = save; var pure_expr = parse_expression(assert: false)
        if(!is_err(pure_expr)) { eat_semi(); return pure_expr }
        pointer = save; return ASTNode(NodeType.ErrorNode)
    }

    // ==========================================
    // 5. 表达式、优先级与符号表查缺
    // ==========================================
    private func parse_expression(assert!: Bool = true): ASTNode { return parse_bool_expr(assert: assert) }

    private func parse_bool_expr(assert!: Bool = true): ASTNode {
        var left = parse_additive_expr(assert: assert) 
        if(is_err(left) || pointer >= token_cnt) { return left }
        var op = token_table[pointer].name
        if(op == ">" || op == ">=" || op == "<" || op == "<=" || op == "==" || op == "!="){
            pointer++; var op_node = ASTNode(NodeType.BinOp, name: op)
            op_node.children.add(left); op_node.children.add(parse_additive_expr(assert: assert)); return op_node 
        }
        return left
    }

    private func parse_additive_expr(assert!: Bool = true): ASTNode {
        var left = parse_term(assert: assert) 
        if(is_err(left)) { return left }
        while(pointer < token_cnt && (token_table[pointer].name == "+" || token_table[pointer].name == "-")){
            var op_node = ASTNode(NodeType.BinOp, name: token_table[pointer].name)
            pointer++; op_node.children.add(left); op_node.children.add(parse_term(assert: true)); left = op_node 
        }
        return left
    }

    private func parse_term(assert!: Bool = true): ASTNode {
        var left = parse_factor(assert: assert) 
        if(is_err(left)) { return left }
        while(pointer < token_cnt && (token_table[pointer].name == "*" || token_table[pointer].name == "/")){
            var op_node = ASTNode(NodeType.BinOp, name: token_table[pointer].name)
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
        if(cat(0, assert: false, check_id: false)){  
            var var_name = token_table[pointer-1].name
            var is_array = false
            if(term("[", assert: false)) {
                var arr_node = ASTNode(NodeType.ArrayAccess, name: var_name)
                arr_node.children.add(parse_expression(assert: true)); term("]", assert: true)
                is_array = true; return arr_node
            }
            if(!is_array) {
                if(!symbol_table.contains(var_name)){
                    if(assert) { error_cnt++; println("第 ${token_table[pointer-1].line} 行错误：在表达式中未声明先引用 '${var_name}'！") }
                    return ASTNode(NodeType.Number, name: "0") // 造假人，保全整个树
                }
                return ASTNode(NodeType.Identifier, name: var_name)
            }
        }
        pointer = save
        if(cat(1, assert: assert)){ return ASTNode(NodeType.Number, name: token_table[pointer-1].name) }
        pointer = save; return ASTNode(NodeType.ErrorNode)
    }

    // ==========================================
    // 6. 基础匹配
    // ==========================================
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

    private func cat(lexeme: Int64, assert!: Bool = true, check_id!: Bool = true): Bool {
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