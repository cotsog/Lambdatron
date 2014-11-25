//
//  lexer.swift
//  Lambdatron
//
//  Created by Austin Zheng on 11/12/14.
//  Copyright (c) 2014 Austin Zheng. All rights reserved.
//

import Foundation

enum LexResult {
  case Success([LexToken])
  case Failure(LexError)
}

enum LexError : Printable {
  case InvalidEscapeSequenceError
  case NonTerminatedStringError
  
  var description : String {
    switch self {
    case .InvalidEscapeSequenceError: return "invalid or unfinished escape sequence"
    case .NonTerminatedStringError: return "strings weren't all terminated by end of input"
    }
  }
}

/// Tokens that come out of the lex() function
enum LexToken : Printable {
  case LeftParentheses            // left parentheses '('
  case RightParentheses           // right parentheses ')'
  case LeftSquareBracket          // left square bracket '['
  case RightSquareBracket         // right square bracket ']'
  case Quote                      // single quote '''
  case NilLiteral                 // nil
  case StringLiteral(String)      // string (denoted by double quotes)
  case Number(Double)             // floating-point number
  case Boolean(Bool)              // boolean (true or false)
  case Keyword(String)            // keyword (prefixed by ':')
  case Identifier(String)         // unknown identifier (function or variable name)
  case Special(SpecialForm)       // a special form (e.g. 'quote')
  
  var description : String {
    switch self {
    case .LeftParentheses: return "LeftP <(>"
    case .RightParentheses: return "RightP <)>"
    case .LeftSquareBracket: return "LeftSqBr <[>"
    case .RightSquareBracket: return "RightSqBr <]>"
    case .Quote: return "Quote <'>"
    case let .StringLiteral(x): return "String \"\(x)\""
    case let .NilLiteral: return "Nil"
    case let .Number(x): return "Number <\(x)>"
    case let .Boolean(x): return "Boolean <\(x)>"
    case let .Keyword(x): return "Keyword \(x)"
    case let .Identifier(x): return "Identifier <\(x)>"
    case let .Special(x): return "Special <\(x.rawValue)>"
    }
  }
}

func processEscape(sequence: String) -> String? {
  switch sequence {
    case "r": return "\r"
    case "n": return "\n"
    case "t": return "\t"
    case "\"": return "\""
    case "\\": return "\\"
  default: return nil
  }
}

