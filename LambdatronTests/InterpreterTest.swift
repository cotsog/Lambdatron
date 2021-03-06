//
//  InterpreterTest.swift
//  Lambdatron
//
//  Created by Austin Zheng on 1/16/15.
//  Copyright (c) 2015 Austin Zheng. All rights reserved.
//

import Foundation
import XCTest
@testable import Lambdatron

extension Value {
  var asSeq : SeqType? {
    if case let .Seq(value) = self {
      return value
    }
    return nil
  }
}

let EmptyNode = Empty()

/// Convenience function: given a bunch of Values, return a list.
func listWithItems(items: Value...) -> Value {
  return .Seq(items.count == 0 ? Empty() : ContiguousList(items))
}

/// Convenience functions: given a bunch of Values, return a vector.
func vectorWithItems(items: Value...) -> Value {
  return .Vector(items)
}

/// Convenience function: given a bunch of Value key-value pairs, return a map.
func mapWithItems(items: (Value, Value)...) -> Value {
  if items.count == 0 {
    return .Map([:])
  }
  var buffer : MapType = [:]
  for (key, value) in items {
    buffer[key] = value
  }
  return .Map(buffer)
}

/// An abstract superclass intended for various interpreter tests.
class InterpreterTest : XCTestCase {
  var interpreter = Interpreter()

  func keyword(name: String, namespace: String? = nil) -> InternedKeyword {
    return InternedKeyword(name, namespace: namespace, ivs: interpreter.internStore)
  }

  func symbol(name: String, namespace: String? = nil) -> InternedSymbol {
    return InternedSymbol(name, namespace: namespace, ivs: interpreter.internStore)
  }

  override func setUp() {
    super.setUp()
    interpreter.reset()
    clearOutputBuffer()
    interpreter.writeOutput = writeToBuffer
  }

  override func tearDown() {
    super.tearDown()
    // Reset the interpreter
    clearOutputBuffer()
    interpreter.writeOutput = {
      print($0)
    }
  }

  // Run some input, expecting no errors.
  func runCode(input: String) -> Value? {
    let result = interpreter.evaluate(input)
    switch result {
    case let .Success(s):
      return s
    case let .ReadFailure(err):
      XCTFail("runCode did not successfully evaluate the input \"\(input)\"; read error: \(err.description)")
    case let .EvalFailure(err):
      XCTFail("runCode did not successfully evaluate the input \"\(input)\"; eval error: \(err.description)")
    }
    return nil
  }

  /// Given an input string, lex, parse, and reader-expand it and compare to an expected String output.
  func expect(input: String, shouldExpandTo output: String) {
    let context = interpreter.currentNamespace
    let lexed = lex(input)
    switch lexed {
    case let .Just(lexed):
      let parsed = parse(lexed, context)
      switch parsed {
      case let .Just(parsed):
        let expanded = parsed.expand(context)
        switch expanded {
        case let .Success(expanded):
          let actualOutput = expanded.describe(context).rawStringValue
          XCTAssert(actualOutput == output, "expected: \(output), got: \(actualOutput)")
        case let .Failure(f):
          XCTFail("reader macro expansion error: \(f.description)")
        }
      case .Error:
        XCTFail("parser error")
      }
    case .Error:
      XCTFail("lexer error")
    }
  }

  /// Given an input string, evaluate it and compare the output to an expected Value output.
  func expectThat(input: String, shouldEvalTo expected: Value) {
    let result = interpreter.evaluate(input)
    switch result {
    case let .Success(actual):
      let isEqual : Bool = (expected == actual)
      XCTAssert(isEqual /*expected == actual*/, "expected: \(expected), got: \(actual)")
    case let .ReadFailure(f):
      XCTFail("read error: \(f.description)")
    case let .EvalFailure(f):
      XCTFail("evaluation error: \(f.description)")
    }
  }

  /// Given an input string, evaluate it and expect a seq. Then compare the items in the seq to a given set of items.
  /// This test does not check the order of items, only that they all appear exactly once.
  func expectThat(input: String, shouldEvalToContain item: Value, _ expected: Value...) {
    // Put the items in a set
    let expectedItems : Set<Value> = Set(expected + [item])

    let result = interpreter.evaluate(input)
    switch result {
    case let .Success(actual):
      if let actual = actual.asSeq {
        var actualItems = Set<Value>()
        for item in SeqIterator(actual) {
          if case let .Just(item) = item {
            actualItems.insert(item)
          } else {
            fatalError("Test is in a bad state")
          }
        }
        XCTAssert(expectedItems == actualItems, "actual and expected items didn't match:\nexpected \(expectedItems)\ngot \(actualItems)")
      }
      else {
        XCTFail("expected a sequence from expectThat:shouldEvalToContain:, got \(actual)")
      }
    case let .ReadFailure(f):
      XCTFail("read error: \(f.description)")
    case let .EvalFailure(f):
      XCTFail("evaluation error: \(f.description)")
    }
  }

