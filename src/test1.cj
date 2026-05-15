package compile
import std.fs.*
import std.console.*

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

// 读取源代码文件
class FileReader {
    private var file_path: String
    
    public init(file_path: String) {
        this.file_path = file_path
    }
    
    // 从文件读取内容，转换成程序可遍历的字符数组
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

// 词法分析器（DFA 状态机）
class Lexer {
    private var program: Array<Rune>      // 源代码所有字符
    private var out_path: String          // 结果输出的文件路径
    private var line: UInt64 = 1          // 当前读到了第几行
    private var is_error: Bool = false    // 分析过程中是否遇到过错误
    private var token_cnt: Int64 = 0      // 一共识别出了多少个有效单词
    private var pointer: Int64 = 0        // 当前正在读取的字符位置
    
    // 暂存识别出来的 Token
    private var results: Array<Token> = Array<Token>(10000, { _ => Token(0, "", 0) })

    // 映射表 (ID 和 NUM 需要输出代号，其他的直接输出自身)
    private let num2lexeme: Array<String> = ["ID", "NUM", "SYMBOL", "OP", "KEYWORD"]

    // 🚨 严格依据 PPT 补充的关键字表（必须严格按字母字典序排列，用于二分查找）
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
            
            // 【状态 1：遇到空白符】直接跳过
            if (is_empty(program[pointer])) {
                read_next()
                continue
            }
            
            // 【状态 2：遇到字母或下划线】标识符或关键字
            if (is_letter_or_underscore(program[pointer])) {         
                var id: String = String(program[pointer])
                read_next()
                
                // 后面跟着的是字母、数字或下划线，一直拼接
                while (pointer < program.size) {
                    if (is_letter_or_underscore(program[pointer]) || is_digit(program[pointer])) {
                        id += String(program[pointer])
                        read_next()
                    } else {
                        // 🚨 严格区分大小写，直接将 id 传入折半查找（去掉了 wordtolow）
                        if (is_keyword_binary_search(id)) {
                            results[token_cnt] = Token(4, id, this.line) // 关键字
                        } else {
                            results[token_cnt] = Token(0, id, this.line) // 普通标识符
                        }
                        token_cnt++
                        break
                    }
                }
                continue
            }
            
