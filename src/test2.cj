package Cangjie_based_lexer

import std.collection.*
import std.fs.*

class parser2 <: base {
    private var pointer: Int64
    private var error_cnt: Int64
    private var symbol_table: Map<String, Int64>  // 变量名 -> 内存地址映射
    private var output_code: ArrayList<String>
    private var word_code: ArrayList<String>
    private var next_var_addr: Int64               // 变量分配地址计数器
    private var label_count: Int64                  // 唯一跳转标签计数器
    private var token_table: Array<token>
    private var token_cnt: Int64
    private var out_path: String

    // 汉化词法类别名称映射表，用于输出高质量错误信息
    private let num2lexeme: Array<String> = ["标识符(ID)", "整数(NUM)", "界符(SYMBOL)", "操作符(OP)", "关键字(KEYWORD)"]
   
    public parser2(token_table: Array<token>, token_cnt: Int64, out_path: String){
        this.pointer = 0
        this.error_cnt = 0
        this.symbol_table = HashMap<String, Int64>()
        this.output_code = ArrayList<String>()
        this.word_code = ArrayList<String>()
        this.next_var_addr = 0
        this.label_count = 0
        this.token_table = token_table
        this.token_cnt = token_cnt
        this.out_path = out_path
    }

    public func run(){
        if(parse_program()){
            println("\n语法与语义分析成功！开始输出目标中间代码：")
            output_code.append("STOP")
            write2file()
            for(code in output_code){ println(code) }
        }
        else{
            println("\n语法分析失败！累计发现 ${error_cnt} 处错误。")
        }
    }

    public func write2file(){
        let file = File.create(out_path)
        for(str in output_code){
            file.write((str+"\n").toArray())
        }
        file.close()
    }

    public func generate_word_code(): ArrayList<String> {
        for(line in output_code){
            var parts = line.split(" ")
            for(p in parts){
                if(p != "") {
                    word_code.append(p)
                }
            }
        }
        return word_code
    }

    // 生成唯一的控制流中间标签（如 L1, L2 等）
    private func new_label(): String{
        label_count++
        return "L${label_count}"
    }

    // 1. <program> -> { fun_declaration } <main_declaration>
    private func parse_program(assert!: Bool = true): Bool{
        while(pointer < token_cnt && token_table[pointer].name == "func") {
            if(!parse_fun_declaration()) { return false }
        }
        return parse_main_declaration(assert: assert)
    }

    // 2. <fun_declaration> -> func ID '(' { ID:type } ')' [ : type ] <fun_body>
    private func parse_fun_declaration(): Bool {
        if(!term("func")) { return false }
        if(!cat(0, check_id: false)) { return false } // 函数名
        if(!term("(")) { return false }
        
        // 解析可选的参数列表
        while(pointer < token_cnt && token_table[pointer].name != ")") {
            if(!cat(0, check_id: false)) { return false }
            if(!term(":")) { return false }
            if(!term("int")) { return false }
            if(pointer < token_cnt && token_table[pointer].name == ",") { pointer++ }
        }
        
        if(!term(")")) { return false }
        if(pointer < token_cnt && token_table[pointer].name == ":") {
            pointer++
            if(!term("int")) { return false }
        }
        return parse_function_body()
    }

    // 3. <main_declaration> -> main '(' { ID:type } ')' [ : type ] <fun_body>
    private func parse_main_declaration(assert!: Bool = true): Bool{
        if(!term("main", assert: assert)) { return false }
        if(!term("(")) { return false }
        
        while(pointer < token_cnt && token_table[pointer].name != ")") {
            if(!cat(0, check_id: false)) { return false }
            if(!term(":")) { return false }
            if(!term("int")) { return false }
            if(pointer < token_cnt && token_table[pointer].name == ",") { pointer++ }
        }
        
        if(!term(")")) { return false }
        if(pointer < token_cnt && token_table[pointer].name == ":") {
            pointer++
            if(!term("int")) { return false }
        }
        return parse_function_body()
    }

    // 4. <fun_body> -> '{' <declaration_list> <statement_list> '}'
    private func parse_function_body(assert!: Bool = true): Bool{
        return term("{") && parse_declaration_list() && parse_statement_list() && term("}")
    }

