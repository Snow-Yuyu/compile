package compile

import std.collection.*
import std.fs.*

class parser2 {
    private var pointer: Int64
    public var error_cnt: Int64
    private var symbol_table: Map<String, Int64>  
    private var output_code: ArrayList<String>
    private var next_var_addr: Int64               
    private var label_count: Int64                  
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
        this.label_count = 0
        this.token_table = token_table
        this.token_cnt = token_cnt
        this.out_path = out_path
    }

    public func run(){
        if(parse_program() && error_cnt == 0){
            println("  └─ ✓ 语法与语义分析成功！没有发现错误。")
            output_code.add("STOP")
            write2file()
            println("\n--- 虚拟机目标中间代码(P-Code) ---")
            for(code in output_code){ println(code) }
        }
        else{
            println("  └─ ❌ 语法与语义分析失败！累计发现 ${error_cnt} 处错误。")
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
        println("  └─ 中间代码结果已成功写入文件：${out_path}")
    }

    private func new_label(): String{
        label_count++
        return "L${label_count}"
    }

    private func parse_program(assert!: Bool = true): Bool{
        while(pointer < token_cnt && token_table[pointer].name == "func") {
            if(!parse_fun_declaration(assert: assert)) { return false }
        }
        return parse_main_declaration(assert: assert)
    }

    private func parse_fun_declaration(assert!: Bool = true): Bool {
        if(!term("func", assert: assert)) { return false }
        if(!cat(0, assert: true, check_id: false)) { return false } 
        if(!term("(", assert: true)) { return false }
        while(pointer < token_cnt && token_table[pointer].name != ")") {
            if(!cat(0, assert: true, check_id: false)) { return false }
            if(!term(":", assert: true)) { return false }
            if(!term("int", assert: true)) { return false }
            if(pointer < token_cnt && token_table[pointer].name == ",") { pointer++ }
        }
        if(!term(")", assert: true)) { return false }
        if(pointer < token_cnt && token_table[pointer].name == ":") {
            pointer++
            if(!term("int", assert: true)) { return false }
        }
        return parse_function_body(assert: true)
    }

    private func parse_main_declaration(assert!: Bool = true): Bool{
        if(!term("main", assert: assert)) { return false }
        if(!term("(", assert: true)) { return false }
        while(pointer < token_cnt && token_table[pointer].name != ")") {
            if(!cat(0, assert: true, check_id: false)) { return false }
            if(!term(":", assert: true)) { return false }
            if(!term("int", assert: true)) { return false }
            if(pointer < token_cnt && token_table[pointer].name == ",") { pointer++ }
        }
        if(!term(")", assert: true)) { return false }
        if(pointer < token_cnt && token_table[pointer].name == ":") {
            pointer++
            if(!term("int", assert: true)) { return false }
        }
        return parse_function_body(assert: true)
    }

    private func parse_function_body(assert!: Bool = true): Bool{
        return term("{", assert: assert) && parse_declaration_list(assert: true) && parse_statement_list(assert: true) && term("}", assert: true)
    }

    private func parse_declaration_list(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_declaration_stat(assert: false) && parse_declaration_list(assert: assert))[1] ||
               (pointer=save, parse_epsilon(assert: assert))[1]
    }

    private func parse_declaration_stat(assert!: Bool = true): Bool{
        var save = pointer
        
        if(term("var", assert: assert)){
            if(!cat(0, assert: true, check_id: false)) { pointer = save; return false }
            var var_name = token_table[pointer-1].name
            
            if(symbol_table.contains(var_name)){
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 重复声明！")
                error_cnt++
            } else {
                symbol_table[var_name] = next_var_addr
                next_var_addr++
            }
            
            if(pointer < token_cnt && token_table[pointer].name == "[") {
                pointer++ 
                if(!cat(1, assert: true)) { pointer = save; return false } 
                if(!term("]", assert: true)) { pointer = save; return false }
                if(!term(";", assert: true)) { pointer = save; return false }
                return true
            }
            
            if(pointer < token_cnt && token_table[pointer].name == ":") {
                pointer++
                if(!term("int", assert: true)) { pointer = save; return false }
            }
            
            if(pointer < token_cnt && token_table[pointer].name == "="){
                pointer++
                if(!parse_expression(assert: true)) { pointer = save; return false }
            }
            
            if(!term(";", assert: true)) { pointer = save; return false }
            return true
        }
        
        pointer = save
        if(term("let", assert: assert)){
            if(!cat(0, assert: true, check_id: false)) { pointer = save; return false }
            var var_name = token_table[pointer-1].name
            
            if(symbol_table.contains(var_name)){
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 重复声明！")
                error_cnt++
            } else {
                symbol_table[var_name] = next_var_addr
                next_var_addr++
            }
            
            if(!term("=", assert: true)) { pointer = save; return false }
            if(!parse_expression(assert: true)) { pointer = save; return false }
            if(!term(";", assert: true)) { pointer = save; return false }
            return true
        }
        
        pointer = save
        return false
    }

    private func parse_epsilon(assert!: Bool = true): Bool{ 
        let _ = assert
        return true 
    }

    private func parse_statement_list(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_statement(assert: false) && parse_statement_list(assert: assert))[1] ||
               (pointer=save, parse_epsilon(assert: assert))[1]
    }

    private func parse_statement(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_declaration_stat(assert: false))[1] ||
               (pointer=save, parse_if_stat(assert: false))[1] ||
               (pointer=save, parse_while_stat(assert: false))[1] ||
               (pointer=save, parse_for_stat(assert: false))[1] ||
               (pointer=save, parse_read_stat(assert: false))[1] || 
               (pointer=save, parse_write_stat(assert: false))[1] || 
               (pointer=save, parse_compound_stat(assert: false))[1] ||
               (pointer=save, parse_jump_stat(assert: false))[1] ||        
               (pointer=save, parse_match_stat(assert: false))[1] ||       
               (pointer=save, parse_nested_func_stat(assert: false))[1] || 
               (pointer=save, parse_expression_stat(assert: assert))[1]
    }

    private func parse_if_stat(assert!: Bool = true): Bool{
        if(!term("if", assert: assert)) {return false}
        if(!term("(", assert: true)) {return false}
        if(!parse_expression(assert: true)) {return false}
        if(!term(")", assert: true)) {return false}

        let else_label = new_label()
        let end_label = new_label()
        output_code.add("BRF ${else_label}")

        if(!parse_statement(assert: true)) {return false}
        output_code.add("BR ${end_label}")
        output_code.add("${else_label}:")

        if(term("else", assert: false)){
            if(!parse_statement(assert: true)) {return false}
        }
        output_code.add("${end_label}:")
        return true
    }

    private func parse_while_stat(assert!: Bool = true): Bool {
        if(!term("while", assert: assert)) { return false }
        if(!term("(", assert: true)) { return false }
        let start_label = new_label()
        let end_label = new_label()
        output_code.add("${start_label}:") 
        if(!parse_expression(assert: true)) { return false }
        if(!term(")", assert: true)) { return false }
        output_code.add("BRF ${end_label}") 
        if(!parse_statement(assert: true)) { return false }
        output_code.add("BR ${start_label}") 
        output_code.add("${end_label}:")
        return true
    }

    private func parse_for_stat(assert!: Bool = true): Bool {
        if(!term("for", assert: assert)) { return false }
        if(!term("(", assert: true)) { return false }
        if(!cat(0, assert: true, check_id: false)) { return false } 
        var loop_var = token_table[pointer-1].name
        if(!symbol_table.contains(loop_var)) {
            symbol_table[loop_var] = next_var_addr
            next_var_addr++
        }
        if(!term("in", assert: true)) { return false }
        if(!parse_expression(assert: true)) { return false }
        if(!term(")", assert: true)) { return false }
        let for_start = new_label()
        let for_end = new_label()
        output_code.add("${for_start}:")
        output_code.add("BRF ${for_end}")
        if(!parse_statement(assert: true)) { return false }
        output_code.add("BR ${for_start}")
        output_code.add("${for_end}:")
        return true
    }

    private func parse_jump_stat(assert!: Bool = true): Bool {
        var save = pointer
        if(term("break", assert: assert)) {
            if(term(";", assert: true)) { output_code.add("BRK"); return true }
        }
        pointer = save
        if(term("continue", assert: assert)) {
            if(term(";", assert: true)) { output_code.add("CNT"); return true }
        }
        pointer = save
        if(term("return", assert: assert)) {
            parse_expression(assert: false)
            if(term(";", assert: true)) { output_code.add("RET"); return true }
        }
        pointer = save
        return false
    }

    private func parse_match_stat(assert!: Bool = true): Bool {
        if(!term("match", assert: assert)) { return false }
        if(!term("(", assert: true)) { return false }
        if(!parse_expression(assert: true)) { return false }
        if(!term(")", assert: true)) { return false }
        if(!term("{", assert: true)) { return false }
        while(pointer < token_cnt && token_table[pointer].name == "case") {
            pointer++ 
            if(!parse_expression(assert: true)) { return false }
            if(!term(":", assert: true)) { return false }
            if(!parse_statement(assert: true)) { return false }
        }
        if(!term("}", assert: true)) { return false }
        return true
    }

    private func parse_nested_func_stat(assert!: Bool = true): Bool {
        if(!term("func", assert: assert)) { return false }
        pointer-- 
        return parse_fun_declaration(assert: true)
    }

    private func parse_read_stat(assert!: Bool = true): Bool{
        if(!term("read", assert: assert)) { return false }
        
        let has_paren = term("(", assert: false)
        if(!cat(0, assert: true, check_id: false)){ return false }
        
        var var_name = token_table[pointer-1].name
        if(!symbol_table.contains(var_name)){
            error_cnt++
            println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 使用前未声明！")
        } else {
            output_code.add("IN")
            output_code.add("STO ${symbol_table[var_name]}")
        }
        
        if(has_paren && !term(")", assert: true)) { return false }
        if(!term(";", assert: true)) { return false }
        return true
    }

    private func parse_write_stat(assert!: Bool = true): Bool{
        if(!term("write", assert: assert)) { return false }
        if(!parse_expression(assert: true)) {return false}
        output_code.add("OUT")
        if(!term(";", assert: true)) {return false}
        return true
    }

    private func parse_compound_stat(assert!: Bool = true): Bool{
        return term("{", assert: assert) && parse_statement_list(assert: true) && term("}", assert: true)
    }

    private func parse_expression_stat(assert!: Bool = true): Bool{
        var save = pointer
        if(pointer + 1 < token_cnt && token_table[pointer + 1].name == "="){
            if(!cat(0, assert: assert, check_id: false)) {return false}
            var var_name = token_table[pointer-1].name
            if(!term("=", assert: true)) {return false}
            if(!parse_bool_expr(assert: true)) {return false} 
            if(!term(";", assert: true)) {return false}
            if(!symbol_table.contains(var_name)){
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 赋值前未声明！")
            } else {
                output_code.add("STO ${symbol_table[var_name]}")
                output_code.add("POP") 
            }
            return true
        }
        pointer = save
        if(parse_expression(assert: false) && term(";", assert: assert)) {
            output_code.add("POP")        
            return true
        }
        pointer = save
        if(term(";", assert: assert)){ return true }
        return false
    }

    private func parse_expression(assert!: Bool = true): Bool{ return parse_bool_expr(assert: assert) }

    private func parse_bool_expr(assert!: Bool = true): Bool{
        if(!parse_additive_expr(assert: assert)) {return false} 
        var save = pointer
        if(pointer < token_cnt){
            var op = token_table[pointer].name
            if(op == ">" || op == ">=" || op == "<" || op == "<=" || op == "==" || op == "!="){
                pointer++
                if(!parse_additive_expr(assert: assert)) {return false} 
                if(op == ">"){ output_code.add("GT") } 
                else if(op == ">="){ output_code.add("GE") }
                else if(op == "<"){ output_code.add("LT") }
                else if(op == "<="){ output_code.add("LE") }
                else if(op == "=="){ output_code.add("EQ") }
                else if(op == "!="){ output_code.add("NE") }
                return true
            }
        }
        pointer = save
        return true
    }

    private func parse_additive_expr(assert!: Bool = true): Bool{
        if(!parse_term(assert: assert)) {return false} 
        while(true){
            if(term("+", assert: false)){
                if(!parse_term(assert: assert)) {return false} 
                output_code.add("ADD")
            } else if(term("-", assert: false)){
                if(!parse_term(assert: assert)) {return false} 
                output_code.add("SUB")
            } else {
                break
            }
        }
        return true
    }

    private func parse_term(assert!: Bool = true): Bool{
        if(!parse_factor(assert: assert)) {return false} 
        while(true){
            if(term("*", assert: false)){
                if(!parse_factor(assert: assert)) {return false} 
                output_code.add("MULT")
            } else if(term("/", assert: false)){
                if(!parse_factor(assert: assert)) {return false} 
                output_code.add("DIV")
            } else {
                break
            }
        }
        return true
    }

    private func parse_factor(assert!: Bool = true): Bool{
        var save = pointer
        if(term("(", assert: false)){
            if(!parse_additive_expr(assert: true)) {return false}
            if(!term(")", assert: true)) {return false}
            return true
        }
        pointer = save
        if(cat(0, assert: false, check_id: false)){  
            var var_name = token_table[pointer-1].name
            if(!symbol_table.contains(var_name)){
                if(assert) { 
                    error_cnt++
                    println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 在表达式中未声明先引用！")
                }
                // ✨ 核心修复：遇到未声明变量（语义错误）时，骗过语法流继续解析
                output_code.add("LOAD 0") 
                return true
            }
            output_code.add("LOAD ${symbol_table[var_name]}")
            return true
        }
        pointer = save
        if(cat(1, assert: assert)){  
            var val_str = token_table[pointer-1].name
            output_code.add("LOADI ${val_str}")
            return true
        }
        pointer = save
        return false
    }

    private func term(tok: String, assert!: Bool = true): Bool{
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

    private func cat(lexeme: Int64, assert!: Bool = true, check_id!: Bool = true): Bool{
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