public struct Prefix<Input: Collection>: Parser where Input.SubSequence == Input {
  public let maximum: Int?
  public let minimum: Int
  public let ending: Ending<Input>?

  public enum Ending<Input: Collection> {
    case elemSatisfies((Input.Element) -> Bool)
    case subSeqMatches(Input.SubSequence, by: (Input.Element, Input.Element) -> Bool, includeMatch: Bool)

    /// The number of elements of the ending that should be included in the prefix.
    public var includedCount: Int {
      switch self {
      case .elemSatisfies:
        return 0
      case let .subSeqMatches(subSequence, _, includeMatch):
        return includeMatch ? subSequence.count : 0
      }
    }
  }

  @inlinable
  @inline(__always)
  public func parse(_ input: inout Input) throws -> Input {
    // extract the prefix of the input
    let prefix: Input
    let maxLength = min(input.count, self.maximum ?? input.count)
    switch ending {
    case nil:
      prefix = maximum.map(input.prefix) ?? input
    case .elemSatisfies(let predicate):
      prefix = input.prefix(maxLength).prefix(while: { !predicate($0) })
    case .subSeqMatches(let subSeq, let areEquivalent, let includeMatch):
      let maxSubSeqOffset = maxLength - (includeMatch ? subSeq.count : 0)
      guard let endIndex = input.indices.prefix(max(0, maxSubSeqOffset + 1))
        .first(where: { input[$0...].starts(with: subSeq, by: areEquivalent) })
        .map({ input.index($0, offsetBy: includeMatch ? subSeq.count : 0) })
      else {
        throw ParsingError.expectedInput("prefix \(includeMatch ? "through" : "up to") \(formatValue(subSeq))", at: input)
      }
      prefix = input.prefix(upTo: endIndex)
    }

    // check for minimum count
    let count = prefix.count
    guard count >= self.minimum else {
      let includedEndingCount = ending?.includedCount ?? 0
      input.removeFirst(count - includedEndingCount)
      defer { input.removeFirst(includedEndingCount) }
      let atLeast = self.minimum - count
      let messagePrefix = "\(atLeast) \(count == includedEndingCount ? "" : "more ")element\(atLeast == 1 ? "" : "s")"
      switch ending {
      case nil:
        throw ParsingError.expectedInput(messagePrefix, at: input)
      case .elemSatisfies:
        throw ParsingError.expectedInput(messagePrefix + " satisfying predicate", at: input)
      case .subSeqMatches:
        throw ParsingError.expectedInput(messagePrefix + " before the prefix end sequence", at: input)
      }
    }

    input.removeFirst(count)
    return prefix
  }
}

extension Prefix: ParserPrinter where Input: PrependableCollection {
  @inlinable
  public func print(_ output: Input, into input: inout Input) throws {
    let count = output.count
    guard count >= self.minimum
    else {
      let description = describe(input).map { "\n\n\($0.debugDescription)" } ?? ""
      throw PrintingError.failed(
        summary: """
          round-trip expectation failed

          A "Prefix" parser that parses at least \(self.minimum) \
          element\(self.minimum == 1 ? "" : "s") was given only \(count) \
          element\(count == 1 ? "" : "s") to print.\(description)
          """,
        input: input
      )
    }
    if let maximum = self.maximum {
      guard count <= maximum
      else {
        let description = describe(input).map { "\n\n\($0.debugDescription)" } ?? ""
        throw PrintingError.failed(
          summary: """
            round-trip expectation failed

            A "Prefix" parser that parses at most \(maximum) element\(maximum == 1 ? "" : "s") was \
            given \(count) element\(count == 1 ? "" : "s") to print.\(description)
            """,
          input: input
        )
      }
    }

    if let ending = ending {
      switch ending {
      case let .elemSatisfies(predicate):
        guard output.allSatisfy({ !predicate($0) })
        else {
          throw PrintingError.failed(
            summary: """
              round-trip expectation failed

              A "Prefix" parser's predicate failed to satisfy all elements it was handed to print.

              During a round-trip, the "Prefix" parser would have stopped parsing at this element, \
              which means its data is in an invalid state.
              """,
            input: input
          )
        }
        guard input.first.map(predicate) != false
        else {
          throw PrintingError.failed(
            summary: """
              round-trip expectation failed

              A "Prefix" parser's predicate satisfied the first element printed by the next printer.

              During a round-trip, the "Prefix" parser would have parsed this element, which means \
              the data handed to the next printer is in an invalid state.
              """,
            input: input
          )
        }

      case let .subSeqMatches(subSeq, areEquivalent, includeMatch):
        if includeMatch {
          guard (try? self.parse(output)) != nil else {
            throw PrintingError.failed(
              summary: """
                round-trip expectation failed

                A "Prefix(through:)" parser-printer attempted to print a collection that could not have \
                been parsed.
                """,
              input: input
            )
          }
        } else {
          guard input.starts(with: subSeq, by: areEquivalent)
          else {
            throw PrintingError.failed(
              summary: """
                round-trip expectation failed

                A "Prefix(upTo:)" parser-printer expected its match to be printed next, but no such match \
                was printed.

                During a round-trip, the parser would have continued parsing up to the match or the end \
                of input.
                """,
              input: input
            )
          }
          var output = output
          guard (try? self.parse(&output)) == nil else {
            throw PrintingError.failed(
              summary: """
                round-trip expectation failed

                A "Prefix(upTo:)" parser-printer was given a value to print that contained the match it \
                parses up to.

                During a round-trip, the parser would have only parsed up to this match.
                """,
              input: input
            )
          }
        }
      }
    }
    input.prepend(contentsOf: output)
  }
}

