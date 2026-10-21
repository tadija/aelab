import Testing
@testable import Core

@Test func basePathNormalizesRootAndPreservesPathBoundaries() throws {
    #expect(try WebBasePath().root == "/")
    #expect(try WebBasePath("/").value == "")
    let base = try WebBasePath("/lab/aelab/")
    #expect(base.root == "/lab/aelab/")
    #expect(base.relative("/lab/aelab") == "")
    #expect(base.relative("/lab/aelab/api/config") == "/api/config")
    #expect(base.relative("/lab/aelab-other/api/config") == nil)
    #expect(base.relative("/api/config") == nil)
}
@Test func basePathRejectsAmbiguousAndUnsafePrefixes() {
    for path in ["aelab", "//evil", "/a//b", "/a/../b", "/a/./b", "/a%2fb", "/a?b", "/a#b", "/a b", "/a\"b", "/a\nb"] {
        #expect(throws: (any Error).self) { _ = try WebBasePath(path) }
    }
}
