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
        // In default compatible mode, legacy calls can coexist without clearing the modern session.
        XCTAssertTrue(gate.accept(nil, handshake: false, generation: gate.generation))
        XCTAssertEqual(gate.pageID, "page")
        XCTAssertTrue(gate.accept("page", handshake: false, generation: gate.generation))
        XCTAssertFalse(gate.accept("stale", handshake: false, generation: gate.generation))
        XCTAssertFalse(gate.accept("", handshake: true, generation: gate.generation))

        // In strict mode, legacy calls without pageId are rejected once modern pageId is set.
        gate.strict = true
        XCTAssertFalse(gate.accept(nil, handshake: false, generation: gate.generation))
        XCTAssertTrue(gate.accept("page", handshake: false, generation: gate.generation))
    }
    func testMixedLegacyAndModernCoexistence() {
        var gate = BridgePageGate()
        XCTAssertFalse(gate.strict)
        XCTAssertTrue(gate.accept("session-1", handshake: true, generation: gate.generation))
        // Multiple alternating modern and legacy calls in compatible mode:
        XCTAssertTrue(gate.accept(nil, handshake: false, generation: gate.generation))
        XCTAssertTrue(gate.accept("session-1", handshake: false, generation: gate.generation))
        XCTAssertTrue(gate.accept(nil, handshake: false, generation: gate.generation))
        XCTAssertEqual(gate.pageID, "session-1")
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
