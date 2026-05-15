package compile
import std.console.*
import std.fs.*

// ==========================================
// 1. 数据结构定义：单词的“身份证”
// ==========================================
// 编译原理中，词法分析的产物叫做 Token（记号/单词流）
struct Token {
    public var lexeme: Int64              // 单词的类别编号。比如 0代表普通标识符，1代表数字，4代表关键字
    public var name: String               // 单词的字面值（实际长什么样）。比如 "int", "123", ">="
    public var line: UInt64               // 记录这个单词出现在代码的第几行，方便后面报错时定位
    
    public init(lexeme: Int64, name: String, line: UInt64) {
        this.lexeme = lexeme
        this.name = name
        this.line = line
    }
}

// ==========================================
// 2. 工具类：负责读取源代码文件
// ==========================================
class FileReader {
    private var file_path: String
    
    public init(file_path: String) {
        this.file_path = file_path
    }
    
    // 这个函数的核心作用是：把文件里的内容，变成程序可以一个一个遍历的“字符数组 (Array<Rune>)”
    public func get_program(): Array<Rune> {
        try {
            // readFrom 读出来的是底层字节流 (Array<UInt8>)
            let program_bytes = File.readFrom(this.file_path)
            // 准备一个同样大小的字符数组，用来装转换后的内容
            var program = Array<Rune>(program_bytes.size, { _ => r'0' })
            
            // 遍历字节，转成仓颉的字符类型 (Rune)
            for (i in 0..program_bytes.size) {
                program[i] = Rune(UInt32(program_bytes[i])) 
            }
            return program
        } catch (e: Exception) {
            println("Error: File doesn't exist or cannot be read! -> ${this.file_path}")
            return Array<Rune>(0, { _ => r'0' }) // 读文件失败就返回空数组
        }
    }
}

// ==========================================
// 3. 核心类：词法分析器（DFA 状态机）
// ==========================================
class Lexer {
    private var program: Array<Rune>      // 装着源代码所有字符的数组
    private var out_path: String          // 分析结果输出的文件路径
    private var line: UInt64 = 1          // 当前读到了第几行，初始为第 1 行
    private var is_error: Bool = false    // 标记整个分析过程中是否遇到过错误
    private var token_cnt: Int64 = 0      // 记录一共识别出了多少个有效单词
    private var pointer: Int64 = 0        // 【极其重要】探照灯指针！指着当前正在读取的字符位置
    
    // 初始化一个很大的数组，用来暂存识别出来的 Token（最多支持 10000 个单词）
    private var results: Array<Token> = Array<Token>(10000, { _ => Token(0, "", 0) })

    // 映射表：把数字编号翻译成人类能看懂的类别英文
    private let num2lexeme: Array<String> = ["ID", "NUM", "SYMBOL", "OP", "KEYWORD"]

    // 🚨 【实验硬性要求】：保留字表
    // 为什么一定要按字母 a-z 顺序排好？因为“折半查找（二分查找）”的前提是数组必须有序！
    private let keywords: Array<String> = [
        "break", "continue", "do", "else", "for", 
        "if", "int", "read", "return", "void", "while", "write"
    ]

    public init(program: Array<Rune>, out_path: String) {
        this.program = program
        this.out_path = out_path
    }

