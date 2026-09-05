import Foundation
import XCTest
@testable import TreadUpdater

final class CoordinateParserTests: XCTestCase {
    struct CoordinateCase: Decodable {
        let input: String
        let format: String?
        let lat: String?
        let lng: String?
        let warning: Bool?
        let error: String?
    }

    func testSharedCoordinateCasesMatchTheCanonicalContract() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "coordinate-cases", withExtension: "json"))
        let cases = try JSONDecoder().decode([CoordinateCase].self, from: Data(contentsOf: url))

        for item in cases {
            if let expectedError = item.error {
                XCTAssertThrowsError(try CoordinateParser.parse(item.input), item.input) { error in
                    XCTAssertEqual(String(describing: error), expectedError)
                }
                continue
            }
            let result = try CoordinateParser.parse(item.input)
            XCTAssertEqual(result.inputFormat == .dms ? "dms" : "decimal", item.format, item.input)
            XCTAssertEqual(result.latitudeText, item.lat, item.input)
            XCTAssertEqual(result.longitudeText, item.lng, item.input)
            XCTAssertEqual(!result.warnings.isEmpty, item.warning, item.input)
        }
    }
}
