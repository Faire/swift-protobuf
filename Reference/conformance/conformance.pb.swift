/*
 * DO NOT EDIT.
 *
 * Generated by the protocol buffer compiler.
 * Source: conformance/conformance.proto
 *
 */

//  Protocol Buffers - Google's data interchange format
//  Copyright 2008 Google Inc.  All rights reserved.
//  https://developers.google.com/protocol-buffers/
// 
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
// 
//      * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//      * Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following disclaimer
//  in the documentation and/or other materials provided with the
//  distribution.
//      * Neither the name of Google Inc. nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
// 
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that your are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _1: SwiftProtobuf.ProtobufAPIVersion_1 {}
  typealias Version = _1
}

fileprivate let _protobuf_package = "conformance"

//  This defines the conformance testing protocol.  This protocol exists between
//  the conformance test suite itself and the code being tested.  For each test,
//  the suite will send a ConformanceRequest message and expect a
//  ConformanceResponse message.
// 
//  You can either run the tests in two different ways:
// 
//    1. in-process (using the interface in conformance_test.h).
// 
//    2. as a sub-process communicating over a pipe.  Information about how to
//       do this is in conformance_test_runner.cc.
// 
//  Pros/cons of the two approaches:
// 
//    - running as a sub-process is much simpler for languages other than C/C++.
// 
//    - running as a sub-process may be more tricky in unusual environments like
//      iOS apps, where fork/stdin/stdout are not available.

enum Conformance_WireFormat: SwiftProtobuf.Enum, SwiftProtobuf._ProtoNameProviding {
  typealias RawValue = Int
  case unspecified // = 0
  case protobuf // = 1
  case json // = 2
  case UNRECOGNIZED(Int)

  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNSPECIFIED"),
    1: .same(proto: "PROTOBUF"),
    2: .same(proto: "JSON"),
  ]

  init() {
    self = .unspecified
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unspecified
    case 1: self = .protobuf
    case 2: self = .json
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .unspecified: return 0
    case .protobuf: return 1
    case .json: return 2
    case .UNRECOGNIZED(let i): return i
    }
  }

}