    // ==========================================
    // ⭐ 核心逻辑：执行词法分析的主循环
    // ==========================================
    public func run(): Array<Token> {
        // 只要指针还没指到文件末尾，就一直循环读下去
        while (pointer < program.size) {
            
            // 【状态 1：遇到空白符】空格、回车、换行、Tab，直接跳过
            if (is_empty(program[pointer])) {
                read_next() // 指针往后挪一格
                continue
            }
            
            // 【状态 2：遇到字母】可能是“关键字”，也可能是“普通变量名(标识符)”
            if (is_letter(program[pointer])) {         
                var id: String = String(program[pointer]) // 先把首字母记下来
                read_next()
                
                // 只要后面跟着的还是字母或数字，就一直拼接上去 (例如遇到: a, b, c, 1, 2)
                while (pointer < program.size) {
                    if (is_letter(program[pointer]) || is_digit(program[pointer])) {
                        id += String(program[pointer])
                        read_next()
                    } else {
                        // 读到了非字母和数字，说明这个单词读完了。
                        // 🚨 调用折半查找，去保留字表里对一对，看它是不是关键字
                        if (is_keyword_binary_search(word2low(id))) {
                            results[token_cnt] = Token(4, id, this.line) // 4号：关键字
                        } else {
                            results[token_cnt] = Token(0, id, this.line) // 0号：普通标识符
                        }
                        token_cnt++
                        break // 退出内层循环，继续去读下一个新单词
                    }
                }
                continue
            }
            
            // 【状态 3：遇到数字】识别整数
            if (is_digit(program[pointer])) {          
                var num: String = String(program[pointer])
                read_next()
                
                // 只要后面跟着的还是数字，就一直拼
                while (pointer < program.size) {
                    if (is_digit(program[pointer])) {
                        num += String(program[pointer])
                        read_next()
                    } else {
                        // 如果数字后面紧跟着字母（比如 123a），这是非法的，报错！
                        if (!is_letter(program[pointer]) && !is_slash(program[pointer])) {
                            results[token_cnt] = Token(1, num, this.line) // 1号：数字 NUM
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
            
            // 【状态 4：遇到单字符符号】比如分号、括号
            if (is_single_signal(program[pointer])) {  
                results[token_cnt] = Token(2, String(program[pointer]), this.line) // 2号：SYMBOL
                token_cnt++
                read_next()
                continue
            }
            
            // 【状态 5：遇到运算符】核心难点是“向前看 (Lookahead)”机制
            if (is_other_signal(program[pointer])) {   
                var op: String = String(program[pointer]) // 先记录第一个字符，比如 >
                read_next()
                // 向前看一眼，如果紧跟着的是 =，说明这是一个双字符运算符 >=
                if (pointer < program.size && program[pointer] == r'=') {        
                    op += String(r'=')
                    results[token_cnt] = Token(3, op, this.line) // 3号：运算符 OP
                    token_cnt++
                    read_next()
                } else {
                    // 如果后面不是 =，那说明只是个单字符运算符，比如单独的 >
                    results[token_cnt] = Token(2, op, this.line)
                    token_cnt++
                }
                continue
            }
            
            // 【状态 6：处理斜杠】可能是除号，也可能是多行注释 /*
            if (is_slash(program[pointer])) {          
                if (pointer + 1 < program.size) {
                    read_next()
                    if (program[pointer] == r'*') {    // 证实是多行注释 /*
                        while (pointer < program.size) {
                            read_next()
                            // 在注释里一直找，直到找到配对的 */
                            if (pointer + 1 < program.size && program[pointer] == r'*') {
                                read_next()
                                if (program[pointer] == r'/') {
                                    read_next() // 吞掉最后的斜杠，注释结束
                                    break
                                }
                            }
                        }
                    } else {                           // 只是普通的除号 /
                        if (is_empty(program[pointer]) || is_letter(program[pointer]) || is_digit(program[pointer])) {
                            results[token_cnt] = Token(2, "/", this.line)
                            token_cnt++
                        } else {
                            found_error(program[pointer])
                        }    
                    }
                } else {
                    // 文件末尾的最后一个字符是斜杠
                    results[token_cnt] = Token(2, "/", this.line)
                    token_cnt++
                }
                continue
            }
            
            // 【保底分支】所有条件都不满足，说明遇到了程序完全不认识的乱码符号
            found_error(program[pointer])            
            read_next()
        }
        
        if (!is_error) { println("Lexical analysis succeeds!\n") }
        else { println("Lexical analysis finished with errors!\n") }
        return results
    }

    // ==========================================
    // 工具方法：输出格式化
    // ==========================================
    public func out_string(i: Int64): String {
        var str: String
        // 关键字为了排版好看，单独做个格式化
        if (results[i].lexeme == 4) {
            str = (word2low(results[i].name) + "\t\t" + results[i].name)
        } else {
            str = (num2lexeme[results[i].lexeme] + "\t\t" + results[i].name)
        }
        return str
    }

    public func show() {                    
        println("Token_Category\tToken")
        println("------------------------")
        for (i in 0..token_cnt) {
            println(out_string(i))
        }
    }

    public func write2file() {
        let file = File.create(out_path)
        file.write(("Token_Category\tToken\n").toArray())
        for (i in 0..token_cnt) {
            file.write((out_string(i) + "\n").toArray())
        }
        println("\nLexical analysis results write to file ${out_path} !\n")
        file.close()
    }

    // ==========================================
    // 工具方法：指针移动与报错
    // ==========================================
    private func read_next() {
        // 如果当前遇到的是换行符 (ASCII 码 10)，就把行号 + 1
        if (pointer < program.size && UInt32(program[pointer]) == 10) { 
            this.line++                               
        }
        // 指针向后走一步
        this.pointer++
    }

    private func found_error(ch: Rune) {               
        this.is_error = true
        println("Found error in line ${this.line} : ${ch}")
    }

    // ==========================================
    // ⭐ 【高分关键】折半查找 (Binary Search) 算法
    // ==========================================
    private func is_keyword_binary_search(str: String): Bool {
        var left: Int64 = 0
        var right: Int64 = keywords.size - 1

        // 当左边界还没超过右边界时，持续查找
        while (left <= right) {
            // 计算中间位置的索引
            let mid: Int64 = left + (right - left) / 2
            let mid_val: String = keywords[mid]

            // 和中间的值进行比对
            if (mid_val == str) {
                return true        // 运气好，直接和中间的值一样，说明是保留字
            } else if (mid_val < str) {
                left = mid + 1     // 字典序小于目标，说明目标在右半边，把左边界挪过来
            } else {
                right = mid - 1    // 字典序大于目标，说明目标在左半边，把右边界挪过去
            }
        }
        return false               // 找完了整个数组都没找到，说明只是普通的变量名
    }

    // ==========================================
    // 字符判断底层工具（通过 ASCII 码或字符范围判断）
    // ==========================================
    private func word2low(str: String): String {
        var res = ""
        let bytes = str.toArray() // 拿到字符串底层的字节数组
        for (i in 0..bytes.size) {
            let b = bytes[i]
            // 如果是大写字母 A(65) 到 Z(90)
            if (b >= 65 && b <= 90) { 
                res += String(Rune(UInt32(b) + 32)) // ASCII码加32就是对应的小写字母
            } else {
                res += String(Rune(UInt32(b)))
            }
        }
        return res
    }

    private func is_empty(ch: Rune): Bool {
        return UInt32(ch) == 10 || UInt32(ch) == 13 || UInt32(ch) == 32 || UInt32(ch) == 9
    }
    private func is_letter(ch: Rune): Bool {
        return (ch >= r'A' && ch <= r'Z') || (ch >= r'a' && ch <= r'z')
    }
    private func is_digit(ch: Rune): Bool {
        return ch >= r'0' && ch <= r'9'
    }
    private func is_single_signal(ch: Rune): Bool {
        return ch == r';' || ch == r',' || ch == r'(' || ch == r')' || 
               ch == r'[' || ch == r']' || ch == r'{' || ch == r'}' || 
               ch == r'+' || ch == r'-' || ch == r'*'
    }
    private func is_other_signal(ch: Rune): Bool {
        return ch == r'>' || ch == r'<' || ch == r'!' || ch == r'='
    }
    private func is_slash(ch: Rune): Bool {
        return ch == r'/'
    }
}

// ==============================================
// 🚀 程序入口 (Main 函数)
// args: 接收命令行传入的参数（即使不用也要写上，防止重载冲突）
// ==============================================
main(args: Array<String>): Int64 {
    // 1. 定义源文件和输出文件的名字
    let input_file = "input.txt"  
    let output_file = "output.txt"

    println("Start Lexical Analysis...")
    
    // 2. 读取源文件
    let reader = FileReader(input_file)
    let program_runes = reader.get_program()
    
    // 如果文件是空的或者没找到，程序安全退出
    if (program_runes.size == 0) {
        println("Exiting...")
        return -1 
    }

    // 3. 将字符流喂给词法分析器，开始工作
    let my_lexer = Lexer(program_runes, output_file)
    my_lexer.run()
    
    // 4. 展示结果，并把结果存盘
    my_lexer.show()
    my_lexer.write2file()
    
    // 0 代表程序正常执行结束
    return 0
}