  /// Given an input string and a string describing an expected form, evaluate both and compare for equality.
  func expectThat(input: String, shouldEvalTo form: String) {
    // Evaluate the test form first
    let actual = interpreter.evaluate(input)
    switch actual {
    case let .Success(actual):
      // Then evaluate the reference form
      let expected = interpreter.evaluate(form)
      switch expected {
      case let .Success(expected):
        XCTAssert(expected == actual, "expected: \(expected), got: \(actual)")
      default:
        XCTFail("reference form failed to evaluate successfully; this is a problem with the unit test")
      }
    case let .ReadFailure(f):
      XCTFail("read error: \(f.description)")
    case let .EvalFailure(f):
      XCTFail("evaluation error: \(f.description)")
    }
  }

  /// Given an input string, evaluate it and expect a particular read failure.
  func expectThat(input: String, shouldFailAs expected: ReadError.ReadErrorType) {
    let result = interpreter.evaluate(input)
    switch result {
    case let .Success(s):
      XCTFail("evaluation unexpectedly succeeded; result: \(s.description)")
    case let .ReadFailure(actual):
      let expectedName = expected.rawValue
      let actualName = actual.error.rawValue
      XCTAssert(expected == actual.error, "expected: \(expectedName), got: \(actualName)")
    case let .EvalFailure(err):
      XCTFail("unexpected evaluation error: \(err.description)")
    }
  }

  /// Given an input string, evaluate it and expect a particular evaluation failure.
  func expectThat(input: String, shouldFailAs expected: EvalError.EvalErrorType) {
    let result = interpreter.evaluate(input)
    switch result {
    case let .Success(s):
      XCTFail("evaluation unexpectedly succeeded; result: \(s.description)")
    case let .ReadFailure(err):
      XCTFail("unexpected read error: \(err.description)")
    case let .EvalFailure(actual):
      let expectedName = expected.rawValue
      let actualName = actual.error.rawValue
      XCTAssert(expected == actual.error, "expected: \(expectedName), got: \(actualName)")
    }
  }

  /// Given an input string, evaluate it and expect an invalid argument error.
  func expectInvalidArgumentErrorFrom(input: String) {
    expectThat(input, shouldFailAs: .InvalidArgumentError)
  }

  /// Given an input string, evaluate it and expect an arity error.
  func expectArityErrorFrom(input: String) {
    expectThat(input, shouldFailAs: .ArityError)
  }

  // Buffer functionality
  /// A buffer capturing output from the interpreter.
  var outputBuffer : String = ""

  /// Clear the output buffer.
  func clearOutputBuffer() {
    outputBuffer = ""
  }

  /// Write to the output buffer. Intended to be passed to the interpreter for use in testing println and side effects.
  func writeToBuffer(item: String) {
    outputBuffer += item
  }

  /// Compare an input string to the contents of the output buffer.
  func expectOutputBuffer(toBe expected: String) {
    XCTAssert(outputBuffer == expected, "expected: \(expected), got: \(outputBuffer)")
  }

  /// Test whether the output buffer is empty or not.
  func expectEmptyOutputBuffer() {
    XCTAssert(outputBuffer.isEmpty, "Output buffer was not empty; got: \(outputBuffer)")
  }

  /// Test whether or not a ListType matches the items in a collection.
  func expectList<T : SequenceType where T.Generator.Element == Value>(list: SeqType, toMatch match: T) {
    var listGenerator = SeqIterator(list).generate()
    var matchGenerator = match.generate()

    while true {
      let thisListItem = listGenerator.next()
      let thisMatchItem = matchGenerator.next()
      if thisMatchItem == nil && thisListItem == nil {
        // Reached the end of the lists, and both match
        return
      }
      else if thisMatchItem == nil || thisListItem == nil {
        // Reached the end of only one of the lists; length mismatch
        XCTFail("List did not match expected collection \(match); length mismatch")
        return
      }
      switch thisListItem! {
      case let .Just(value):
        if value != thisMatchItem! {
          XCTFail("Item mismatch: expected: \(thisMatchItem!), got: \(value)")
          return
        }
        continue
      case let .Error(err):
        XCTFail("Evaluation error while iterating through list: \(err.description)")
        return
      }
    }
  }
}
