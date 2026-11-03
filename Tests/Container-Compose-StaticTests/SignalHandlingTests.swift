//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richman and the Container-Compose project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import Testing
import Foundation
import Darwin
@testable import ContainerComposeCore

@Suite("Signal Handling and Child Process Tracking Tests", .serialized)
struct SignalHandlingTests {

    @Test("child spawned after the signal stream is installed still dies on forwarded SIGINT")
    func childDoesNotInheritIgnoredSigint() async throws {
        // Regression guard, not a fix: an ignored SIGINT survives exec and would make `container run`
        // immune to the SIGINT we forward. Foundation's Process currently resets dispositions for
        // children (verified empirically); this fails if that ever stops being true.
        signal(SIGINT, SIG_IGN)

        let registry = ActiveProcessRegistry()
        let started = Date()
        let exit = Task {
            try await ChildProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                registry: registry,
                onStdout: { _ in }, onStderr: { _ in }
            )
        }
        while registry.count() == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        registry.signalAll(SIGINT)
        _ = try await exit.value
        #expect(Date().timeIntervalSince(started) < 2.0)
        #expect(registry.count() == 0)
    }

    @Test("fast-exiting children never leave stale PIDs tracked (PID-reuse safety)")
    func fastChildrenLeaveNoStalePids() async throws {
        let registry = ActiveProcessRegistry()
        for _ in 0..<100 {
            _ = try await ChildProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [],
                registry: registry, onStdout: { _ in }, onStderr: { _ in }
            )
        }
        #expect(registry.count() == 0)
    }
}
