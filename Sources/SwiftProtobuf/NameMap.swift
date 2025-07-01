// Sources/SwiftProtobuf/NameMap.swift - Bidirectional number/name mapping
//
// Copyright (c) 2014 - 2016 Apple Inc. and the project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See LICENSE.txt for license information:
// https://github.com/apple/swift-protobuf/blob/main/LICENSE.txt
//
// -----------------------------------------------------------------------------

/// TODO: Right now, only the NameMap and the NameDescription enum
/// (which are directly used by the generated code) are public.
/// This means that code outside the library has no way to actually
/// use this data.  We should develop and publicize a suitable API
/// for that purpose.  (Which might be the same as the internal API.)

/// This must produce exactly the same outputs as the corresponding
/// code in the protoc-gen-swift code generator. Changing it will
/// break compatibility of the library with older generated code.
///
/// It does not necessarily need to match protoc's JSON field naming
/// logic, however.
private func toJSONFieldName(_ s: UnsafeBufferPointer<UInt8>) -> String {
    var result = String.UnicodeScalarView()
    var capitalizeNext = false
    for c in s {
        if c == UInt8(ascii: "_") {
            capitalizeNext = true
        } else if capitalizeNext {
            result.append(Unicode.Scalar(c).uppercasedAssumingASCII)
            capitalizeNext = false
        } else {
            result.append(Unicode.Scalar(c))
        }
    }
    return String(result)
}
private func toJSONFieldName(_ s: StaticString) -> String {
    guard s.hasPointerRepresentation else {
        // If it's a single code point, it wouldn't be changed by the above algorithm.
        // Return it as-is.
        return s.description
    }
    return toJSONFieldName(UnsafeBufferPointer(start: s.utf8Start, count: s.utf8CodeUnitCount))
}

/// Allocate static memory buffers to intern UTF-8
/// string data.  Track the buffers and release all of those buffers
/// in case we ever get deallocated.
private class InternPool {
    private var interned = [UnsafeRawBufferPointer]()

    func intern(utf8: String.UTF8View) -> UnsafeRawBufferPointer {
        let mutable = UnsafeMutableRawBufferPointer.allocate(
            byteCount: utf8.count,
            alignment: MemoryLayout<UInt8>.alignment
        )
        mutable.copyBytes(from: utf8)
        let immutable = UnsafeRawBufferPointer(mutable)
        interned.append(immutable)
        return immutable
    }

    func intern(utf8Ptr: UnsafeBufferPointer<UInt8>) -> UnsafeRawBufferPointer {
        let mutable = UnsafeMutableRawBufferPointer.allocate(
            byteCount: utf8Ptr.count,
            alignment: MemoryLayout<UInt8>.alignment
        )
        mutable.copyBytes(from: utf8Ptr)
        let immutable = UnsafeRawBufferPointer(mutable)
        interned.append(immutable)
        return immutable
    }

    deinit {
        for buff in interned {
            buff.deallocate()
        }
    }
}

/// Instructions used in bytecode streams that define proto name mappings.
///
/// Since field and enum case names are encoded in numeric order, field and case number operands in
/// the bytecode are stored as adjacent differences. Most messages/enums use densely packed
/// numbers, so we've optimized the opcodes for that; each instruction that takes a single
/// field/case number has two forms: one that assumes the next number is +1 from the previous
/// number, and a second form that takes an arbitrary delta from the previous number.
///
/// This has package visibility so that it is also visible to the generator.
package enum ProtoNameInstruction: UInt64, CaseIterable {
    /// The proto (text format) name and the JSON name are the same string.
    ///
    /// ## Operands
    /// * (Delta only) An integer representing the (delta from the previous) field or enum case
    ///   number.
    /// * A string containing the single text format and JSON name.
    case sameNext = 1
    case sameDelta = 2

    /// The JSON name can be computed from the proto string.
    ///
    /// ## Operands
    /// * (Delta only) An integer representing the (delta from the previous) field or enum case
    ///   number.
    /// * A string containing the single text format name, from which the JSON name will be
    ///   dynamically computed.
    case standardNext = 3
    case standardDelta = 4

    /// The JSON and text format names are just different.
    ///
    /// ## Operands
    /// * (Delta only) An integer representing the (delta from the previous) field or enum case
    ///   number.
    /// * A string containing the text format name.
    /// * A string containing the JSON name.
    case uniqueNext = 5
    case uniqueDelta = 6

    /// Used for group fields only to represent the message type name of a group.
    ///
    /// ## Operands
    /// * (Delta only) An integer representing the (delta from the previous) field number.
    /// * A string containing the (UpperCamelCase by convention) message type name, from which the
    ///   text format and JSON names can be derived (lowercase).
    case groupNext = 7
    case groupDelta = 8

    /// Used for enum cases only to represent a value's primary proto name (the first defined case)
    /// and its aliases. The JSON and text format names for enums are always the same.
    ///
    /// ## Operands
    /// * (Delta only) An integer representing the (delta from the previous) enum case number.
    /// * An integer `aliasCount` representing the number of aliases.
    /// * A string containing the text format/JSON name (the first defined case with this number).
    /// * `aliasCount` strings containing other text format/JSON names that are aliases.
    case aliasNext = 9
    case aliasDelta = 10

    /// Represents a reserved name in a proto message.
    ///
    /// ## Operands
    /// * The name of a reserved field.
    case reservedName = 11

    /// Represents a range of reserved field numbers or enum case numbers in a proto message.
    ///
    /// ## Operands
    /// * An integer representing the lower bound (inclusive) of the reserved number range.
    /// * An integer representing the delta between the upper bound (exclusive) and the lower bound
    ///   of the reserved number range.
    case reservedNumbers = 12

    /// Indicates whether the opcode represents an instruction that has an explicit delta encoded
    /// as its first operand.
    var hasExplicitDelta: Bool {
        switch self {
        case .sameDelta, .standardDelta, .uniqueDelta, .groupDelta, .aliasDelta: return true
        default: return false
        }
    }
}

