//
//  Copyright (c) 2018. Uber Technologies
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

/// Box for an instance cached by `Component.shared`.
///
/// `shared` stores these instead of the bare instance so it can read the cache back
/// with `as? SharedInstance<T>`, a check against one concrete class. Casting the
/// bare `Any` with `as? T` instead makes the Swift runtime look up the stored type's
/// conformance when `T` is a protocol, which, before the runtime's conformance cache
/// is warm, means scanning every conformance record in the binary.
final class SharedInstance<T> {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}