/// Given a raw input (as a string), lex it into individual tokens.
func lex(raw: String) -> LexResult {
  enum RawLexToken {
    case LeftP
    case RightP
    case LeftSqBr
    case RightSqBr
    case Quote
    case StringLiteral(String)
    case Unknown(String)
  }
  
  enum State {
    case Normal, String, Comment
  }
  
  let wsSet = NSCharacterSet.whitespaceAndNewlineCharacterSet()
  let nlSet = NSCharacterSet.newlineCharacterSet()
  
  // PHASE 1: raw lex
  var rawTokenBuffer : [RawLexToken] = []
  
  // currentToken can only contain either a StringLiteral or an Unknown token
  var currentToken : NSMutableString = ""
  
  /// Helper function - flush the current-in-progress token to the token buffer
  func flushTokenToBuffer() {
    if currentToken.length > 0 {
      rawTokenBuffer.append(.Unknown(currentToken))
    }
    currentToken = ""
  }
  
  var state : State = .Normal
  
  var skipCount = 0
  let rawAsNSString = NSString(string: raw)
  for (idx, char) in enumerate(raw) {
    if skipCount > 0 {
      // Multi-character sequence detected previously. Don't run.
      skipCount--
      continue
    }
    
    // Horrible, horrible hacks to turn a Character into a unichar
    var tChar = NSString(string: String(char)).characterAtIndex(0)
    
    switch state {
    case .Normal:
      switch char {
      case ";":
        flushTokenToBuffer()                          // User starting a comment with a ;
        state = .Comment
      case "\"":
        flushTokenToBuffer()                          // User starting a string with an opening "
        state = .String
      case "(":
        flushTokenToBuffer()                          // Left parentheses
        rawTokenBuffer.append(.LeftP)
      case ")":
        flushTokenToBuffer()                          // Right parentheses
        rawTokenBuffer.append(.RightP)
      case "[":
        flushTokenToBuffer()                          // Left square bracket
        rawTokenBuffer.append(.LeftSqBr)
      case "]":
        flushTokenToBuffer()                          // Right square bracket
        rawTokenBuffer.append(.RightSqBr)
      case "'":
        flushTokenToBuffer()                          // Single quote
        rawTokenBuffer.append(.Quote)
      case _ where wsSet.characterIsMember(tChar):
        flushTokenToBuffer()                          // Whitespace/newline
      default:
        currentToken.appendString(String(char))       // Any other valid character
      }
    case .String:
      // Currently lexing characters forming a string literal
      if char == "\"" {
        // User ended the string with a closing "
        rawTokenBuffer.append(.StringLiteral(currentToken))
        currentToken = ""
        state = .Normal
      }
      else if (char == "\\") {
        if idx == rawAsNSString.length - 1 {
          // An escape character cannot be the last character in the input
          return .Failure(.InvalidEscapeSequenceError)
        }
        skipCount = 1
        // Get the next character
        let nextChar = rawAsNSString.substringWithRange(NSRange(location: idx+1, length: 1))
        if let escapeSeq = processEscape(nextChar) {
          currentToken.appendString(escapeSeq)
        }
        else {
          return .Failure(.InvalidEscapeSequenceError)
        }
      }
      else {
        // Any other token gets added to the buffer as a literal
        currentToken.appendString(String(char))
      }
    case .Comment:
      // Comments are completely ignored by the lexer, and are terminated by a newline
      switch char {
      case _ where nlSet.characterIsMember(tChar):
        // End of string
        state = .Normal
      default: break
      }
    }
  }
  
  if state == .String {
    // This is bad; a string was left dangling
    return .Failure(.NonTerminatedStringError)
  }
  // If there's another token left, flush it
  flushTokenToBuffer()
  
  // PHASE 2: identify 'unknowns'
  var tokenBuffer : [LexToken] = []
  for rawToken in rawTokenBuffer {
    switch rawToken {
    case .LeftP: tokenBuffer.append(.LeftParentheses)
    case .RightP: tokenBuffer.append(.RightParentheses)
    case .LeftSqBr: tokenBuffer.append(.LeftSquareBracket)
    case .RightSqBr: tokenBuffer.append(.RightSquareBracket)
    case .Quote: tokenBuffer.append(.Quote)
    case let .StringLiteral(sl): tokenBuffer.append(.StringLiteral(sl))
    case let .Unknown(u):
      // Possible type inference bug? Without the String() constructor it fails, even though 'u' is already a string
      let tValue = NSString(string: String(u))
      // Figure out what to do with the token
      if let specialForm = SpecialForm(rawValue: tValue) {
        // Special form
        tokenBuffer.append(.Special(specialForm))
      }
      else if tValue.characterAtIndex(0) == UInt16(UnicodeScalar(":").value) && tValue.length > 1 {
        // This is a keyword (starts with ":" and has at least one other character)
        tokenBuffer.append(.Keyword(u))
      }
      else if tValue == "nil" {
        // Literal nil
        tokenBuffer.append(.NilLiteral)
      }
      else if tValue == "false" {
        // Literal bool
        tokenBuffer.append(.Boolean(false))
      }
      else if tValue == "true" {
        // Literal bool
        tokenBuffer.append(.Boolean(true))
      }
      else if let numberToken = buildNumberFromString(u) {
        // Literal number
        tokenBuffer.append(numberToken)
      }
      else {
        // Identifier
        tokenBuffer.append(.Identifier(u))
      }
    }
  }
  
  return .Success(tokenBuffer)
}

func buildNumberFromString(str: String) -> LexToken? {
  // The classic 'isNumber()' function.
  // TODO: Replace this with a REAL number parser
  let nf = NSNumberFormatter()
  nf.numberStyle = NSNumberFormatterStyle.DecimalStyle
  let number = nf.numberFromString(str)
  if let actualNumber = number {
    let doubleVal = actualNumber.doubleValue
    return LexToken.Number(actualNumber.doubleValue)
  }
  return nil
}