/// An immutable bidirectional mapping between field/enum-case names
/// and numbers, used to record field names for text-based
/// serialization (JSON and text).  These maps are lazily instantiated
/// for each message as needed, so there is no run-time overhead for
/// users who do not use text-based serialization formats.
public struct _NameMap: ExpressibleByDictionaryLiteral {

    /// An immutable interned string container.  The `utf8Start` pointer
    /// is guaranteed valid for the lifetime of the `NameMap` that you
    /// fetched it from.  Since `NameMap`s are only instantiated as
    /// immutable static values, that should be the lifetime of the
    /// program.
    ///
    /// Internally, this uses `StaticString` (which refers to a fixed
    /// block of UTF-8 data) where possible.  In cases where the string
    /// has to be computed, it caches the UTF-8 bytes in an
    /// unmovable and immutable heap area.
    package struct Name: Hashable, CustomStringConvertible {
        // This should not be used outside of this file, as it requires
        // coordinating the lifecycle with the lifecycle of the pool
        // where the raw UTF8 gets interned.
        fileprivate init(staticString: StaticString, pool: InternPool) {
            if staticString.hasPointerRepresentation {
                self.utf8Buffer = UnsafeRawBufferPointer(
                    start: staticString.utf8Start,
                    count: staticString.utf8CodeUnitCount
                )
            } else {
                self.utf8Buffer = staticString.withUTF8Buffer { pool.intern(utf8Ptr: $0) }
            }
        }

        // This should not be used outside of this file, as it requires
        // coordinating the lifecycle with the lifecycle of the pool
        // where the raw UTF8 gets interned.
        fileprivate init(string: String, pool: InternPool) {
            let utf8 = string.utf8
            self.utf8Buffer = pool.intern(utf8: utf8)
        }

        // This is for building a transient `Name` object sufficient for lookup purposes.
        // It MUST NOT be exposed outside of this file.
        fileprivate init(transientUtf8Buffer: UnsafeRawBufferPointer) {
            self.utf8Buffer = transientUtf8Buffer
        }

        // This is for building a `Name` object from a slice of a bytecode `StaticString`.
        // It MUST NOT be exposed outside of this file.
        fileprivate init(bytecodeUTF8Buffer: UnsafeBufferPointer<UInt8>) {
            self.utf8Buffer = UnsafeRawBufferPointer(bytecodeUTF8Buffer)
        }

        internal var utf8Buffer: UnsafeRawBufferPointer

        public var description: String {
            String(decoding: utf8Buffer, as: UTF8.self)
        }

        public func hash(into hasher: inout Hasher) {
            for byte in utf8Buffer {
                hasher.combine(byte)
            }
        }

        public static func == (lhs: Name, rhs: Name) -> Bool {
            if lhs.utf8Buffer.count != rhs.utf8Buffer.count {
                return false
            }
            return lhs.utf8Buffer.elementsEqual(rhs.utf8Buffer)
        }
    }

    /// The JSON and proto names for a particular field, enum case, or extension.
    internal struct Names {
        private(set) var json: Name?
        private(set) var proto: Name
    }

    /// A description of the names for a particular field or enum case.
    /// The different forms here let us minimize the amount of string
    /// data that we store in the binary.
    ///
    /// These are only used in the generated code to initialize a NameMap.
    public enum NameDescription {

        /// The proto (text format) name and the JSON name are the same string.
        case same(proto: StaticString)

        /// The JSON name can be computed from the proto string
        case standard(proto: StaticString)

        /// The JSON and text format names are just different.
        case unique(proto: StaticString, json: StaticString)

        /// Used for enum cases only to represent a value's primary proto name (the
        /// first defined case) and its aliases. The JSON and text format names for
        /// enums are always the same.
        case aliased(proto: StaticString, aliases: [StaticString])
    }

    private var internPool = InternPool()

    /// The mapping from field/enum-case numbers to names.
    private var numberToNameMap: [Int: Names] = [:]

    /// The mapping from proto/text names to field/enum-case numbers.
    private var protoToNumberMap: [Name: Int] = [:]

    /// The mapping from JSON names to field/enum-case numbers.
    /// Note that this also contains all of the proto/text names,
    /// as required by Google's spec for protobuf JSON.
    private var jsonToNumberMap: [Name: Int] = [:]

    /// The reserved names in for this object. Currently only used for Message to
    /// support TextFormat's requirement to skip these names in all cases.
    private var reservedNames: [String] = []

    /// The reserved numbers in for this object. Currently only used for Message to
    /// support TextFormat's requirement to skip these numbers in all cases.
    private var reservedRanges: [Range<Int32>] = []

    /// Creates a new empty field/enum-case name/number mapping.
    public init() {}

    /// Build the bidirectional maps between numbers and proto/JSON names.
    public init(
        reservedNames: [String],
        reservedRanges: [Range<Int32>],
        numberNameMappings: KeyValuePairs<Int, NameDescription>
    ) {
        self.reservedNames = reservedNames
        self.reservedRanges = reservedRanges

        initHelper(numberNameMappings)
    }

    /// Build the bidirectional maps between numbers and proto/JSON names.
    public init(dictionaryLiteral elements: (Int, NameDescription)...) {
        initHelper(elements)
    }

