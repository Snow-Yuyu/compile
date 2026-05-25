package compile
import std.fs.*
import std.console.*
import std.collection.*

struct Token {
    public var lexeme: Int64              // 0:ID, 1:NUM, 2:界符/符号, 3:操作符, 4:关键字
    public var name: String               // 单词的字面值
    public var line: UInt64               // 记录单词出现位置
    public init(lexeme: Int64, name: String, line: UInt64) {
        this.lexeme = lexeme
        this.name = name
        this.line = line
    }
}

class FileReader {
    private var file_path: String
    
    public init(file_path: String) {
        this.file_path = file_path
    }
    
    public func get_program(): Array<Rune> {
        try {
            let program_bytes = File.readFrom(this.file_path)
            var program = Array<Rune>(program_bytes.size, { _ => r'0' })
            for (i in 0..program_bytes.size) {
                program[i] = Rune(UInt32(program_bytes[i])) 
            }
            return program
        } catch (e: Exception) {
            println("错误：文件不存在或无法读取！ -> ${this.file_path}")
            return Array<Rune>(0, { _ => r'0' })
        }
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

    private let keywords: Array<String> = [
        "as", "break", "case", "const", "continue", "do", "else", "for", 
        "from", "func", "if", "in", "int", "let", "main", "match", 
        "read", "return", "var", "void", "where", "while", "write"
    ]

    public init(program: Array<Rune>, out_path: String) {
        this.program = program
        this.out_path = out_path
    }

    public func run(): Array<Token> {
        while (pointer < program.size) {
            if (is_empty(program[pointer])) {
                read_next()
                continue
            }
            if (is_letter_or_underscore(program[pointer])) { 
                var id: String = String(program[pointer])
                read_next()
                while (pointer < program.size) {
                    if (is_letter_or_underscore(program[pointer]) || is_digit(program[pointer])) {
                        id += String(program[pointer])
                        read_next()
                    } else {
                        if (is_keyword_binary_search(id)) {
                            results[token_cnt] = Token(4, id, this.line) 
                        } else {
                            results[token_cnt] = Token(0, id, this.line) 
                        }
                        token_cnt++
                        break
                    }
                }
                continue
            }
            if (is_digit(program[pointer])) {          
                var num: String = String(program[pointer])
                read_next()
                while (pointer < program.size) {
                    if (is_digit(program[pointer])) {
                        num += String(program[pointer])
                        read_next()
                    } else {
                        if (!is_letter_or_underscore(program[pointer])) {
                            results[token_cnt] = Token(1, num, this.line) 
                            token_cnt++
                            break
                        } else {
                            found_error(program[pointer])
                            break
                        }
                    }
                }
                continue
            }
            if (is_single_signal(program[pointer])) {  
                results[token_cnt] = Token(2, String(program[pointer]), this.line)
                token_cnt++
                read_next()
                continue
            }
            if (is_other_signal(program[pointer])) {   
                var op: String = String(program[pointer])
                read_next()
                if (pointer < program.size && program[pointer] == r'=') {        
                    op += String(r'=')
                    results[token_cnt] = Token(3, op, this.line)
                    token_cnt++
                    read_next()
                } else {
                    results[token_cnt] = Token(3, op, this.line) 
                    token_cnt++
                }
                continue
            }
            if (is_slash(program[pointer])) {          
                if (pointer + 1 < program.size) {
                    read_next() 
                    if (pointer < program.size && program[pointer] == r'*') {    
                        while (pointer < program.size) {
                            read_next()
                            if (pointer + 1 < program.size && program[pointer] == r'*') {
                                read_next()
                                if (program[pointer] == r'/') {
                                    read_next() 
                                    break
                                }
                            }
                        }
                    } else if (pointer < program.size && program[pointer] == r'/') { 
                        while (pointer < program.size) {
                            read_next()
                            if (pointer < program.size && UInt32(program[pointer]) == 10) {
                                read_next()
                                break
                            }
                        }
                    } else {                           
                        results[token_cnt] = Token(3, "/", this.line)
                        token_cnt++
                    }
                } else {
                    results[token_cnt] = Token(3, "/", this.line)
                    token_cnt++
                    read_next()
                }
                continue
            }
            found_error(program[pointer])            
            read_next()
        }
        if (!is_error) { 
            println("\n[Lexer] 词法分析成功！") 
        } else { 
            println("\n[Lexer] 词法分析过程中发现错误！") 
        }
        return results
    }

    public func out_string(i: Int64): String {
        var str: String
        if (results[i].lexeme == 0 || results[i].lexeme == 1) {
            str = (num2lexeme[results[i].lexeme] + "\t\t" + results[i].name)
        } else {
            str = (results[i].name + "\t\t" + results[i].name)
        }
        return str
    }

    public func writetofile() {
        let targetPath = Path(out_path)
        if (exists(targetPath)) { remove(targetPath) }
        let file = File.create(out_path)
        file.write(("单词类别\t单词值\n").toArray())
        for (i in 0..token_cnt) {
            file.write((out_string(i) + "\n").toArray())
        }
        println("  └─ 词法分析结果已写入文件：${out_path}")
        file.close()
    }

    private func read_next() {
        if (pointer < program.size && UInt32(program[pointer]) == 10) { 
            this.line++                               
        }
        this.pointer++
    }

    private func found_error(ch: Rune) {               
        this.is_error = true
        println("第 ${this.line} 行有词法错误：未识别的字符 '${ch}'")
    }

    private func is_keyword_binary_search(str: String): Bool {
        var left: Int64 = 0
        var right: Int64 = keywords.size - 1
        while (left <= right) {
            let mid: Int64 = left + (right - left) / 2
            let mid_val: String = keywords[mid]
            if (mid_val == str) { return true } 
            else if (mid_val < str) { left = mid + 1 } 
            else { right = mid - 1 }
        }
        return false   
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
    let lex_out_path = "D:/Astudy/code/compile/token_out.txt"   
    let parse_out_path = "D:/Astudy/code/compile/pcode_out.txt" 

    println("==============================================")
    println("         编译前端流水线联调启动               ")
    println("==============================================")

    let reader = FileReader(src_path)
    let src_runes = reader.get_program()
    if (src_runes.size == 0) { return }

    var myLexer = Lexer(src_runes, lex_out_path)
    let tokens_raw = myLexer.run()
    myLexer.writetofile()

    // 智能清点有效 Token 长度，防止 10000 数组空间的尾部空结构体污染 Parser 计数
    var valid_token_count: Int64 = 0
    for (i in 0..10000) {
        if (tokens_raw[i].line == 0) {
            break 
        }
        valid_token_count++
    }

    var precise_tokens = Array<Token>(valid_token_count, { i => tokens_raw[i] })
    println("  └─ ✓ 成功在主函数内部清点出有效 Token 数量: ${valid_token_count} 个\n")

    println("[Parser] 正在启动语法与语义分析器...")
    var myParser = parser2(precise_tokens, valid_token_count, parse_out_path)
    myParser.run()
    println("==============================================")
}