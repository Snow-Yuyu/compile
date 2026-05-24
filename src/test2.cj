package compile

import std.collection.*
import std.fs.*

class parser2 {
    private var pointer: Int64
    public var error_cnt: Int64
    private var symbol_table: Map<String, Int64>  // 变量名 -> 内存地址映射
    private var output_code: ArrayList<String>
    private var word_code: ArrayList<String>
    private var next_var_addr: Int64               // 变量分配地址计数器
    private var label_count: Int64                  // 唯一跳转标签计数器
    private var token_table: Array<Token>
    private var token_cnt: Int64
    private var out_path: String

    private let num2lexeme: Array<String> = ["标识符(ID)", "整数(NUM)", "界符(SYMBOL)", "操作符(OP)", "关键字(KEYWORD)"]
   
    public parser2(token_table: Array<Token>, token_cnt: Int64, out_path: String){
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
        if(parse_program() && error_cnt == 0){
            println("  └─ ✓ 语法与语义分析成功！中间代码已就绪。")
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
        // ✨ 增强：写入前彻底清理残余同名旧文件，拒绝抛出已存在异常
        if (exists(targetPath)) { 
            remove(targetPath) 
        }
        let file = File.create(out_path)
        for(str in output_code){
            file.write((str+"\n").toArray())
        }
        file.close()
        println("  └─ 中间代码结果已写入文件：${out_path}")
    }

    public func generate_word_code(): ArrayList<String> {
        for(line in output_code){
            var parts = line.split(" ")
            for(p in parts){
                if(p != "") { word_code.add(p) }
            }
        }
        return word_code
    }

    private func new_label(): String{
        label_count++
        return "L${label_count}"
    }

    private func parse_program(assert!: Bool = true): Bool{
        while(pointer < token_cnt && token_table[pointer].name == "func") {
            if(!parse_fun_declaration()) { return false }
        }
        return parse_main_declaration(assert: assert)
    }

    private func parse_fun_declaration(): Bool {
        if(!term("func")) { return false }
        if(!cat(0, check_id: false)) { return false } 
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

    private func parse_function_body(assert!: Bool = true): Bool{
        return term("{") && parse_declaration_list() && parse_statement_list() && term("}")
    }

    private func parse_declaration_list(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_declaration_stat(assert: false) && parse_declaration_list())[1] ||
               (pointer=save, parse_epsilon())[1]
    }

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

    private func parse_epsilon(assert!: Bool = true): Bool{ return true }

    private func parse_statement_list(assert!: Bool = true): Bool{
        var save = pointer
        return (pointer=save, parse_statement(assert: false) && parse_statement_list())[1] ||
               (pointer=save, parse_epsilon())[1]
    }

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

    private func parse_if_stat(assert!: Bool = true): Bool{
        if(!term("if", assert: assert)) {return false}
        if(!term("(")) {return false}
        if(!parse_expression()) {return false}
        if(!term(")")) {return false}

        let else_label = new_label()
        let end_label = new_label()
        output_code.add("BRF ${else_label}")

        if(!parse_statement()) {return false}
        output_code.add("BR ${end_label}")
        output_code.add("${else_label}:")

        if(term("else", assert: false)){
            if(!parse_statement()) {return false}
        }
        output_code.add("${end_label}:")
        return true
    }

    private func parse_while_stat(assert!: Bool = true): Bool {
        if(!term("while", assert: assert)) { return false }
        if(!term("(")) { return false }
        let start_label = new_label()
        let end_label = new_label()
        output_code.add("${start_label}:") 
        if(!parse_expression()) { return false }
        if(!term(")")) { return false }
        output_code.add("BRF ${end_label}") 
        if(!parse_statement()) { return false }
        output_code.add("BR ${start_label}") 
        output_code.add("${end_label}:")
        return true
    }

    private func parse_for_stat(assert!: Bool = true): Bool {
        if(!term("for", assert: assert)) { return false }
        if(!term("(")) { return false }
        if(!cat(0, check_id: false)) { return false } 
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
        output_code.add("${for_start}:")
        output_code.add("BRF ${for_end}")
        if(!parse_statement()) { return false }
        output_code.add("BR ${for_start}")
        output_code.add("${for_end}:")
        return true
    }

    private func parse_read_stat(assert!: Bool = true): Bool{
        var save = pointer
        if(term("read", assert: assert, cogen: false) && cat(0, cogen: false)){
            var var_name = token_table[pointer-1].name
            if(!symbol_table.contains(var_name)){
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 使用前未声明！")
            } else {
                output_code.add("IN")
                output_code.add("STO ${symbol_table[var_name]}")
            }
            return term(";", cogen: false)
        }
        pointer = save
        return false        
    }

    private func parse_write_stat(assert!: Bool = true): Bool{
        var save = pointer
        if(term("write", assert: assert, cogen: false)){
            if(!parse_expression()) {return false}
            output_code.add("OUT")
            if(!term(";", cogen: false)) {return false}
            return true
        }
        pointer = save
        return false
    }

    private func parse_compound_stat(assert!: Bool = true): Bool{
        return term("{", assert: assert) && parse_statement_list() && term("}")
    }

    private func parse_expression_stat(assert!: Bool = true): Bool{
        var save = pointer
        // 探测赋值号（通过 check_id: false 干净识别标识符，不触发级联检测）
        if(pointer + 1 < token_cnt && token_table[pointer + 1].name == "="){
            if(!cat(0, assert: false, check_id: false)) {return false}
            var var_name = token_table[pointer-1].name
            if(!term("=")) {return false}
            if(!parse_bool_expr()) {return false}
            if(!term(";")) {return false}
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
        if(parse_expression(assert: false) && term(";")) {
            output_code.add("POP")        
            return true
        }
        pointer = save
        if(term(";", assert: assert)){ return true }
        return false
    }

    private func parse_expression(assert!: Bool = true): Bool{ return parse_bool_expr(assert: assert) }

    private func parse_bool_expr(assert!: Bool = true): Bool{
        if(!parse_additive_expr()) {return false}
        var save = pointer
        if(pointer < token_cnt){
            var op = token_table[pointer].name
            if(op == ">" || op == ">=" || op == "<" || op == "<=" || op == "==" || op == "!="){
                pointer++
                if(!parse_additive_expr()) {return false}
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
        if(!parse_term()) {return false}
        while(true){
            var save = pointer
            if(term("+", assert: false)){
                if(!parse_term()) {return false}
                output_code.add("ADD")
            } else if(term("-", assert: false)){
                if(!parse_term()) {return false}
                output_code.add("SUB")
            } else {
                pointer = save
                break
            }
        }
        return true
    }

    private func parse_term(assert!: Bool = true): Bool{
        if(!parse_factor()) {return false}
        while(true){
            var save = pointer
            if(term("*", assert: false)){
                if(!parse_factor()) {return false}
                output_code.add("MULT")
            } else if(term("/", assert: false)){
                if(!parse_factor()) {return false}
                output_code.add("DIV")
            } else {
                pointer = save
                break
            }
        }
        return true
    }

    private func parse_factor(assert!: Bool = true): Bool{
        var save = pointer
        if(term("(", assert: false)){
            if(!parse_additive_expr()) {return false}
            if(!term(")")) {return false}
            return true
        }
        pointer = save
        // ✨ 改进：先只管是不是ID，剥离后续的语义检查，避免未声明引用被误判成非整数类型错误
        if(cat(0, assert: false, check_id: false)){  
            var var_name = token_table[pointer-1].name
            if(!symbol_table.contains(var_name)){
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行错误：变量 '${var_name}' 在表达式中未声明先引用！")
                return false
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

    private func term(tok: String, assert!: Bool = true, cogen!: Bool = true): Bool{
        if(assert){
            if(afadd_term() == tok){ return true }
            else{
                error_cnt++
                println("第 ${token_table[pointer-1].line} 行语法错：期望得到终结符 '${tok}'，实际得到：'${token_table[pointer-1].name}'") 
                return false
            }
        }else{
            if(afadd_term() == tok){ return true }
            else{ return false } 
        }
    }

    private func afadd_term(): String{
        if(pointer >= token_cnt || token_table[pointer].lexeme == 5){return "文件流结束(EOF)"}
        var tok = token_table[pointer].name
        pointer++
        return tok
    }

    // ✨ 核心修复：移除了多余的 side_check 报错级联分支，使 speculative（预测分支）回溯正常工作
    private func cat(lexeme: Int64, assert!: Bool = true, check_id!: Bool = true, cogen!: Bool = true): Bool{
        if(assert){
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