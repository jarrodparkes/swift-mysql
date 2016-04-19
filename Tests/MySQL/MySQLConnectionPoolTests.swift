import Foundation
import XCTest

@testable import MySQL

public class MySQLConnectionPoolTests: XCTestCase {

  var mockConnection = MockMySQLConnection()

  public override func setUp() {
    mockConnection = MockMySQLConnection()
    MySQLConnectionPool.setConnectionProvider() {
      return self.mockConnection
    }

    MySQLConnectionPool.activeConnections = [String: [MySQLConnectionProtocol]]()
    MySQLConnectionPool.inactiveConnections = [String: [MySQLConnectionProtocol]]()
  }

  public func testSetsPoolSize() {
    MySQLConnectionPool.setPoolSize(10)

    XCTAssertEqual(10, MySQLConnectionPool.poolSize)
  }

  public func testConnectionConnectCalled() {
    do {
      var _ = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "")!

      XCTAssertTrue(mockConnection.connectCalled, "Connect should have been called")
    } catch {
      XCTFail("Unable to create connection")
    }
  }

  public func testGetConnectionWithNoInactiveConnectionsCreatesANewConnection() {
    do {
      let connection = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "")!

      XCTAssertTrue(connection.equals(mockConnection), "Should have used connection from pool")
    } catch {
      XCTFail("Unable to create connection")
    }
  }

  public func testGetConnectionWithNoInactiveConnectionsAddsAnActivePoolItem() {
    do {
      var _ = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "")!

      XCTAssertEqual(1, MySQLConnectionPool.activeConnections.values.first?.count, "Active connections should contain 1 item")
    } catch {
      XCTFail("Unable to create connection")
    }
  }

  public func testGetConnectionWithInactivePoolItemUsesExistingConnection() {
    do {
      var inactiveConnections = [MySQLConnectionProtocol]()
      let tempConnection = MockMySQLConnection()
      inactiveConnections.append(tempConnection)

      MySQLConnectionPool.inactiveConnections["192.168.99.100_root_my-secret-pw_test"] = inactiveConnections

      let connection = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "test")!

      XCTAssertTrue(connection.equals(tempConnection), "Should have used connection from pool")
      XCTAssertEqual(1, MySQLConnectionPool.activeConnections.values.first?.count, "There should be no active connections")
      XCTAssertEqual(0, MySQLConnectionPool.inactiveConnections.values.first?.count, "There should be one inactive connections")
    } catch {
      XCTFail("Unable to create connection")
    }
  }

  public func testGetConnectionNoInactiveConnectionsAddsAnActivePoolItemWithAValidKey() {
    do {
      var _ = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "test")!

      XCTAssertEqual("192.168.99.100_root_my-secret-pw_test", MySQLConnectionPool.activeConnections.keys.first!, "Key should have correct value")
    } catch {
      XCTFail("Unable to create connection")
    }
  }

  public func testReleaseConnectionReturnsConnectionToThePool() {
    do {
      let connection = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "test")!
      MySQLConnectionPool.releaseConnection(connection)

      XCTAssertEqual(0, MySQLConnectionPool.activeConnections.values.first?.count, "There should be no active connections")
      XCTAssertEqual(1, MySQLConnectionPool.inactiveConnections.values.first?.count, "There should be one inactive connections")
    } catch {
      XCTFail("Unable to create connection")
    }
  }

  // Async tests are not currently implemented for Swift mac 24_03 release
  #if os(Linux)
  var timer = 0.0

  public func testGetConnectionBlocksWhenPoolIsExhausted() {
    let expectation = expectationWithDescription("Should have blocked when no pool connections are available")

    do {
      MySQLConnectionPool.poolSize = 1
      let connection = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "test")!

      let thread = NSThread() { () -> Void in
        do {
          let startTime = NSDate().timeIntervalSince1970
          let _ = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "test")!

          let endTime = NSDate().timeIntervalSince1970
          self.timer = endTime - startTime

          expectation.fulfill()
        } catch {}
      }

      thread.start()

      sleep(1)

      MySQLConnectionPool.releaseConnection(connection)

    } catch {
      XCTFail("Unable to create connection")
    }

    waitForExpectationsWithTimeout(3) { error in
      if let error = error {
        XCTFail("Error: \(error.localizedDescription)")
      }
    }

    //test equal elapsed time + delay interval
    XCTAssertTrue((timer >= 1), "getConnection should have blocked for 1 second")
  }

  public func testGetConnectionTimesoutWhenPoolIsExhausted() {
    let expectation = expectationWithDescription("MySQLConnectionPool getConnection should have timedout")

    do {
      MySQLConnectionPool.poolSize = 1
      MySQLConnectionPool.poolTimeout = 1
      let _ = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "test")!

      let thread = NSThread() { () -> Void in
        do {
          let _ = try MySQLConnectionPool.getConnection("192.168.99.100", user: "root", password: "my-secret-pw", port: 3306, database: "test")!
        } catch {
          expectation.fulfill()
        }
      }

      thread.start()
    } catch {
      XCTFail("Unable to create connection")
    }

    waitForExpectationsWithTimeout(3) { error in
      if let error = error {
        XCTFail("Error: \(error.localizedDescription)")
      }
    }
  }
  #else
  public func testGetConnectionBlocksWhenPoolIsExhausted() {}
  public func testGetConnectionTimesoutWhenPoolIsExhausted() {}
  #endif
}

extension MySQLConnectionPoolTests {
  static var allTests: [(String, MySQLConnectionPoolTests -> () throws -> Void)] {
    return [
      ("testSetsPoolSize", testSetsPoolSize),
      ("testConnectionConnectCalled", testConnectionConnectCalled),
      ("testGetConnectionWithNoInactiveConnectionsCreatesANewConnection", testGetConnectionWithNoInactiveConnectionsCreatesANewConnection),
      ("testGetConnectionWithNoInactiveConnectionsAddsAnActivePoolItem", testGetConnectionWithNoInactiveConnectionsAddsAnActivePoolItem),
      ("testGetConnectionWithInactivePoolItemUsesExistingConnection", testGetConnectionWithInactivePoolItemUsesExistingConnection),
      ("testGetConnectionNoInactiveConnectionsAddsAnActivePoolItemWithAValidKey", testGetConnectionNoInactiveConnectionsAddsAnActivePoolItemWithAValidKey),
      ("testReleaseConnectionReturnsConnectionToThePool", testReleaseConnectionReturnsConnectionToThePool),
      ("testGetConnectionBlocksWhenPoolIsExhausted", testGetConnectionBlocksWhenPoolIsExhausted),
      ("testGetConnectionTimesoutWhenPoolIsExhausted", testGetConnectionTimesoutWhenPoolIsExhausted)
    ]
  }
}
