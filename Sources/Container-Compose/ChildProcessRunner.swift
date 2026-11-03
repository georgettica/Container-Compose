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

/// Spawns a child process, streams its output, and tracks it in an
/// ``ActiveProcessRegistry`` so interrupts can signal and verify it.
enum ChildProcessRunner {
    /// Runs `executable`, streams stdout/stderr through the closures, and returns
    /// the exit status once the process terminates.
    @discardableResult
    static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        registry: ActiveProcessRegistry = .shared,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice  // never share the host terminal
            if let environment { process.environment = environment }

            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            func stream(_ handle: FileHandle, to sink: @escaping @Sendable (String) -> Void) {
                handle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return }
                    sink(string)
                }
            }
            stream(stdoutHandle, to: onStdout)
            stream(stderrHandle, to: onStderr)

            process.terminationHandler = { proc in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                registry.unregister(proc.processIdentifier)
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                registry.register(process.processIdentifier)
                // A fast child can finish before register(): its termination handler already
                // ran unregister(), so drop the entry we just added or it goes stale.
                if !process.isRunning { registry.unregister(process.processIdentifier) }
            } catch {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