///   Represents a single test case's input.  The testee should:
///  
///     1. parse this proto (which should always succeed)
///     2. parse the protobuf or JSON payload in "payload" (which may fail)
///     3. if the parse succeeded, serialize the message in the requested format.
struct Conformance_ConformanceRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ConformanceRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .unique(proto: "protobuf_payload", json: "protobufPayload"),
    2: .unique(proto: "json_payload", json: "jsonPayload"),
    3: .unique(proto: "requested_output_format", json: "requestedOutputFormat"),
  ]

  var protobufPayload: Data {
    get {
      if case .protobufPayload(let v)? = payload {
        return v
      }
      return Data()
    }
    set {
      payload = .protobufPayload(newValue)
    }
  }

  var payload: Conformance_ConformanceRequest.OneOf_Payload? = nil

  var jsonPayload: String {
    get {
      if case .jsonPayload(let v)? = payload {
        return v
      }
      return ""
    }
    set {
      payload = .jsonPayload(newValue)
    }
  }

  ///   Which format should the testee serialize its message to?
  var requestedOutputFormat: Conformance_WireFormat = Conformance_WireFormat.unspecified

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OneOf_Payload: Equatable {
    case protobufPayload(Data)
    case jsonPayload(String)

    static func ==(lhs: Conformance_ConformanceRequest.OneOf_Payload, rhs: Conformance_ConformanceRequest.OneOf_Payload) -> Bool {
      switch (lhs, rhs) {
      case (.protobufPayload(let l), .protobufPayload(let r)): return l == r
      case (.jsonPayload(let l), .jsonPayload(let r)): return l == r
      default: return false
      }
    }

    fileprivate init?<T: SwiftProtobuf.Decoder>(byDecodingFrom decoder: inout T, fieldNumber: Int) throws {
      switch fieldNumber {
      case 1:
        var value = Data()
        try decoder.decodeSingularBytesField(value: &value)
        self = .protobufPayload(value)
        return
      case 2:
        var value = String()
        try decoder.decodeSingularStringField(value: &value)
        self = .jsonPayload(value)
        return
      default:
        break
      }
      return nil
    }

    fileprivate func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V, start: Int, end: Int) throws {
      switch self {
      case .protobufPayload(let v):
        if start <= 1 && 1 < end {
          try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
        }
      case .jsonPayload(let v):
        if start <= 2 && 2 < end {
          try visitor.visitSingularStringField(value: v, fieldNumber: 2)
        }
      }
    }
  }

  init() {}

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1, 2:
        if payload != nil {
          try decoder.handleConflictingOneOf()
        }
        payload = try Conformance_ConformanceRequest.OneOf_Payload(byDecodingFrom: &decoder, fieldNumber: fieldNumber)
      case 3: try decoder.decodeSingularEnumField(value: &requestedOutputFormat)
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try payload?.traverse(visitor: &visitor, start: 1, end: 3)
    if requestedOutputFormat != Conformance_WireFormat.unspecified {
      try visitor.visitSingularEnumField(value: requestedOutputFormat, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  func _protobuf_generated_isEqualTo(other: Conformance_ConformanceRequest) -> Bool {
    if payload != other.payload {return false}
    if requestedOutputFormat != other.requestedOutputFormat {return false}
    if unknownFields != other.unknownFields {return false}
    return true
  }
}

///   Represents a single test case's output.
struct Conformance_ConformanceResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ConformanceResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .unique(proto: "parse_error", json: "parseError"),
    6: .unique(proto: "serialize_error", json: "serializeError"),
    2: .unique(proto: "runtime_error", json: "runtimeError"),
    3: .unique(proto: "protobuf_payload", json: "protobufPayload"),
    4: .unique(proto: "json_payload", json: "jsonPayload"),
    5: .same(proto: "skipped"),
  ]

  ///   This string should be set to indicate parsing failed.  The string can
  ///   provide more information about the parse error if it is available.
  ///  
  ///   Setting this string does not necessarily mean the testee failed the
  ///   test.  Some of the test cases are intentionally invalid input.
  var parseError: String {
    get {
      if case .parseError(let v)? = result {
        return v
      }
      return ""
    }
    set {
      result = .parseError(newValue)
    }
  }

  var result: Conformance_ConformanceResponse.OneOf_Result? = nil

  ///   If the input was successfully parsed but errors occurred when
  ///   serializing it to the requested output format, set the error message in
  ///   this field.
  var serializeError: String {
    get {
      if case .serializeError(let v)? = result {
        return v
      }
      return ""
    }
    set {
      result = .serializeError(newValue)
    }
  }

  ///   This should be set if some other error occurred.  This will always
  ///   indicate that the test failed.  The string can provide more information
  ///   about the failure.
  var runtimeError: String {
    get {
      if case .runtimeError(let v)? = result {
        return v
      }
      return ""
    }
    set {
      result = .runtimeError(newValue)
    }
  }

  ///   If the input was successfully parsed and the requested output was
  ///   protobuf, serialize it to protobuf and set it in this field.
  var protobufPayload: Data {
    get {
      if case .protobufPayload(let v)? = result {
        return v
      }
      return Data()
    }
    set {
      result = .protobufPayload(newValue)
    }
  }

  ///   If the input was successfully parsed and the requested output was JSON,
  ///   serialize to JSON and set it in this field.
  var jsonPayload: String {
    get {
      if case .jsonPayload(let v)? = result {
        return v
      }
      return ""
    }
    set {
      result = .jsonPayload(newValue)
    }
  }

  ///   For when the testee skipped the test, likely because a certain feature
  ///   wasn't supported, like JSON input/output.
  var skipped: String {
    get {
      if case .skipped(let v)? = result {
        return v
      }
      return ""
    }
    set {
      result = .skipped(newValue)
    }
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OneOf_Result: Equatable {
    case parseError(String)
    case serializeError(String)
    case runtimeError(String)
    case protobufPayload(Data)
    case jsonPayload(String)
    case skipped(String)

    static func ==(lhs: Conformance_ConformanceResponse.OneOf_Result, rhs: Conformance_ConformanceResponse.OneOf_Result) -> Bool {
      switch (lhs, rhs) {
      case (.parseError(let l), .parseError(let r)): return l == r
      case (.serializeError(let l), .serializeError(let r)): return l == r
      case (.runtimeError(let l), .runtimeError(let r)): return l == r
      case (.protobufPayload(let l), .protobufPayload(let r)): return l == r
      case (.jsonPayload(let l), .jsonPayload(let r)): return l == r
      case (.skipped(let l), .skipped(let r)): return l == r
      default: return false
      }
    }

    fileprivate init?<T: SwiftProtobuf.Decoder>(byDecodingFrom decoder: inout T, fieldNumber: Int) throws {
      switch fieldNumber {
      case 1:
        var value = String()
        try decoder.decodeSingularStringField(value: &value)
        self = .parseError(value)
        return
      case 2:
        var value = String()
        try decoder.decodeSingularStringField(value: &value)
        self = .runtimeError(value)
        return
      case 3:
        var value = Data()
        try decoder.decodeSingularBytesField(value: &value)
        self = .protobufPayload(value)
        return
      case 4:
        var value = String()
        try decoder.decodeSingularStringField(value: &value)
        self = .jsonPayload(value)
        return
      case 5:
        var value = String()
        try decoder.decodeSingularStringField(value: &value)
        self = .skipped(value)
        return
      case 6:
        var value = String()
        try decoder.decodeSingularStringField(value: &value)
        self = .serializeError(value)
        return
      default:
        break
      }
      return nil
    }

    fileprivate func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V, start: Int, end: Int) throws {
      switch self {
      case .parseError(let v):
        if start <= 1 && 1 < end {
          try visitor.visitSingularStringField(value: v, fieldNumber: 1)
        }
      case .runtimeError(let v):
        if start <= 2 && 2 < end {
          try visitor.visitSingularStringField(value: v, fieldNumber: 2)
        }
      case .protobufPayload(let v):
        if start <= 3 && 3 < end {
          try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
        }
      case .jsonPayload(let v):
        if start <= 4 && 4 < end {
          try visitor.visitSingularStringField(value: v, fieldNumber: 4)
        }
      case .skipped(let v):
        if start <= 5 && 5 < end {
          try visitor.visitSingularStringField(value: v, fieldNumber: 5)
        }
      case .serializeError(let v):
        if start <= 6 && 6 < end {
          try visitor.visitSingularStringField(value: v, fieldNumber: 6)
        }
      }
    }
  }

  init() {}

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1...6:
        if result != nil {
          try decoder.handleConflictingOneOf()
        }
        result = try Conformance_ConformanceResponse.OneOf_Result(byDecodingFrom: &decoder, fieldNumber: fieldNumber)
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try result?.traverse(visitor: &visitor, start: 1, end: 7)
    try unknownFields.traverse(visitor: &visitor)
  }

  func _protobuf_generated_isEqualTo(other: Conformance_ConformanceResponse) -> Bool {
    if result != other.result {return false}
    if unknownFields != other.unknownFields {return false}
    return true
  }
}
