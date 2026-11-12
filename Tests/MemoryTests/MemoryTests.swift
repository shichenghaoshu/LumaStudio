import XCTest
import PhotoCore
final class MemoryTests: XCTestCase {
    func testOnlyExplicitConfirmationUpdatesPreferencesAndClearPersists() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let memory=try LocalPreferenceMemory(directory:root)
        let before=await memory.preferences();XCTAssertEqual(before.confirmationCount,0)
        var recipe=EditRecipe();recipe.global.temperature=7200;recipe.beauty.strength=0.25
        try await memory.remember(recipe)
        let reloaded=try LocalPreferenceMemory(directory:root),saved=await reloaded.preferences();XCTAssertEqual(saved.confirmationCount,1);XCTAssertEqual(saved.temperature,7200)
        try await reloaded.clear()
        let cleared=try LocalPreferenceMemory(directory:root),empty=await cleared.preferences();XCTAssertEqual(empty.confirmationCount,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("training.jsonl").path))
    }
}
