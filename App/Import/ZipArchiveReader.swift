import Compression
import Foundation

/// Reads the files in a .zip archive, such as a YNAB plan export. Handles stored and
/// deflated entries, which is what Finder, iOS and web exports produce.
struct ZipArchiveReader {
  struct Entry {
    var name: String
    var data: Data
  }

  enum ZipError: LocalizedError {
    case notAnArchive
    case unsupportedEntry(String)

    var errorDescription: String? {
      switch self {
      case .notAnArchive: "The file isn’t a readable zip archive."
      case .unsupportedEntry(let name): "“\(name)” in the zip archive couldn’t be read."
      }
    }
  }

  static func isArchive(_ data: Data) -> Bool {
    data.count >= 4 && data.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04])
  }

  /// Every file in the archive, in archive order. Folders and macOS metadata are skipped.
  func entries(in data: Data) throws -> [Entry] {
    let bytes = [UInt8](data)
    guard let end = endOfCentralDirectory(in: bytes) else { throw ZipError.notAnArchive }
    let count = Int(bytes.uint16(at: end + 10))
    var offset = Int(bytes.uint32(at: end + 16))
    var entries: [Entry] = []
    for _ in 0..<count {
      guard offset + 46 <= bytes.count, bytes.uint32(at: offset) == 0x0201_4B50 else {
        throw ZipError.notAnArchive
      }
      let method = bytes.uint16(at: offset + 10)
      let compressedSize = Int(bytes.uint32(at: offset + 20))
      let size = Int(bytes.uint32(at: offset + 24))
      let nameLength = Int(bytes.uint16(at: offset + 28))
      let extraLength = Int(bytes.uint16(at: offset + 30))
      let commentLength = Int(bytes.uint16(at: offset + 32))
      let localOffset = Int(bytes.uint32(at: offset + 42))
      guard offset + 46 + nameLength <= bytes.count else { throw ZipError.notAnArchive }
      let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
      offset += 46 + nameLength + extraLength + commentLength

      if name.hasSuffix("/") || name.hasPrefix("__MACOSX/") { continue }
      guard localOffset + 30 <= bytes.count, bytes.uint32(at: localOffset) == 0x0403_4B50 else {
        throw ZipError.unsupportedEntry(name)
      }
      let dataStart = localOffset + 30
        + Int(bytes.uint16(at: localOffset + 26)) + Int(bytes.uint16(at: localOffset + 28))
      guard dataStart + compressedSize <= bytes.count else { throw ZipError.unsupportedEntry(name) }
      let compressed = bytes[dataStart..<(dataStart + compressedSize)]
      switch method {
      case 0:
        entries.append(Entry(name: name, data: Data(compressed)))
      case 8:
        entries.append(Entry(name: name, data: try inflate(Array(compressed), size: size, name: name)))
      default:
        throw ZipError.unsupportedEntry(name)
      }
    }
    return entries
  }

  /// The end-of-central-directory record sits in the last 64 KB, before any archive comment.
  private func endOfCentralDirectory(in bytes: [UInt8]) -> Int? {
    guard bytes.count >= 22 else { return nil }
    let lowest = max(0, bytes.count - 22 - 65_535)
    return stride(from: bytes.count - 22, through: lowest, by: -1)
      .first { bytes.uint32(at: $0) == 0x0605_4B50 }
  }

  /// Zip's deflate is raw DEFLATE, which is what Compression's zlib algorithm decodes.
  private func inflate(_ source: [UInt8], size: Int, name: String) throws -> Data {
    guard size > 0 else { return Data() }
    var output = [UInt8](repeating: 0, count: size)
    let written = compression_decode_buffer(&output, size, source, source.count, nil, COMPRESSION_ZLIB)
    guard written == size else { throw ZipError.unsupportedEntry(name) }
    return Data(output)
  }
}

private extension [UInt8] {
  func uint16(at offset: Int) -> UInt16 {
    UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
  }

  func uint32(at offset: Int) -> UInt32 {
    UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
      | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
  }
}