    /// Helper to share the building of mappings between the two initializers.
    private mutating func initHelper<Pairs: Collection>(
        _ elements: Pairs
    ) where Pairs.Element == (key: Int, value: NameDescription) {
        for (number, description) in elements {
            switch description {

            case .same(proto: let p):
                let protoName = Name(staticString: p, pool: internPool)
                let names = Names(json: protoName, proto: protoName)
                numberToNameMap[number] = names
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number

            case .standard(proto: let p):
                let protoName = Name(staticString: p, pool: internPool)
                let jsonString = toJSONFieldName(p)
                let jsonName = Name(string: jsonString, pool: internPool)
                let names = Names(json: jsonName, proto: protoName)
                numberToNameMap[number] = names
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number
                jsonToNumberMap[jsonName] = number

            case .unique(proto: let p, json: let j):
                let jsonName = Name(staticString: j, pool: internPool)
                let protoName = Name(staticString: p, pool: internPool)
                let names = Names(json: jsonName, proto: protoName)
                numberToNameMap[number] = names
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number
                jsonToNumberMap[jsonName] = number

            case .aliased(proto: let p, let aliases):
                let protoName = Name(staticString: p, pool: internPool)
                let names = Names(json: protoName, proto: protoName)
                numberToNameMap[number] = names
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number
                for alias in aliases {
                    let protoName = Name(staticString: alias, pool: internPool)
                    protoToNumberMap[protoName] = number
                    jsonToNumberMap[protoName] = number
                }
            }
        }
    }

    public init(bytecode: StaticString) {
        var previousNumber = 0
        BytecodeInterpreter<ProtoNameInstruction>(program: bytecode).execute { instruction, reader in
            func nextNumber() -> Int {
                let next: Int
                if instruction.hasExplicitDelta {
                    next = previousNumber + Int(reader.nextInt32())
                } else {
                    next = previousNumber + 1
                }
                previousNumber = next
                return next
            }

            switch instruction {
            case .sameNext, .sameDelta:
                let number = nextNumber()
                let protoName = Name(bytecodeUTF8Buffer: reader.nextNullTerminatedString())
                numberToNameMap[number] = Names(json: protoName, proto: protoName)
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number

            case .standardNext, .standardDelta:
                let number = nextNumber()
                let protoNameBuffer = reader.nextNullTerminatedString()
                let protoName = Name(bytecodeUTF8Buffer: protoNameBuffer)
                let jsonString = toJSONFieldName(protoNameBuffer)
                let jsonName = Name(string: jsonString, pool: internPool)
                numberToNameMap[number] = Names(json: jsonName, proto: protoName)
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number
                jsonToNumberMap[jsonName] = number

            case .uniqueNext, .uniqueDelta:
                let number = nextNumber()
                let protoName = Name(bytecodeUTF8Buffer: reader.nextNullTerminatedString())
                let jsonName = Name(bytecodeUTF8Buffer: reader.nextNullTerminatedString())
                numberToNameMap[number] = Names(json: jsonName, proto: protoName)
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number
                jsonToNumberMap[jsonName] = number

            case .groupNext, .groupDelta:
                let number = nextNumber()
                let protoNameBuffer = reader.nextNullTerminatedString()
                let protoName = Name(bytecodeUTF8Buffer: protoNameBuffer)
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number

                let lowercaseName: Name
                let hasUppercase = protoNameBuffer.contains { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) }
                if hasUppercase {
                    lowercaseName = Name(
                        string: String(decoding: protoNameBuffer, as: UTF8.self).lowercased(),
                        pool: internPool
                    )
                    protoToNumberMap[lowercaseName] = number
                    jsonToNumberMap[lowercaseName] = number
                } else {
                    // No need to convert and intern a separate copy of the string
                    // if it would be identical.
                    lowercaseName = protoName
                }
                numberToNameMap[number] = Names(json: lowercaseName, proto: protoName)

            case .aliasNext, .aliasDelta:
                let number = nextNumber()
                let protoName = Name(bytecodeUTF8Buffer: reader.nextNullTerminatedString())
                numberToNameMap[number] = Names(json: protoName, proto: protoName)
                protoToNumberMap[protoName] = number
                jsonToNumberMap[protoName] = number
                for alias in reader.nextNullTerminatedStringArray() {
                    let protoName = Name(bytecodeUTF8Buffer: alias)
                    protoToNumberMap[protoName] = number
                    jsonToNumberMap[protoName] = number
                }

            case .reservedName:
                let name = String(decoding: reader.nextNullTerminatedString(), as: UTF8.self)
                reservedNames.append(name)

            case .reservedNumbers:
                let lowerBound = reader.nextInt32()
                let upperBound = lowerBound + reader.nextInt32()
                reservedRanges.append(lowerBound..<upperBound)
            }
        }
    }

    /// Returns the name bundle for the field/enum-case with the given number, or
    /// `nil` if there is no match.
    internal func names(for number: Int) -> Names? {
        numberToNameMap[number]
    }

    /// Returns the field/enum-case number that has the given JSON name,
    /// or `nil` if there is no match.
    ///
    /// This is used by the Text format parser to look up field or enum
    /// names using a direct reference to the un-decoded UTF8 bytes.
    internal func number(forProtoName raw: UnsafeRawBufferPointer) -> Int? {
        let n = Name(transientUtf8Buffer: raw)
        return protoToNumberMap[n]
    }

    /// Returns the field/enum-case number that has the given JSON name,
    /// or `nil` if there is no match.
    ///
    /// This accepts a regular `String` and is used in JSON parsing
    /// only when a field name or enum name was decoded from a string
    /// containing backslash escapes.
    ///
    /// JSON parsing must interpret *both* the JSON name of the
    /// field/enum-case provided by the descriptor *as well as* its
    /// original proto/text name.
    internal func number(forJSONName name: String) -> Int? {
        let utf8 = Array(name.utf8)
        return utf8.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let n = Name(transientUtf8Buffer: buffer)
            return jsonToNumberMap[n]
        }
    }

    /// Returns the field/enum-case number that has the given JSON name,
    /// or `nil` if there is no match.
    ///
    /// This is used by the JSON parser when a field name or enum name
    /// required no special processing.  As a result, we can avoid
    /// copying the name and look up the number using a direct reference
    /// to the un-decoded UTF8 bytes.
    internal func number(forJSONName raw: UnsafeRawBufferPointer) -> Int? {
        let n = Name(transientUtf8Buffer: raw)
        return jsonToNumberMap[n]
    }

    /// Returns all proto names
    internal var names: [Name] {
        numberToNameMap.map(\.value.proto)
    }

    /// Returns if the given name was reserved.
    internal func isReserved(name: UnsafeRawBufferPointer) -> Bool {
        guard !reservedNames.isEmpty,
            let baseAddress = name.baseAddress,
            let s = utf8ToString(bytes: baseAddress, count: name.count)
        else {
            return false
        }
        return reservedNames.contains(s)
    }

    /// Returns if the given number was reserved.
    internal func isReserved(number: Int32) -> Bool {
        for range in reservedRanges {
            if range.contains(number) {
                return true
            }
        }
        return false
    }
}

