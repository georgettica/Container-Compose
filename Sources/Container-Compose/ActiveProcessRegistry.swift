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

import Foundation

/// Tracks child processes spawned by container-compose so an interrupt can signal them
/// and verify they are gone. ``ChildProcessRunner`` is the
/// only place that registers/unregisters, and always unregisters on exit.
final class ActiveProcessRegistry: @unchecked Sendable {
    static let shared = ActiveProcessRegistry()
    private let lock = NSLock()
    private var activePids: Set<pid_t> = []

    func register(_ pid: pid_t) { lock.withLock { _ = activePids.insert(pid) } }

    func unregister(_ pid: pid_t) { lock.withLock { _ = activePids.remove(pid) } }

    func signalAll(_ sig: Int32) {
        let pids = lock.withLock { activePids }
        for pid in pids { kill(pid, sig) }
    }

    func count() -> Int { lock.withLock { activePids.count } }
}