    // 5. <declaration_list> -> <declaration_list><declaration_stat> | ε
    private func parse_declaration_list(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_declaration_stat(assert: false) && parse_declaration_list())[1] ||
               (pointer=save, parse_epsilon())[1]
    }

    // 6. <declaration_stat> -> var ID:int
    private func parse_declaration_stat(assert!: Bool = true): Bool{
        var save = pointer
        if(term("var", assert: assert) && cat(0, check_id: false)){  
            var var_name = token_table[pointer-1].name
            if(symbol_table.contains(var_name)){
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 重复声明！")
                error_cnt++
            } else {
                symbol_table[var_name] = next_var_addr
                next_var_addr++
            }
            if(!term(":")) { return false }
            return term("int")
        }
        pointer = save
        return false
    }

    private func parse_epsilon(assert!: Bool = true): Bool{
        return true
    }

    // 7. <statement_list> -> <statement_list><statement> | ε
    private func parse_statement_list(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_statement(assert: false) && parse_statement_list())[1] ||
               (pointer=save, parse_epsilon())[1]
    }

    // 8. <statement> -> 从五个分支扩充为全部七个文法分支支持
    private func parse_statement(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_if_stat(assert: false))[1] ||
               (pointer=save, parse_while_stat(assert: false))[1] ||
               (pointer=save, parse_for_stat(assert: false))[1] ||
               (pointer=save, parse_read_stat(assert: false))[1] || 
               (pointer=save, parse_write_stat(assert: false))[1] || 
               (pointer=save, parse_compound_stat(assert: false))[1] ||
               (pointer=save, parse_expression_stat(assert: assert))[1]
    }

    // 9. <if_stat> -> if '(' <expr> ')' <statement> [ else <statement> ]
    private func parse_if_stat(assert!: Bool = true): Bool{
        if(!term("if", assert: assert)) {return false}
        if(!term("(")) {return false}
        if(!parse_expression()) {return false}
        if(!term(")")) {return false}

        let else_label = new_label()
        let end_label = new_label()
        output_code.append("BRF ${else_label}")

        if(!parse_statement()) {return false}

        output_code.append("BR ${end_label}")
        output_code.append("${else_label}:")

        if(term("else", assert: false)){
            if(!parse_statement()) {return false}
        }

        output_code.append("${end_label}:")
        return true
    }

    // 10. 🚨 补全：<while_stat> -> while '(' <expr> ')' <statement>
    private func parse_while_stat(assert!: Bool = true): Bool {
        if(!term("while", assert: assert)) { return false }
        if(!term("(")) { return false }
        
        let start_label = new_label()
        let end_label = new_label()
        
        output_code.append("${start_label}:") // 循环回溯点
        if(!parse_expression()) { return false }
        if(!term(")")) { return false }
        
        output_code.append("BRF ${end_label}") // 条件不满足退出循环
        if(!parse_statement()) { return false }
        
        output_code.append("BR ${start_label}") // 无条件循环
        output_code.append("${end_label}:")
        return true
    }

    // 11. 🚨 补全：<for_stat> -> for '(' ID in <expr> ')' <statement>
    private func parse_for_stat(assert!: Bool = true): Bool {
        if(!term("for", assert: assert)) { return false }
        if(!term("(")) { return false }
        if(!cat(0, check_id: false)) { return false } // 循环迭代变量
        
        var loop_var = token_table[pointer-1].name
        if(!symbol_table.contains(loop_var)) {
            symbol_table[loop_var] = next_var_addr
            next_var_addr++
        }
        
        if(!term("in")) { return false }
        if(!parse_expression()) { return false }
        if(!term(")")) { return false }
        
        let for_start = new_label()
        let for_end = new_label()
        
        output_code.append("${for_start}:")
        output_code.append("BRF ${for_end}")
        if(!parse_statement()) { return false }
        output_code.append("BR ${for_start}")
        output_code.append("${for_end}:")
        return true
    }

    // 13. <read_stat> -> read ID
    private func parse_read_stat(assert!: Bool = true): Bool{
        var save = pointer
        if(term("read", assert: assert, cogen: false) && cat(0, cogen: false)){
            var var_name = token_table[pointer-1].name
            if(!symbol_table.contains(var_name)){
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 使用前未声明！")
            } else {
                output_code.append("IN")
                output_code.append("STO ${symbol_table[var_name]}")
            }
            return term(";", cogen: false)
        }
        pointer = save
        return false        
    }

    // 12. <write_stat> -> write <expression>
    private func parse_write_stat(assert!: Bool = true): Bool{
        var save = pointer
        if(term("write", assert: assert, cogen: false)){
            if(!parse_expression()) {return false}
            output_code.append("OUT")
            if(!term(";", cogen: false)) {return false}
            return true
        }
        pointer = save
        return false
    }

    // 14. <compound_stat> -> '{' <statement_list> '}'
    private func parse_compound_stat(assert!: Bool = true): Bool{
        return term("{", assert: assert) && parse_statement_list() && term("}")
    }

    // 15 & 16. <expression_stat> -> <expression> | ID = <bool_expr>
    private func parse_expression_stat(assert!: Bool = true): Bool{
        var save = pointer
        if(pointer + 1 < token_cnt && token_table[pointer + 1].name == "="){
            if(!cat(0, assert: false)) {return false}
            var var_name = token_table[pointer-1].name
            if(!term("=")) {return false}
            if(!parse_bool_expr()) {return false}
            if(!term(";")) {return false}
            if(!symbol_table.contains(var_name)){
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 赋值前未声明！")
            } else {
                output_code.append("STO ${symbol_table[var_name]}")
                output_code.append("POP")    // 清理执行栈
            }
            return true
        }
        pointer = save
        if(parse_expression(assert: false) && term(";")) {
            output_code.append("POP")        
            return true
        }
        pointer = save
        if(term(";", assert: assert)){
            return true
        }
        return false
    }

    private func parse_expression(assert!: Bool = true): Bool{
        return parse_bool_expr(assert: assert)
    }

    // 17. 🚨 补全：布尔表达式（完整映射支持 >, >=, <, <=, ==, !=）
    private func parse_bool_expr(assert!: Bool = true): Bool{
        if(!parse_additive_expr()) {return false}
        var save = pointer
        if(pointer < token_cnt){
            var op = token_table[pointer].name
            if(op == ">" || op == ">=" || op == "<" || op == "<=" || op == "==" || op == "!="){
                pointer++
                if(!parse_additive_expr()) {return false}
                // 依据关系操作符生成对应的具体 P-Code 计算指令
                if(op == ">"){ output_code.append("GT") } 
                else if(op == ">="){ output_code.append("GE") }
                else if(op == "<"){ output_code.append("LT") }
                else if(op == "<="){ output_code.append("LE") }
                else if(op == "=="){ output_code.append("EQ") }
                else if(op == "!="){ output_code.append("NE") }
                return true
            }
        }
        pointer = save
        return true
    }

    // 18. <additive_expr> -> <term> { (+|-) <term> }
    private func parse_additive_expr(assert!: Bool = true): Bool{
        if(!parse_term()) {return false}
        while(true){
            var save = pointer
            if(term("+", assert: false)){
                if(!parse_term()) {return false}
                output_code.append("ADD")
            } else if(term("-", assert: false)){
                if(!parse_term()) {return false}
                output_code.append("SUB")
            } else {
                pointer = save
                break
            }
        }
        return true
    }

    // 19. <term> -> <factor> { (*|/) <factor> }
    private func parse_term(assert!: Bool = true): Bool{
        if(!parse_factor()) {return false}
        while(true){
            var save = pointer
            if(term("*", assert: false)){
                if(!parse_factor()) {return false}
                output_code.append("MULT")
            } else if(term("/", assert: false)){
                if(!parse_factor()) {return false}
                output_code.append("DIV")
            } else {
                pointer = save
                break
            }
        }
        return true
    }

    // 20. <factor> -> '(' <additive_expr> ')' | ID | NUM
    private func parse_factor(assert!: Bool = true): Bool{
        var save = pointer
        if(term("(", assert: false)){
            if(!parse_additive_expr()) {return false}
            if(!term(")")) {return false}
            return true
        }
        pointer = save
        if(cat(0, assert: false)){  
            var var_name = token_table[pointer-1].name
            if(!symbol_table.contains(var_name)){
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 表达式中未声明先引用！")
                return false
            }
            output_code.append("LOAD ${symbol_table[var_name]}")
            return true
        }
        pointer = save
        if(cat(1, assert: assert)){  
            var val_str = token_table[pointer-1].name
            output_code.append("LOADI ${val_str}")
            return true
        }
        pointer = save
        return false
    }

    // 终结符底层比对函数
    private func term(tok: String, assert!: Bool = true, cogen!: Bool = true): Bool{
        if(assert){
            if(afadd_term() == tok){
                return true
            }else{
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行语法错：期望得到终结符 '${tok}'，实际读入：'${token_table[pointer-1].name}'") 
                return false
            }
        }else{
            if(afadd_term() == tok){
                return true
            }else{
                return false
            } 
        }
    }

    private func afadd_term(): String{
        if(pointer >= token_cnt || token_table[pointer].lexeme == 5){return "文件流结束(EOF)"}
        var tok = token_table[pointer].name
        pointer++
        return tok
    }

    // 类别属性（标识符/数字等）匹配函数
    private func cat(lexeme: Int64, assert!: Bool = true, check_id!: Bool = true, cogen!: Bool = true): Bool{
        var side_check = false
        if(pointer < token_cnt && lexeme == 0 && token_table[pointer].lexeme == 0){side_check = true}
        if(assert || side_check){
            if(afadd_cat() == lexeme && (lexeme != 0 || !check_id || symbol_table.contains(token_table[pointer-1].name))){
                return true
            }
            else{
                error_cnt++
                if(token_table[pointer-1].lexeme != lexeme){
                    println("第 ${token_table[pointer-1].line} 行类型错：期望读取 [${num2lexeme[lexeme]}] 类别，实际得到：[${num2lexeme[token_table[pointer-1].lexeme]}]")
                }
                return false
            }
        }else{
            if(afadd_cat() == lexeme && (lexeme != 0 || !check_id || symbol_table.contains(token_table[pointer-1].name))){
                return true
            }else{
                return false
            }
        }
    }

    private func afadd_cat(): Int64{
        if(pointer >= token_cnt || token_table[pointer].lexeme == 5){return 5}
        var lexeme = token_table[pointer].lexeme
        pointer++
        return lexeme
    }
}