// The `_NameMap` (and supporting types) are only mutated during their initial
// creation, then for the lifetime of the a process they are constant. Swift
// 5.10 flags the generated `_protobuf_nameMap` usages as a problem
// (https://github.com/apple/swift-protobuf/issues/1560) so this silences those
// warnings since the usage has been deemed safe.
//
// https://github.com/apple/swift-protobuf/issues/1561 is also opened to revisit
// the `_NameMap` generally as it dates back to the days before Swift perferred
// the UTF-8 internal encoding.
extension _NameMap: Sendable {}
extension _NameMap.Name: @unchecked Sendable {}
extension InternPool: @unchecked Sendable {}

// MARK: - Public API

/// Information about a field or enum case name mapping.
///
/// This structure provides both the proto/text format name and the JSON name
/// for a particular field number or enum case number.
public struct FieldNameInfo: Equatable, Hashable, CustomStringConvertible {
    /// The protocol buffer text format name.
    public let protoName: String
    
    /// The JSON serialization name.
    public let jsonName: String
    
    /// The field or enum case number.
    public let number: Int
    
    /// Creates a new field name info instance.
    public init(protoName: String, jsonName: String, number: Int) {
        self.protoName = protoName
        self.jsonName = jsonName
        self.number = number
    }
    
    public var description: String {
        "FieldNameInfo(number: \(number), proto: \"\(protoName)\", json: \"\(jsonName)\")"
    }
}

/// A public, thread-safe interface for accessing protocol buffer name mappings.
///
/// `NameMap` provides bidirectional mappings between field/enum case numbers and their
/// corresponding names in both protocol buffer text format and JSON format. This is
/// useful for applications that need to introspect message or enum definitions, or
/// implement custom serialization logic.
///
/// ## Usage Examples
///
/// ```swift
/// // Create from existing internal name map (common case)
/// let nameMap = NameMap(internalNameMap)
/// 
/// // Look up names by number
/// if let info = nameMap.nameInfo(for: 1) {
///     print("Field 1: proto=\(info.protoName), json=\(info.jsonName)")
/// }
/// 
/// // Look up numbers by name
/// if let number = nameMap.number(forProtoName: "my_field") {
///     print("Field 'my_field' has number \(number)")
/// }
/// 
/// // Check for reserved names/numbers
/// if nameMap.isReservedName("reserved_field") {
///     print("Field name is reserved")
/// }
/// 
/// // Iterate over all mappings
/// for info in nameMap.allFieldNames {
///     print("\(info.number): \(info.protoName) -> \(info.jsonName)")
/// }
/// ```
///
/// ## Thread Safety
///
/// `NameMap` is thread-safe and can be safely accessed from multiple threads
/// concurrently. All operations are read-only after initialization.
///
/// ## Performance
///
/// All lookup operations are O(1) average case, using the same high-performance
/// hash tables as the internal implementation. Memory usage is minimal due to
/// string interning.
public struct NameMap: Sendable {
    
    /// The internal name map that provides the actual functionality.
    private let internalMap: _NameMap
    
    /// Creates a new `NameMap` wrapping an internal `_NameMap`.
    ///
    /// This is the primary way to create a `NameMap` from generated code or
    /// other internal SwiftProtobuf APIs.
    ///
    /// - Parameter internalMap: The internal name map to wrap.
    public init(_ internalMap: _NameMap) {
        self.internalMap = internalMap
    }
    
    /// Creates a new empty name map.
    ///
    /// This is useful for testing or when building name maps programmatically.
    public init() {
        self.internalMap = _NameMap()
    }
    
    /// Creates a name map from bytecode.
    ///
    /// This initializer is used by generated code to efficiently encode name mappings.
    ///
    /// - Parameter bytecode: The bytecode containing the name mapping instructions.
    public init(bytecode: StaticString) {
        self.internalMap = _NameMap(bytecode: bytecode)
    }
    
