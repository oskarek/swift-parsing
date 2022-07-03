import Parsing
import XCTest

final class PrefixThroughTests: XCTestCase {
  func testSuccess() {
    var input = "Hello,world, 42!"[...]
    XCTAssertEqual("Hello,world, ", try Prefix(through: ", ").parse(&input))
    XCTAssertEqual("42!", input)
  }

  func testSuccessIsEmpty() {
    var input = "Hello, world!"[...]
    XCTAssertEqual("", try Prefix(through: "").parse(&input))
    XCTAssertEqual("Hello, world!", input)
  }

  func testFailureIsEmpty() {
    var input = ""[...]
    XCTAssertThrowsError(try Prefix(through: ", ").parse(&input)) { error in
      XCTAssertEqual(
        """
        error: unexpected input
         --> input:1:1
        1 |
          | ^ expected prefix through ", "
        """,
    "\(error)"
      )
    }
    XCTAssertEqual("", input)
  }

  func testFailureNoMatch() {
    var input = "Hello world!"[...]
    XCTAssertThrowsError(try Prefix(through: ", ").parse(&input)) { error in
      XCTAssertEqual(
        """
        error: unexpected input
         --> input:1:1
        1 | Hello world!
          | ^ expected prefix through ", "
        """,
        "\(error)"
      )
    }
    XCTAssertEqual("Hello world!", input)
  }

  func testUTF8() {
    var input = "Hello,world, 42!"[...].utf8
    XCTAssertEqual("Hello,world, ", Substring(try Prefix(through: ", "[...].utf8).parse(&input)))
    XCTAssertEqual("42!", Substring(input))
  }

  func testPrint() throws {
    var input = ""[...]
    try Prefix(through: ",").print("Hello,", into: &input)
    XCTAssertEqual("Hello,", input)
  }

  func testPrefixRangeFromFailure() {
    var input = "42 Hello, world!"[...]
    XCTAssertThrowsError(try Prefix(17..., through: "world!").parse(&input)) { error in
      XCTAssertEqual(
        """
        error: unexpected input
         --> input:1:11
        1 | 42 Hello, world!
          |           ^ expected 1 more element before the prefix end sequence
        """,
        "\(error)"
      )
    }
    XCTAssertEqual("", input)
  }
}
