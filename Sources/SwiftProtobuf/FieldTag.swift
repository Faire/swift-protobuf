// Sources/SwiftProtobuf/FieldTag.swift - Describes a binary field tag
//
// Copyright (c) 2014 - 2016 Apple Inc. and the project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See LICENSE.txt for license information:
// https://github.com/apple/swift-protobuf/blob/main/LICENSE.txt
//
// -----------------------------------------------------------------------------
///
/// Types related to binary encoded tags (field numbers and wire formats).
///
// -----------------------------------------------------------------------------

/// Encapsulates the number and wire format of a field, which together form the
/// "tag".
///
/// This type also validates tags in that it will never allow a tag with an
/// improper field number (such as zero) or wire format (such as 6 or 7) to
/// exist. In other words, a `FieldTag`'s properties never need to be tested
/// for validity because they are guaranteed correct at initialization time.
package struct FieldTag: RawRepresentable {

    package typealias RawValue = UInt32

    /// The raw numeric value of the tag, which contains both the field number and
    /// wire format.
    package let rawValue: UInt32

    /// The field number component of the tag.
    package var fieldNumber: Int {
        Int(rawValue >> 3)
    }

    /// The wire format component of the tag.
    package var wireFormat: WireFormat {
        // This force-unwrap is safe because there are only two initialization
        // paths: one that takes a WireFormat directly (and is guaranteed valid at
        // compile-time), or one that takes a raw value but which only lets valid
        // wire formats through.
        WireFormat(rawValue: UInt8(rawValue & 7))!
    }

    /// A helper property that returns the number of bytes required to
    /// varint-encode this tag.
    package var encodedSize: Int {
        Varint.encodedSize(of: rawValue)
    }

    /// Creates a new tag from its raw numeric representation.
    ///
    /// Note that if the raw value given here is not a valid tag (for example, it
    /// has an invalid wire format), this initializer will fail.
    package init?(rawValue: UInt32) {
        // Verify that the field number and wire format are valid and fail if they
        // are not.
        guard rawValue & ~0x07 != 0,
            let _ = WireFormat(rawValue: UInt8(rawValue % 8))
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    /// Creates a new tag by composing the given field number and wire format.
    package init(fieldNumber: Int, wireFormat: WireFormat) {
        self.rawValue = UInt32(truncatingIfNeeded: fieldNumber) << 3 | UInt32(wireFormat.rawValue)
    }
}