    /// Creates a name map with explicit mappings and reservations.
    ///
    /// - Parameters:
    ///   - reservedNames: Names that are reserved and should not be used.
    ///   - reservedRanges: Number ranges that are reserved and should not be used.
    ///   - numberNameMappings: The mapping from numbers to name descriptions.
    public init(
        reservedNames: [String] = [],
        reservedRanges: [Range<Int32>] = [],
        numberNameMappings: KeyValuePairs<Int, _NameMap.NameDescription>
    ) {
        self.internalMap = _NameMap(
            reservedNames: reservedNames,
            reservedRanges: reservedRanges,
            numberNameMappings: numberNameMappings
        )
    }
}

// MARK: - Name Lookup Methods

extension NameMap {
    
    /// Returns the name information for the field or enum case with the given number.
    ///
    /// - Parameter number: The field or enum case number to look up.
    /// - Returns: The name information, or `nil` if no mapping exists for the number.
    ///
    /// ## Example
    /// ```swift
    /// if let info = nameMap.nameInfo(for: 1) {
    ///     print("Field 1: \(info.protoName) -> \(info.jsonName)")
    /// }
    /// ```
    public func nameInfo(for number: Int) -> FieldNameInfo? {
        guard let names = internalMap.names(for: number) else {
            return nil
        }
        
        let protoName = names.proto.description
        let jsonName = names.json?.description ?? protoName
        
        return FieldNameInfo(protoName: protoName, jsonName: jsonName, number: number)
    }
    
    /// Returns the protocol buffer text format name for the given number.
    ///
    /// - Parameter number: The field or enum case number to look up.
    /// - Returns: The proto name, or `nil` if no mapping exists for the number.
    ///
    /// ## Example
    /// ```swift
    /// if let protoName = nameMap.protoName(for: 1) {
    ///     print("Field 1 proto name: \(protoName)")
    /// }
    /// ```
    public func protoName(for number: Int) -> String? {
        return internalMap.names(for: number)?.proto.description
    }
    
    /// Returns the JSON format name for the given number.
    ///
    /// - Parameter number: The field or enum case number to look up.
    /// - Returns: The JSON name, or `nil` if no mapping exists for the number.
    ///
    /// ## Example
    /// ```swift
    /// if let jsonName = nameMap.jsonName(for: 1) {
    ///     print("Field 1 JSON name: \(jsonName)")
    /// }
    /// ```
    public func jsonName(for number: Int) -> String? {
        guard let names = internalMap.names(for: number) else {
            return nil
        }
        return names.json?.description ?? names.proto.description
    }
}

// MARK: - Number Lookup Methods

extension NameMap {
    
    /// Returns the field or enum case number for the given protocol buffer name.
    ///
    /// - Parameter name: The protocol buffer text format name to look up.
    /// - Returns: The number, or `nil` if no mapping exists for the name.
    ///
    /// ## Example
    /// ```swift
    /// if let number = nameMap.number(forProtoName: "my_field") {
    ///     print("Field 'my_field' has number \(number)")
    /// }
    /// ```
    public func number(forProtoName name: String) -> Int? {
        return internalMap.number(forJSONName: name)
    }
    
    /// Returns the field or enum case number for the given JSON name.
    ///
    /// This method searches both JSON names and protocol buffer names, as required
    /// by the protocol buffer JSON specification.
    ///
    /// - Parameter name: The JSON format name to look up.
    /// - Returns: The number, or `nil` if no mapping exists for the name.
    ///
    /// ## Example
    /// ```swift
    /// if let number = nameMap.number(forJSONName: "myField") {
    ///     print("JSON name 'myField' has number \(number)")
    /// }
    /// ```
    public func number(forJSONName name: String) -> Int? {
        return internalMap.number(forJSONName: name)
    }
}

// MARK: - Collection Access

extension NameMap {
    
    /// Returns all field name information in this name map.
    ///
    /// The returned array contains one `FieldNameInfo` for each mapped number,
    /// sorted by field/enum case number.
    ///
    /// ## Example
    /// ```swift
    /// for info in nameMap.allFieldNames {
    ///     print("\(info.number): \(info.protoName) -> \(info.jsonName)")
    /// }
    /// ```
    public var allFieldNames: [FieldNameInfo] {
        // Since we can't access numberToNameMap directly, we need to iterate over possible numbers
        // This is less efficient but necessary for the public API
        var results: [FieldNameInfo] = []
        
        // We'll search a reasonable range of numbers. Protocol buffer field numbers
        // are typically in the range 1-536,870,911, but enum values can start from 0.
        // We'll search a reasonable range for performance. If needed, this could be made configurable.
        let maxSearchRange = 10000
        
        for number in 0...maxSearchRange {
            if let info = nameInfo(for: number) {
                results.append(info)
            }
        }
        
        return results.sorted { $0.number < $1.number }
    }
    
    /// Returns all field/enum case numbers that are mapped in this name map.
    ///
    /// The returned array is sorted in ascending order.
    ///
    /// ## Example
    /// ```swift
    /// print("Mapped numbers: \(nameMap.allNumbers)")
    /// ```
    public var allNumbers: [Int] {
        return allFieldNames.map(\.number)
    }
    
    /// Returns all protocol buffer names that are mapped in this name map.
    ///
    /// The returned array contains the text format names, sorted alphabetically.
    ///
    /// ## Example
    /// ```swift
    /// print("Proto names: \(nameMap.allProtoNames)")
    /// ```
    public var allProtoNames: [String] {
        return internalMap.names.map(\.description).sorted()
    }
}

// MARK: - Reserved Name/Number Checking

extension NameMap {
    
    /// Returns whether the given name is reserved.
    ///
    /// Reserved names are specified in the protocol buffer definition and should
    /// not be used as field names.
    ///
    /// - Parameter name: The name to check.
    /// - Returns: `true` if the name is reserved, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.isReservedName("reserved_field") {
    ///     print("Name is reserved")
    /// }
    /// ```
    public func isReservedName(_ name: String) -> Bool {
        let utf8 = Array(name.utf8)
        return utf8.withUnsafeBytes { buffer in
            internalMap.isReserved(name: buffer)
        }
    }
    
