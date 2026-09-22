import Foundation
import NeedleFoundation

// Shared-protocols benchmark. One process = one sample:
//
//   pass #1  read every `shared` property once — constructs 10 000 instances
//   pass #2  read them all again — 10 000 cache hits, cold conformance cache
//   pass #3  and again — cache hits, warm conformance cache
//
// Every property is `var depN: ProtocolN { shared { let i = ClassN(); return i } }`,
// so `shared`'s `T` is the protocol. Pass #2 is the headline number: upstream
// Needle recovers the cached instance with `Any as? T?`, which for a protocol `T`
// makes the runtime look up ClassN's conformance to ProtocolN — on a cold cache,
// by walking the conformance records of every image.
//
// Pass #2 is only meaningful in a freshly launched process. run.sh spawns a new
// process per sample for exactly this reason.

func seconds(_ duration: Duration) -> Double {
    let (whole, atto) = duration.components
    return Double(whole) + Double(atto) * 1e-18
}

let emitJSON = CommandLine.arguments.contains("--json")

__DependencyProviderRegistry.instance.registerDependencyProviderFactory(for: "^->BenchComponent") { component in
    EmptyDependencyProvider(component: component)
}
let component = BenchComponent()

let clock = ContinuousClock()

var firstPass: [Any] = []
let firstDuration = clock.measure {
    firstPass = accessAll(component)
}

var secondPass: [Any] = []
let secondDuration = clock.measure {
    secondPass = accessAll(component)
}

var thirdPass: [Any] = []
let thirdDuration = clock.measure {
    thirdPass = accessAll(component)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

guard [firstPass.count, secondPass.count, thirdPass.count].allSatisfy({ $0 == benchTypeCount }) else {
    fail("accessed \(firstPass.count)/\(secondPass.count)/\(thirdPass.count) of \(benchTypeCount) properties")
}
// Every ClassN is a class, so `as AnyObject` just unwraps the reference.
func same(_ a: Any, _ b: Any) -> Bool { (a as AnyObject) === (b as AnyObject) }
for i in 0..<benchTypeCount where !same(firstPass[i], secondPass[i]) || !same(firstPass[i], thirdPass[i]) {
    fail("dep\(i) returned a different instance on a later pass; `shared` is not caching")
}

let first = seconds(firstDuration)
let second = seconds(secondDuration)
let third = seconds(thirdDuration)
let count = Double(benchTypeCount)

if emitJSON {
    print("""
    {"types":\(benchTypeCount),"pass1":\(first),"pass2":\(second),"pass3":\(third)}
    """)
} else {
    func line(_ label: String, _ total: Double) -> String {
        String(format: "%-8@ %8.4f s   %7.2f µs/call", label as NSString, total, total / count * 1e6)
    }
    print("types=\(benchTypeCount)")
    print(line("pass#1", first))
    print(line("pass#2", second))
    print(line("pass#3", third))
}
