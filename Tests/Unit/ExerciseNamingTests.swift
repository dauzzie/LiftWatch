import XCTest
#if canImport(LiftWatchIOS)
@testable import LiftWatchIOS
#elseif canImport(LiftWatch)
@testable import LiftWatch
#else
#error("Unable to import app module for tests.")
#endif

final class ExerciseNamingTests: XCTestCase {
    func testCardioSymbolNameIsHumanized() {
        let value = ExerciseNaming.displayName(name: "figure.run", symbol: "figure.run", category: .cardio)
        XCTAssertEqual(value, "Run")
    }

    func testRegularNameRemainsUnchanged() {
        let value = ExerciseNaming.displayName(name: "Deadlift", symbol: "bolt.heart.fill", category: .weightlifting)
        XCTAssertEqual(value, "Deadlift")
    }
}