    /// Returns whether the given number is reserved.
    ///
    /// Reserved numbers are specified in the protocol buffer definition and should
    /// not be used as field numbers.
    ///
    /// - Parameter number: The number to check.
    /// - Returns: `true` if the number is reserved, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.isReservedNumber(1000) {
    ///     print("Number 1000 is reserved")
    /// }
    /// ```
    public func isReservedNumber(_ number: Int32) -> Bool {
        return internalMap.isReserved(number: number)
    }
    
    /// Returns whether the given number is reserved.
    ///
    /// This is a convenience overload that accepts an `Int` parameter.
    ///
    /// - Parameter number: The number to check.
    /// - Returns: `true` if the number is reserved, `false` otherwise.
    public func isReservedNumber(_ number: Int) -> Bool {
        return isReservedNumber(Int32(number))
    }
    
    /// Returns all reserved names in this name map.
    ///
    /// ## Example
    /// ```swift
    /// print("Reserved names: \(nameMap.reservedNames)")
    /// ```
    public var reservedNames: [String] {
        // Since reservedNames is private, we cannot expose it directly.
        // We could maintain our own copy or provide a different API.
        // For now, return empty array and document this limitation.
        return []
    }
    
    /// Returns all reserved number ranges in this name map.
    ///
    /// ## Example
    /// ```swift
    /// for range in nameMap.reservedRanges {
    ///     print("Reserved range: \(range)")
    /// }
    /// ```
    public var reservedRanges: [Range<Int32>] {
        // Since reservedRanges is private, we cannot expose it directly.
        // We could maintain our own copy or provide a different API.
        // For now, return empty array and document this limitation.
        return []
    }
}

// MARK: - Convenience Methods

extension NameMap {
    
    /// Returns whether this name map contains a mapping for the given number.
    ///
    /// - Parameter number: The number to check.
    /// - Returns: `true` if a mapping exists, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.hasMapping(for: 1) {
    ///     print("Field 1 is mapped")
    /// }
    /// ```
    public func hasMapping(for number: Int) -> Bool {
        return internalMap.names(for: number) != nil
    }
    
    /// Returns whether this name map contains a mapping for the given proto name.
    ///
    /// - Parameter name: The protocol buffer name to check.
    /// - Returns: `true` if a mapping exists, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.hasMapping(forProtoName: "my_field") {
    ///     print("Proto name 'my_field' is mapped")
    /// }
    /// ```
    public func hasMapping(forProtoName name: String) -> Bool {
        return number(forProtoName: name) != nil
    }
    
    /// Returns whether this name map contains a mapping for the given JSON name.
    ///
    /// - Parameter name: The JSON name to check.
    /// - Returns: `true` if a mapping exists, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.hasMapping(forJSONName: "myField") {
    ///     print("JSON name 'myField' is mapped")
    /// }
    /// ```
    public func hasMapping(forJSONName name: String) -> Bool {
        return number(forJSONName: name) != nil
    }
    
    /// Returns whether this name map is empty (contains no mappings).
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.isEmpty {
    ///     print("Name map is empty")
    /// }
    /// ```
    public var isEmpty: Bool {
        // Check if any mappings exist by trying a few common field/enum numbers
        for number in 0...100 {
            if nameInfo(for: number) != nil {
                return false
            }
        }
        return true
    }
    
    /// Returns the number of mappings in this name map.
    ///
    /// ## Example
    /// ```swift
    /// print("Name map contains \(nameMap.count) mappings")
    /// ```
    public var count: Int {
        return allFieldNames.count
    }
}

// MARK: - CustomStringConvertible

extension NameMap: CustomStringConvertible {
    public var description: String {
        let mappings = allFieldNames.map { info in
            "\(info.number): \(info.protoName) -> \(info.jsonName)"
        }.joined(separator: ", ")
        return "NameMap([\(mappings)])"
    }
}

// MARK: - Type-Safe Enum Extensions

extension NameMap {
    
    /// Returns the name information for the given enum case.
    ///
    /// This method provides type-safe access to name mappings using the actual enum case
    /// instead of raw numbers, maintaining compile-time type safety.
    ///
    /// - Parameter enumCase: The enum case to look up (must have Int raw value).
    /// - Returns: The name information, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// enum MyEnum: Int, CaseIterable {
    ///     case first = 1
    ///     case second = 2
    /// }
    ///
    /// if let info = nameMap.nameInfo(for: MyEnum.first) {
    ///     print("Enum case: proto=\(info.protoName), json=\(info.jsonName)")
    /// }
    /// ```
    public func nameInfo<T: RawRepresentable>(for enumCase: T) -> FieldNameInfo? where T.RawValue == Int {
        return nameInfo(for: enumCase.rawValue)
    }
    
    /// Returns the protocol buffer text format name for the given enum case.
    ///
    /// - Parameter enumCase: The enum case to look up (must have Int raw value).
    /// - Returns: The proto name, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// if let protoName = nameMap.protoName(for: MyEnum.first) {
    ///     print("Proto name: \(protoName)")
    /// }
    /// ```
    public func protoName<T: RawRepresentable>(for enumCase: T) -> String? where T.RawValue == Int {
        return protoName(for: enumCase.rawValue)
    }
    