            // 【状态 3：遇到数字】识别无符号整数
            if (is_digit(program[pointer])) {          
                var num: String = String(program[pointer])
                read_next()
                
                while (pointer < program.size) {
                    if (is_digit(program[pointer])) {
                        num += String(program[pointer])
                        read_next()
                    } else {
                        // 识别到字母报错（如 123a 非法）
                        if (!is_letter_or_underscore(program[pointer])) {
                            results[token_cnt] = Token(1, num, this.line) // 数字 NUM
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
            
            // 【状态 4：遇到单字符符号】
            if (is_single_signal(program[pointer])) {  
                results[token_cnt] = Token(2, String(program[pointer]), this.line)
                token_cnt++
                read_next()
                continue
            }
            
            // 【状态 5：遇到多字符可能性的操作符或界符】 (>, <, =, !, .)
            if (is_other_signal(program[pointer])) {   
                var op: String = String(program[pointer])
                read_next()
                
                // 🚨 补充处理轻量级仓颉特有的区间界符：.. 和 ..=
                if (op == ".") {
                    if (pointer < program.size && program[pointer] == r'.') {
                        op += "."
                        read_next() // 吞掉第二个点
                        if (pointer < program.size && program[pointer] == r'=') {
                            op += "="
                            read_next() // 吞掉等于号，变成 ..=
                        }
                        results[token_cnt] = Token(2, op, this.line)
                        token_cnt++
                        continue
                    } else {
                        results[token_cnt] = Token(2, op, this.line) // 单个点
                        token_cnt++
                        continue
                    }
                }

                // 处理双字符 >=, <=, !=, ==
                if (pointer < program.size && program[pointer] == r'=') {        
                    op += String(r'=')
                    results[token_cnt] = Token(3, op, this.line)
                    token_cnt++
                    read_next()
                } else {
                    results[token_cnt] = Token(2, op, this.line)
                    token_cnt++
                }
                continue
            }
            
            // 【状态 6：处理斜杠】可能是除号 /，单行注释 //，多行注释 /*
            if (is_slash(program[pointer])) {          
                if (pointer + 1 < program.size) {
                    read_next() // 吞掉第一个 /
                    
                    if (pointer < program.size && program[pointer] == r'*') {    
                        // 多行注释 /* ... */
                        while (pointer < program.size) {
                            read_next()
                            if (pointer + 1 < program.size && program[pointer] == r'*') {
                                read_next()
                                if (program[pointer] == r'/') {
                                    read_next() // 吞掉最后的 /
                                    break
                                }
                            }
                        }
                    } else if (pointer < program.size && program[pointer] == r'/') { 
                        // 🚨 补充逻辑：单行注释 //
                        while (pointer < program.size) {
                            read_next()
                            // 一直读到换行符结束
                            if (pointer < program.size && UInt32(program[pointer]) == 10) {
                                read_next()
                                break
                            }
                        }
                    } else {                           
                        // 普通除号 /
                        results[token_cnt] = Token(3, "/", this.line)
                        token_cnt++
                    }
                } else {
                    // 文件末尾最后一个字符是斜杠
                    results[token_cnt] = Token(3, "/", this.line)
                    token_cnt++
                    read_next()
                }
                continue
            }
            
            // 所有条件都不满足，非法字符
            found_error(program[pointer])            
            read_next()
        }
        
        if (!is_error) { 
            println("\n词法分析成功！\n") 
        } else { 
            println("\nLexical analysis fails!\n") 
        }
        return results
    }

    // 格式化输出 (对照 PPT 的示例要求)
    public func out_string(i: Int64): String {
        var str: String
        // 如果是普通标识符(0)或数字(1)，输出 ID/NUM 加上值
        if (results[i].lexeme == 0 || results[i].lexeme == 1) {
            str = (num2lexeme[results[i].lexeme] + "\t\t" + results[i].name)
        } else {
            // 如果是关键字、界符、运算符，左右两侧都输出单词自身 (如 `main  main` 或 `(  (`)
            str = (results[i].name + "\t\t" + results[i].name)
        }
        return str
    }

    public func show() {                    
        println("单词类别\t单词值")
        for (i in 0..token_cnt) {
            println(out_string(i))
        }
    }

    public func writetofile() {
        let file = File.create(out_path)
        file.write(("单词类别\t单词值\n").toArray())
        for (i in 0..token_cnt) {
            file.write((out_string(i) + "\n").toArray())
        }
        println("\n词法分析结果已写入文件：${out_path} !\n")
        file.close()
    }

    // 指针移动与行号增加
    private func read_next() {
        if (pointer < program.size && UInt32(program[pointer]) == 10) { 
            this.line++                               
        }
        this.pointer++
    }

    // 🚨 按照示例图输出报错信息
    private func found_error(ch: Rune) {               
        this.is_error = true
        println("第 ${this.line} 行有错误： ${ch}")
    }

    // 折半查找关键字
    private func is_keyword_binary_search(str: String): Bool {
        var left: Int64 = 0
        var right: Int64 = keywords.size - 1

        while (left <= right) {
            let mid: Int64 = left + (right - left) / 2
            let mid_val: String = keywords[mid]

            if (mid_val == str) {
                return true 
            } else if (mid_val < str) {
                left = mid + 1 
            } else {
                right = mid - 1 
            }
        }
        return false   
    }

    private func is_empty(ch: Rune): Bool {
        return UInt32(ch) == 10 || UInt32(ch) == 13 || UInt32(ch) == 32 || UInt32(ch) == 9
    }
    
    // 🚨 补充对下划线的支持
    private func is_letter_or_underscore(ch: Rune): Bool {
        return (ch >= r'A' && ch <= r'Z') || (ch >= r'a' && ch <= r'z') || ch == r'_'
    }
    
    private func is_digit(ch: Rune): Bool {
        return ch >= r'0' && ch <= r'9'
    }
    
    private func is_single_signal(ch: Rune): Bool {
        // 🚨 补充了冒号 :
        return ch == r';' || ch == r':' || ch == r',' || ch == r'(' || ch == r')' || 
               ch == r'[' || ch == r']' || ch == r'{' || ch == r'}' || 
               ch == r'+' || ch == r'-' || ch == r'*'
    }
    
    private func is_other_signal(ch: Rune): Bool {
        // 🚨 补充了点号 . (为了支持 .. 和 ..=)
        return ch == r'>' || ch == r'<' || ch == r'!' || ch == r'=' || ch == r'.'
    }
    
    private func is_slash(ch: Rune): Bool {
        return ch == r'/'
    }
}

main(): Int64 {
    let input_file = "test1.txt"  
    let output_file = "output.txt"

    println("开始词法分析...")
    
    let reader = FileReader(input_file)
    let program_runes = reader.get_program()
    
    if (program_runes.size == 0) {
        println("退出程序...")
        return -1 
    }

    let my_lexer = Lexer(program_runes, output_file)
    my_lexer.run()
    
    my_lexer.show()
    my_lexer.writetofile()
    
    return 0
}