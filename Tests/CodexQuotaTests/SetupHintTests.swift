import XCTest
@testable import CodexQuota

final class SetupHintTests: XCTestCase {
    func testMissingCLIHasPriorityOverOtherFailures() {
        var state = QuotaState()
        state.connection = .disconnected(.cliNotFound)
        state.lastFailure = .noRateLimitData
        XCTAssertEqual(state.setupHint, L10n.setupMissingCLI)
    }

    func testLoggedOutOffersLogin() {
        var state = QuotaState()
        state.account = AccountInfo(loggedIn: false, email: nil, planType: nil,
                                    requiresAuth: true, accountType: nil)
        XCTAssertEqual(state.setupHint, L10n.setupLogin)
    }

    func testFailureAndRecovery() {
        var state = QuotaState()
        XCTAssertNil(state.setupHint)
        state.connection = .connected
        state.lastFailure = .noRateLimitData
        XCTAssertEqual(state.setupHint, L10n.setupReadFailed)
        state.lastFailure = nil
        XCTAssertNil(state.setupHint)
    }
}