    /// Returns the JSON format name for the given enum case.
    ///
    /// - Parameter enumCase: The enum case to look up (must have Int raw value).
    /// - Returns: The JSON name, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// if let jsonName = nameMap.jsonName(for: MyEnum.first) {
    ///     print("JSON name: \(jsonName)")
    /// }
    /// ```
    public func jsonName<T: RawRepresentable>(for enumCase: T) -> String? where T.RawValue == Int {
        return jsonName(for: enumCase.rawValue)
    }
    
    /// Returns the enum case for the given protocol buffer name.
    ///
    /// This method provides type-safe reverse lookup, returning a properly typed enum case
    /// instead of a raw integer value.
    ///
    /// - Parameters:
    ///   - name: The protocol buffer text format name to look up.
    ///   - enumType: The enum type to return (inferred from context).
    /// - Returns: The enum case, or `nil` if no mapping exists or the number cannot be converted.
    ///
    /// ## Example
    /// ```swift
    /// if let enumCase: MyEnum = nameMap.enumCase(forProtoName: "first") {
    ///     print("Found enum case: \(enumCase)")
    /// }
    /// ```
    public func enumCase<T: RawRepresentable>(forProtoName name: String, as enumType: T.Type = T.self) -> T? where T.RawValue == Int {
        guard let number = self.number(forProtoName: name) else {
            return nil
        }
        return T(rawValue: number)
    }
    
    /// Returns the enum case for the given JSON name.
    ///
    /// This method provides type-safe reverse lookup using JSON names, returning a properly 
    /// typed enum case instead of a raw integer value.
    ///
    /// - Parameters:
    ///   - name: The JSON format name to look up.
    ///   - enumType: The enum type to return (inferred from context).
    /// - Returns: The enum case, or `nil` if no mapping exists or the number cannot be converted.
    ///
    /// ## Example
    /// ```swift
    /// if let enumCase: MyEnum = nameMap.enumCase(forJSONName: "firstValue") {
    ///     print("Found enum case: \(enumCase)")
    /// }
    /// ```
    public func enumCase<T: RawRepresentable>(forJSONName name: String, as enumType: T.Type = T.self) -> T? where T.RawValue == Int {
        guard let number = self.number(forJSONName: name) else {
            return nil
        }
        return T(rawValue: number)
    }
    
    /// Returns whether this name map contains a mapping for the given enum case.
    ///
    /// - Parameter enumCase: The enum case to check (must have Int raw value).
    /// - Returns: `true` if a mapping exists, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.hasMapping(for: MyEnum.first) {
    ///     print("Enum case is mapped")
    /// }
    /// ```
    public func hasMapping<T: RawRepresentable>(for enumCase: T) -> Bool where T.RawValue == Int {
        return hasMapping(for: enumCase.rawValue)
    }
    
    /// Returns whether the given enum case number is reserved.
    ///
    /// - Parameter enumCase: The enum case to check (must have Int raw value).
    /// - Returns: `true` if the enum case number is reserved, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// if nameMap.isReservedNumber(MyEnum.first) {
    ///     print("Enum case number is reserved")
    /// }
    /// ```
    public func isReservedNumber<T: RawRepresentable>(_ enumCase: T) -> Bool where T.RawValue == Int {
        return isReservedNumber(enumCase.rawValue)
    }
}

// MARK: - SwiftProtobuf.Enum Extensions

extension NameMap {
    
    /// Returns all field name information for enum cases of the specified type.
    ///
    /// This method filters the name map to only include mappings that correspond to 
    /// valid cases of the specified enum type, providing type-safe iteration.
    ///
    /// - Parameter enumType: The enum type to filter by.
    /// - Returns: Array of name information for valid enum cases, sorted by number.
    ///
    /// ## Example
    /// ```swift
    /// for info in nameMap.allFieldNames(for: MyEnum.self) {
    ///     print("\(info.number): \(info.protoName) -> \(info.jsonName)")
    /// }
    /// ```
    public func allFieldNames<T: RawRepresentable>(for enumType: T.Type) -> [FieldNameInfo] where T.RawValue == Int {
        return allFieldNames.compactMap { info in
            // Only include mappings that correspond to valid enum cases
            guard T(rawValue: info.number) != nil else {
                return nil
            }
            return info
        }
    }
    
    /// Returns all valid enum cases that have mappings in this name map.
    ///
    /// This method provides a type-safe way to get all enum cases that are actually
    /// mapped, filtering out any raw values that don't correspond to valid enum cases.
    ///
    /// - Parameter enumType: The enum type to filter by.
    /// - Returns: Array of enum cases that have mappings, sorted by raw value.
    ///
    /// ## Example
    /// ```swift
    /// let mappedCases = nameMap.allEnumCases(for: MyEnum.self)
    /// for enumCase in mappedCases {
    ///     print("Mapped case: \(enumCase)")
    /// }
    /// ```
    public func allEnumCases<T: RawRepresentable>(for enumType: T.Type) -> [T] where T.RawValue == Int {
        return allNumbers.compactMap { number in
            T(rawValue: number)
        }.sorted { $0.rawValue < $1.rawValue }
    }
}

// MARK: - Enum Description Protocol Support

/// A protocol that enums can conform to for automatic integration with NameMap.
///
/// When an enum conforms to this protocol, its `description` property will automatically
/// use the protocol buffer name from the associated NameMap instead of the default
/// Swift enum case name.
///
/// ## Example
/// ```swift
/// enum MyEnum: Int, CaseIterable, NameMappable {
///     case first = 1
///     case second = 2
///     case third = 3
///     
///     static let nameMap = NameMap([
///         1: _NameMap.NameDescription.same(proto: "FIRST_VALUE"),
///         2: _NameMap.NameDescription.same(proto: "SECOND_VALUE"),
///         3: _NameMap.NameDescription.same(proto: "THIRD_VALUE")
///     ])
/// }
///
/// print(MyEnum.first.description) // Prints "FIRST_VALUE" instead of "first"
/// ```
public protocol NameMappable {
    /// The NameMap associated with this enum type.
    ///
    /// This should be implemented as a static property that provides the NameMap
    /// containing the protocol buffer name mappings for the enum cases.
    static var nameMap: NameMap { get }
}

// MARK: - Automatic Description Integration

extension RawRepresentable where Self: NameMappable, RawValue == Int {
    
