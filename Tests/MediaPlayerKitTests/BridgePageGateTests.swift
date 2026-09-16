import XCTest
@testable import MediaPlayerKit

final class BridgePageGateTests: XCTestCase {
    func testOldDocumentCannotReopenGateDuringNavigation() {
        var gate = BridgePageGate()
        XCTAssertTrue(gate.accept("old", handshake: true, generation: gate.generation))
        gate.invalidate()
        let duringNavigation = gate.generation
        XCTAssertFalse(gate.accept("old", handshake: true, generation: duringNavigation))
        XCTAssertFalse(gate.accept("old", handshake: false, generation: duringNavigation))
        XCTAssertFalse(gate.accept(nil, handshake: false, generation: duringNavigation))
        XCTAssertTrue(gate.navigating)
        gate.commit()
        XCTAssertFalse(gate.accept("old", handshake: true, generation: duringNavigation))
        XCTAssertFalse(gate.accept("new", handshake: false, generation: gate.generation))
        XCTAssertTrue(gate.accept("new", handshake: true, generation: gate.generation))
        XCTAssertTrue(gate.accept("new", handshake: false, generation: gate.generation))
        XCTAssertFalse(gate.accept("old", handshake: false, generation: gate.generation))
    }
    func testLegacyCannotDowngradeModernSession() {
        var gate = BridgePageGate()
        XCTAssertTrue(gate.accept(nil, handshake: false, generation: gate.generation))
        XCTAssertTrue(gate.accept("page", handshake: true, generation: gate.generation))
        XCTAssertFalse(gate.accept(nil, handshake: false, generation: gate.generation))
        XCTAssertFalse(gate.accept("", handshake: true, generation: gate.generation))
    }
    func testCommittedBackNavigationCanReconnectRetainedDocument() {
        var gate = BridgePageGate()
        XCTAssertTrue(gate.accept("page", handshake: true, generation: gate.generation))
        let oldGeneration = gate.generation
        gate.invalidate()
        gate.commit()
        XCTAssertFalse(gate.accept("page", handshake: true, generation: oldGeneration))
        XCTAssertTrue(gate.accept("page", handshake: true, generation: gate.generation))
    }
}
