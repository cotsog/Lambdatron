//
//  util.swift
//  Lambdatron
//
//  Created by Austin Zheng on 12/30/14.
//  Copyright (c) 2014 Austin Zheng. All rights reserved.
//

import Foundation

/// Force the program to exit if something is wrong. This function is intended only to represent bugs in the Lambdatron
/// interpreter and should never be invoked at runtime; if it is invoked there is a bug in the interpreter code.
@noreturn func internalError(@autoclosure message: () -> String) {
  print("Internal error: \(message())")
  exit(EXIT_FAILURE)
}


// MARK: Numbers

/// An enum wrapping one of several numerical types, or an invalid value sigil.
enum NumericalType {
  case Integer(Int)
  case Float(Double)
  case Invalid
}


// MARK: Sequences

/// A wrapper for a Map that provides a different iterator for use with the interpreter. This iterator returns each
/// element as a Vector containing the key and value Values.
struct MapSequence : SequenceType, GeneratorType {
  let map : MapType
  var generator : DictionaryGenerator<Value, Value>

  init(_ map: MapType) { self.map = map; self.generator = map.generate() }

  func generate() -> MapSequence { return self }

  /// If the wrapped map is not empty, return the first key-value pair in the MapSequence as a Vector.
  func first() -> Value? {
    var t = self.generate()
    return t.next()
  }

  mutating func next() -> Value? {
    if let (key, value) = generator.next() {
      return .Vector([key, value])
    }
    return nil
  }
}

/// A sequence wrapping another sequence, representing pairs of items. The wrapped sequence must have an even number of
/// items.
struct PairSequence<T : SequenceType> : SequenceType {
  private let seq : T

  init(_ seq: T) { self.seq = seq }

  func generate() -> PairSequenceGenerator<T> {
    return PairSequenceGenerator(seq)
  }
}

struct PairSequenceGenerator<T : SequenceType> : GeneratorType {
  private let seq : T
  private var g : T.Generator

  private init(_ seq: T) { self.seq = seq; g = seq.generate() }

  mutating func next() -> (T.Generator.Element, T.Generator.Element)? {
    if let n1 = g.next() {
      if let n2 = g.next() {
        return (n1, n2)
      }
      else {
        preconditionFailure("Precondition violated: underlying sequence has an odd number of elements.")
      }
    }
    return nil
  }
}


// MARK: Regex

func rangeIsValid(r: NSRange) -> Bool {
  return !(r.location == NSNotFound && r.length == 0)
}

/// Given a pattern, try to build a regex pattern object.
func constructRegex(pattern: String) -> ReadOptional<RegularExpressionType> {
  do {
    return .Just(try RegularExpressionType(pattern: pattern, options: []))
  } catch {
    return .Error(ReadError(.InvalidRegexError))
  }
}


// MARK: Reference wrapper for structs

final class Box<T> {
  let value : T
  init(_ value: T) { self.value = value }

  subscript() -> T {
    return value
  }
}


// MARK: Swift string helpers

/// Given a string, return the string but without the last character. If the string is empty, the empty string will be
/// returned.
func stringWithoutLastCharacter(str: String) -> String {
  if str.isEmpty {
    return str
  }
  return str[str.startIndex..<str.endIndex.predecessor()]
}

// TODO: (az) Make this an extension method
/// Return whether or not a Swift character is a member of an NSCharacterSet.
func characterIsMemberOfSet(c: Character, set: NSCharacterSet) -> Bool {
  let primitive = String(c).utf16[String.UTF16View.Index(_offset: 0)] as unichar
  return set.characterIsMember(primitive)
}

// TODO: (az) Make this an extension method
/// Retrieve a character within a Swift string, or nil if the provided index is out of bounds. This is an O(n)
/// operation with respect to the length of the string.
func characterAtIndex(s: String, idx: Int) -> Character? {
  for (stringIdx, character) in s.characters.enumerate() {
    if stringIdx == idx {
      return character
    }
  }
  return nil
}