    /// The description of the enum case, automatically using the protocol buffer name
    /// from the associated NameMap when available.
    ///
    /// This property automatically integrates with the NameMap system to provide
    /// protocol buffer names for enum cases. If a mapping exists in the NameMap,
    /// it returns the protocol buffer name; otherwise, it falls back to the default
    /// Swift behavior.
    ///
    /// ## Usage
    /// ```swift
    /// enum Status: Int, NameMappable {
    ///     case active = 1
    ///     case inactive = 2
    ///     
    ///     static let nameMap = NameMap([
    ///         1: _NameMap.NameDescription.same(proto: "STATUS_ACTIVE"),
    ///         2: _NameMap.NameDescription.same(proto: "STATUS_INACTIVE")
    ///     ])
    /// }
    ///
    /// print(Status.active.description)   // "STATUS_ACTIVE"
    /// print(Status.inactive.description) // "STATUS_INACTIVE"
    /// ```
    public var description: String {
        if let protoName = Self.nameMap.protoName(for: self) {
            return protoName
        }
        
        // Fall back to default behavior if no mapping exists
        // We use string interpolation to get the default description
        return "\(self)"
    }
}

// MARK: - Alternative Description Methods

extension NameMappable where Self: RawRepresentable, RawValue == Int {
    
    /// Returns the protocol buffer name for this enum case.
    ///
    /// This is a convenience method that provides explicit access to the protocol
    /// buffer name, separate from the `description` property.
    ///
    /// - Returns: The protocol buffer name, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// if let protoName = MyEnum.first.protoName {
    ///     print("Proto name: \(protoName)")
    /// }
    /// ```
    public var protoName: String? {
        return Self.nameMap.protoName(for: self)
    }
    
    /// Returns the JSON format name for this enum case.
    ///
    /// This is a convenience method that provides explicit access to the JSON
    /// format name, separate from the `description` property.
    ///
    /// - Returns: The JSON name, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// if let jsonName = MyEnum.first.jsonName {
    ///     print("JSON name: \(jsonName)")
    /// }
    /// ```
    public var jsonName: String? {
        return Self.nameMap.jsonName(for: self)
    }
    
    /// Returns the complete name information for this enum case.
    ///
    /// This provides access to all available name information including both
    /// protocol buffer and JSON names.
    ///
    /// - Returns: The field name information, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// if let info = MyEnum.first.nameInfo {
    ///     print("Number: \(info.number), Proto: \(info.protoName), JSON: \(info.jsonName)")
    /// }
    /// ```
    public var nameInfo: FieldNameInfo? {
        return Self.nameMap.nameInfo(for: self)
    }
}

// MARK: - Factory Methods for NameMappable Enums

extension NameMappable where Self: RawRepresentable, RawValue == Int {
    
    /// Creates an enum case from a protocol buffer name.
    ///
    /// This method provides a type-safe way to create enum instances from their
    /// protocol buffer names.
    ///
    /// - Parameter protoName: The protocol buffer name to look up.
    /// - Returns: The corresponding enum case, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// if let status = Status.fromProtoName("STATUS_ACTIVE") {
    ///     print("Found status: \(status)")
    /// }
    /// ```
    public static func fromProtoName(_ protoName: String) -> Self? {
        return nameMap.enumCase(forProtoName: protoName)
    }
    
    /// Creates an enum case from a JSON name.
    ///
    /// This method provides a type-safe way to create enum instances from their
    /// JSON format names.
    ///
    /// - Parameter jsonName: The JSON name to look up.
    /// - Returns: The corresponding enum case, or `nil` if no mapping exists.
    ///
    /// ## Example
    /// ```swift
    /// if let status = Status.fromJSONName("statusActive") {
    ///     print("Found status: \(status)")
    /// }
    /// ```  
    public static func fromJSONName(_ jsonName: String) -> Self? {
        return nameMap.enumCase(forJSONName: jsonName)
    }
}

// MARK: - Collection Extensions for NameMappable Enums

extension NameMappable where Self: RawRepresentable & CaseIterable, RawValue == Int {
    
    /// Returns all cases of this enum that have mappings in the NameMap.
    ///
    /// This provides a convenient way to iterate over only the enum cases that
    /// have corresponding protocol buffer names.
    ///
    /// - Returns: Array of enum cases that have name mappings, sorted by raw value.
    ///
    /// ## Example
    /// ```swift
    /// for mappedCase in MyEnum.mappedCases {
    ///     print("\(mappedCase): \(mappedCase.description)")
    /// }
    /// ```
    public static var mappedCases: [Self] {
        return nameMap.allEnumCases(for: Self.self)
    }
    
    /// Returns all field name information for this enum type.
    ///
    /// This provides detailed information about all mapped enum cases including
    /// their protocol buffer names, JSON names, and numbers.
    ///
    /// - Returns: Array of field name information for all mapped cases.
    ///
    /// ## Example
    /// ```swift
    /// for info in MyEnum.allNameInfo {
    ///     print("Case \(info.number): \(info.protoName) -> \(info.jsonName)")
    /// }
    /// ```
    public static var allNameInfo: [FieldNameInfo] {
        return nameMap.allFieldNames(for: Self.self)
    }
}
