package compile
import std.fs.*

public struct Token {
    public var lexeme: Int64
    public var name: String
    public var line: UInt64
    public init(lexeme: Int64, name: String, line: UInt64) {
        this.lexeme = lexeme; this.name = name; this.line = line
    }
}

class FileReader {
    private var file_path: String
    public init(file_path: String) { this.file_path = file_path }
    public func get_program(): Array<Rune> {
        try {
            let program_bytes = File.readFrom(this.file_path)
            var program = Array<Rune>(program_bytes.size, { _ => r'0' })
            for (i in 0..program_bytes.size) { program[i] = Rune(UInt32(program_bytes[i])) }
            return program
        } catch (e: Exception) { return Array<Rune>(0, { _ => r'0' }) }
    }
}

class Lexer {
    private var program: Array<Rune>      
    private var out_path: String          
    private var line: UInt64 = 1          
    private var is_error: Bool = false    
    private var token_cnt: Int64 = 0      
    private var pointer: Int64 = 0        
    private var results: Array<Token> = Array<Token>(10000, { _ => Token(0, "", 0) })
    private let num2lexeme: Array<String> = ["ID", "NUM", "SYMBOL", "OP", "KEYWORD"]

    // ✨ 补充了所有新语法所需的关键字
    private let keywords: Array<String> = [
        "break", "case", "const", "continue", "default", "do", "else", "for", 
        "func", "if", "in", "int", "let", "main", "read", "return", 
        "switch", "var", "void", "while", "write"
    ]

    public init(program: Array<Rune>, out_path: String) {
        this.program = program; this.out_path = out_path
    }

    public func run(): Array<Token> {
        while (pointer < program.size) {
            if (is_empty(program[pointer])) { read_next(); continue }
            if (is_letter_or_underscore(program[pointer])) { 
                var id: String = String(program[pointer])
                read_next()
                while (pointer < program.size) {
                    if (is_letter_or_underscore(program[pointer]) || is_digit(program[pointer])) {
                        id += String(program[pointer]); read_next()
                    } else {
                        if (is_keyword_binary_search(id)) { results[token_cnt] = Token(4, id, this.line) } 
                        else { results[token_cnt] = Token(0, id, this.line) }
                        token_cnt++; break
                    }
                }
                continue
            }
            if (is_digit(program[pointer])) {          
                var num: String = String(program[pointer])
                read_next()
                while (pointer < program.size) {
                    if (is_digit(program[pointer])) {
                        num += String(program[pointer]); read_next()
                    } else {
                        if (!is_letter_or_underscore(program[pointer])) {
                            results[token_cnt] = Token(1, num, this.line); token_cnt++; break
                        } else { found_error(program[pointer]); break }
                    }
                }
                continue
            }
            if (is_single_signal(program[pointer])) {  
                results[token_cnt] = Token(2, String(program[pointer]), this.line)
                token_cnt++; read_next(); continue
            }
            if (is_other_signal(program[pointer])) {   
                var op: String = String(program[pointer]); read_next()
                if (pointer < program.size && program[pointer] == r'=') {        
                    op += String(r'='); results[token_cnt] = Token(3, op, this.line); token_cnt++; read_next()
                } else { results[token_cnt] = Token(3, op, this.line); token_cnt++ }
                continue
            }
            if (is_slash(program[pointer])) {          
                if (pointer + 1 < program.size) {
                    read_next() 
                    if (pointer < program.size && program[pointer] == r'*') {    
                        while (pointer < program.size) {
                            read_next()
                            if (pointer + 1 < program.size && program[pointer] == r'*') {
                                read_next(); if (program[pointer] == r'/') { read_next(); break }
                            }
                        }
                    } else if (pointer < program.size && program[pointer] == r'/') { 
                        while (pointer < program.size) {
                            read_next(); if (pointer < program.size && UInt32(program[pointer]) == 10) { read_next(); break }
                        }
                    } else { results[token_cnt] = Token(3, "/", this.line); token_cnt++ }
                } else { results[token_cnt] = Token(3, "/", this.line); token_cnt++; read_next() }
                continue
            }
            found_error(program[pointer]); read_next()
        }
        return results
    }

    public func writetofile() {
        let targetPath = Path(out_path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        for (i in 0..token_cnt) {
            file.write(("${results[i].lexeme}\t\t${results[i].name}\n").toArray())
        }
        file.close()
    }
    private func read_next() { if (pointer < program.size && UInt32(program[pointer]) == 10) { this.line++ }; this.pointer++ }
    private func found_error(ch: Rune) { this.is_error = true; println("词法错误：未识别的字符 '${ch}'") }
    private func is_keyword_binary_search(str: String): Bool {
        for(k in keywords) { if (k == str) { return true } }; return false
    }
    private func is_empty(ch: Rune): Bool { return UInt32(ch) == 10 || UInt32(ch) == 13 || UInt32(ch) == 32 || UInt32(ch) == 9 }
    private func is_letter_or_underscore(ch: Rune): Bool { return (ch >= r'A' && ch <= r'Z') || (ch >= r'a' && ch <= r'z') || ch == r'_' }
    private func is_digit(ch: Rune): Bool { return ch >= r'0' && ch <= r'9' }
    private func is_single_signal(ch: Rune): Bool { return ch == r';' || ch == r':' || ch == r',' || ch == r'(' || ch == r')' || ch == r'[' || ch == r']' || ch == r'{' || ch == r'}' || ch == r'+' || ch == r'-' || ch == r'*' }
    private func is_other_signal(ch: Rune): Bool { return ch == r'>' || ch == r'<' || ch == r'!' || ch == r'=' }
    private func is_slash(ch: Rune): Bool { return ch == r'/' }
}

main() {
    let src_path = "D:/Astudy/code/compile/input.txt"          
    let lex_out = "D:/Astudy/code/compile/token_out.txt"   
    let ast_out = "D:/Astudy/code/compile/ast_out.txt"   
    let pcode_out = "D:/Astudy/code/compile/pcode_out.txt"
    // ✨ 增加一条：VM 最终执行结果的文件路径
    let vm_out_path = "D:/Astudy/code/compile/vm_out.txt"

    println("==============================================")
    println(">>> [1] Lexer 开始切词...")
    let src_runes = FileReader(src_path).get_program()
    var myLexer = Lexer(src_runes, lex_out)
    let tokens_raw = myLexer.run()
    myLexer.writetofile()

    var valid_cnt: Int64 = 0
    for (i in 0..10000) { if (tokens_raw[i].line == 0) { break }; valid_cnt++ }
    var precise_tokens = Array<Token>(valid_cnt, { i => tokens_raw[i] })

    println(">>> [2] Parser 开始语法建树...")
    var myParser = parser2(precise_tokens, valid_cnt, ast_out)
    myParser.run() 

    println(">>> [3] Semantic & CodeGen 开始生成 P-Code...")
    let root_node = ASTDeserializer.load_from_file(ast_out)
    var analyzer = SemanticAnalyzer()
    analyzer.run(root_node, pcode_out)

    // ✨ 阶段 4：将生成好的 P-Code 送入虚拟机并执行
    println(">>> [4] 正在启动栈式虚拟机 (VM) 执行目标机器码...")
    let vm = VirtualMachine()
    vm.load_codes(pcode_out)   // 读入 test3 生成的指令文件
    vm.run(vm_out_path)        // 启动执行，并将结果写入 vm_out_path 文件

    println("\n==============================================")
    println(" 🚀 全链路编译与执行完美收官！")
    println("==============================================")
}