extension Prefix {
  /// Initializes a parser that consumes a subsequence from the beginning of its input.
  ///
  /// ```swift
  /// try Prefix(1...) { $0.isNumber }.parse("123456")  // "123456"
  ///
  /// try Prefix(1...) { $0.isNumber }.parse("")
  /// // error: unexpected input
  /// //  --> input:1:1
  /// // 1 |
  /// //   | ^ expected 1 more element satisfying predicate
  /// ```
  ///
  /// - Parameters:
  ///   - length: A length that provides a minimum number and maximum of elements to consume for
  ///     parsing to be considered successful.
  ///   - predicate: An optional closure that takes an element of the input sequence as its argument
  ///     and returns `true` if the element should be included or `false` if it should be excluded.
  ///     Once the predicate returns `false` it will not be called again.
  @inlinable
  public init<R: CountingRange>(_ length: R, while predicate: ((Input.Element) -> Bool)? = nil) {
    self.minimum = length.minimum
    self.maximum = length.maximum
    self.ending = predicate.map { pred in .elemSatisfies { !pred($0) } }
  }

  @inlinable
  public init(
    through possibleMatch: Input,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool
  ) {
    self.minimum = 0
    self.maximum = nil
    self.ending = .subSeqMatches(possibleMatch, by: areEquivalent, includeMatch: true)
  }

  @inlinable
  public init(
    upTo possibleMatch: Input,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool
  ) {
    self.minimum = 0
    self.maximum = nil
    self.ending = .subSeqMatches(possibleMatch, by: areEquivalent, includeMatch: false)
  }

  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    through possibleMatch: Input,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool
  ) {
    self.minimum = length.minimum
    self.maximum = length.maximum
    self.ending = .subSeqMatches(possibleMatch, by: areEquivalent, includeMatch: true)
  }

  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    upTo possibleMatch: Input,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool
  ) {
    self.minimum = length.minimum
    self.maximum = length.maximum
    self.ending = .subSeqMatches(possibleMatch, by: areEquivalent, includeMatch: false)
  }

  /// Initializes a parser that consumes a subsequence from the beginning of its input.
  ///
  /// ```swift
  /// try Prefix { $0.isNumber }.parse("123456")  // "123456"
  /// ```
  ///
  /// - Parameters:
  ///   - length: A length that provides a minimum number and maximum of elements to consume for
  ///     parsing to be considered successful.
  ///   - predicate: An closure that takes an element of the input sequence as its argument and
  ///     returns `true` if the element should be included or `false` if it should be excluded. Once
  ///     the predicate returns `false` it will not be called again.
  @inlinable
  public init(while predicate: ((Input.Element) -> Bool)? = nil) {
    self.minimum = 0
    self.maximum = nil
    self.ending = predicate.map { pred in .elemSatisfies { !pred($0) } }
  }
}

extension Prefix where Input.Element: Equatable {
  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    through possibleMatch: Input
  ) {
    self.init(length, through: possibleMatch, by: ==)
  }

  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    upTo possibleMatch: Input
  ) {
    self.init(length, upTo: possibleMatch, by: ==)
  }

  @inlinable
  public init(through possibleMatch: Input) {
    self.init(through: possibleMatch, by: ==)
  }

  @inlinable
  public init(upTo possibleMatch: Input) {
    self.init(upTo: possibleMatch, by: ==)
  }
}

extension Prefix where Input == Substring {
  @_disfavoredOverload
  @inlinable
  public init(
    through possibleMatch: String,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(through: possibleMatch[...], by: areEquivalent)
  }

  @_disfavoredOverload
  @inlinable
  public init(
    upTo possibleMatch: String,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(upTo: possibleMatch[...], by: areEquivalent)
  }

  @_disfavoredOverload
  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    through possibleMatch: String,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(length, through: possibleMatch[...], by: areEquivalent)
  }

  @_disfavoredOverload
  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    upTo possibleMatch: String,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(length, upTo: possibleMatch[...], by: areEquivalent)
  }
}

extension Prefix where Input == Substring.UTF8View {
  @_disfavoredOverload
  @inlinable
  public init(
    through possibleMatch: String.UTF8View,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(through: String(possibleMatch)[...].utf8, by: areEquivalent)
  }

  @_disfavoredOverload
  @inlinable
  public init(
    upTo possibleMatch: String.UTF8View,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(upTo: String(possibleMatch)[...].utf8, by: areEquivalent)
  }

  @_disfavoredOverload
  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    through possibleMatch: String.UTF8View,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(length, through: String(possibleMatch)[...].utf8, by: areEquivalent)
  }

  @_disfavoredOverload
  @inlinable
  public init<R: CountingRange>(
    _ length: R,
    upTo possibleMatch: String.UTF8View,
    by areEquivalent: @escaping (Input.Element, Input.Element) -> Bool = (==)
  ) {
    self.init(length, upTo: String(possibleMatch)[...].utf8, by: areEquivalent)
  }
}

extension Prefix where Input == Substring {
  @_disfavoredOverload
  @inlinable
  public init<R: CountingRange>(_ length: R, while predicate: ((Input.Element) -> Bool)? = nil) {
    self.init(length, while: predicate)
  }

  @_disfavoredOverload
  @inlinable
  public init(while predicate: @escaping (Input.Element) -> Bool) {
    self.init(while: predicate)
  }
}

extension Prefix where Input == Substring.UTF8View {
  @_disfavoredOverload
  @inlinable
  public init<R: CountingRange>(_ length: R, while predicate: ((Input.Element) -> Bool)? = nil) {
    self.init(length, while: predicate)
  }

  @_disfavoredOverload
  @inlinable
  public init(while predicate: @escaping (Input.Element) -> Bool) {
    self.init(while: predicate)
  }
}

extension Parsers {
  public typealias Prefix = Parsing.Prefix  // NB: Convenience type alias for discovery
}
