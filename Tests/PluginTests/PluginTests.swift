import XCTest
import PhotoCore

final class PluginTests: XCTestCase {
    private let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private func example(_ name: String) throws -> PluginPackage {try PluginPackage.decode(Data(contentsOf:root.appendingPathComponent("Resources/Plugins/Examples/studio.luma.\(name).lumaplugin")))}
    private func temporary() throws -> URL {let u=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:u)};return u}
    func testFourTypesRoundTripAndAllInvocationContextsAreDeclared() throws {
        for name in ["warm-light","clear-portrait","subject-light","portrait-assistant"] {
            let p=try example(name);XCTAssertEqual(try PluginPackage.decode(p.encoded()),p)
            XCTAssertEqual(Set(p.manifest.supports),Set(PluginContext.allCases))
        }
    }
    func testRejectsTamperedAssetsUnknownExecutionFieldsAndUnsupportedCapabilities() throws {
        var p=try example("warm-light");p.assets[0].data=Data("not a cube".utf8).base64EncodedString();XCTAssertThrowsError(try p.validate())
        p=try example("warm-light");p.assets[0].path="../escape.cube";XCTAssertThrowsError(try p.validate())
        p=try example("warm-light");p.assets[0]=PluginAsset(path:"bad.cube",bytes:Data("LUT_3D_SIZE 65\n0 0 0\n".utf8));p.payload.lutAsset="bad.cube";XCTAssertThrowsError(try p.validate())
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:example("portrait-assistant").encoded()) as? [String:Any]);json["script"]="shell command"
        XCTAssertThrowsError(try PluginPackage.decode(JSONSerialization.data(withJSONObject:json)))
        p=try example("clear-portrait");p.payload.groups=[.geometry];XCTAssertThrowsError(try p.validate())
        p=try example("subject-light");p.payload.mask?.kind = .hair;XCTAssertThrowsError(try p.validate())
        p=try example("clear-portrait");p.manifest.capabilities=[.planner];XCTAssertThrowsError(try p.validate())
        p=try example("clear-portrait");p.manifest.version="../1";XCTAssertThrowsError(try p.validate())
    }
    func testEditorBatchAndAgentUseSameRecipeCompilerAndPreserveTargetState() async throws {
        let p=try example("clear-portrait")
        var base=EditRecipe();base.geometry.cropAspect=1.25;base.global.temperature=5720
        base.raw.exposure=0.4;base.color.intensity=0.31;base.masks=[LocalMask(id:"brush-own",kind:.brush)]
        base.export.nameTemplate="{name}_client";base.lockedParameters=["global.exposure","beauty"]
        var outputs=[EditRecipe]()
        for context in PluginContext.allCases {
            let result=try await PluginRuntime.execute(p,on:base,context:context)
            XCTAssertEqual(result.context,context);outputs.append(result.recipe)
            XCTAssertEqual(result.recipe.geometry,base.geometry);XCTAssertEqual(result.recipe.raw,base.raw)
            XCTAssertEqual(result.recipe.masks,base.masks);XCTAssertEqual(result.recipe.export,base.export)
            XCTAssertEqual(result.recipe.lockedParameters,base.lockedParameters);XCTAssertEqual(result.recipe.beauty,base.beauty)
            XCTAssertEqual(result.recipe.global.exposure,base.global.exposure);XCTAssertEqual(result.recipe.global.temperature,5720)
            XCTAssertEqual(result.recipe.global.contrast,1.06);XCTAssertEqual(result.recipe.color.intensity,0.31)
        }
        XCTAssertEqual(outputs[0],outputs[1]);XCTAssertEqual(outputs[1],outputs[2])
    }
    func testLocalPluginIsIdempotentAndKeepsOtherMasksAndLocks() async throws {
        let p=try example("subject-light")
        var base=EditRecipe();base.masks=[LocalMask(id:"own",kind:.brush)]
        let first=try await PluginRuntime.execute(p,on:base,context:.editor).recipe
        let second=try await PluginRuntime.execute(p,on:first,context:.agent).recipe
        XCTAssertEqual(first,second);XCTAssertEqual(first.masks.count,2);XCTAssertEqual(first.masks[0],base.masks[0])
        base.lockedParameters=["masks"]
        let locked=try await PluginRuntime.execute(p,on:base,context:.batch).recipe
        XCTAssertEqual(locked.masks,base.masks)
        var full=EditRecipe();full.masks=(0..<16).map{LocalMask(id:"m\($0)",kind:.brush)}
        do {_=try await PluginRuntime.execute(p,on:full,context:.editor);XCTFail("Must reject a seventeenth mask") } catch {}
    }
    func testLUTUsesImmutableContentAddressAndRespectsLocks() async throws {
        let p=try example("warm-light"),folder=try temporary()
        var base=EditRecipe();base.color.intensity=0.44;base.geometry.cropAspect=1
        let result=try await PluginRuntime.execute(p,on:base,context:.editor,lutDirectory:folder).recipe
        XCTAssertEqual(result.color.lut,"user_"+p.assets[0].sha256);XCTAssertEqual(result.color.intensity,0.8)
        XCTAssertEqual(try UserFilterLibrary.load(id:result.color.lut!,at:folder).dimension,17)
        base.lockedParameters=["color"]
        let locked=try await PluginRuntime.execute(p,on:base,context:.agent,lutDirectory:folder).recipe
        XCTAssertEqual(locked.color,base.color);XCTAssertEqual(locked.geometry,base.geometry)
    }
    func testAIInstructionRunsHostPlannerAndBoundsItsOutput() async throws {
        let p=try example("portrait-assistant")
        var base=EditRecipe();base.geometry.cropAspect=1.3;base.global.exposure=0.2;base.lockedParameters=["global.exposure"]
        base.masks=[LocalMask(id:"own",kind:.brush)]
        let result=try await PluginRuntime.execute(p,on:base,context:.agent,request:"不要美白",planner:{ instruction,current in
            XCTAssertTrue(instruction.contains("不要美白"));XCTAssertFalse(instruction.contains("${request}"))
            var proposed=current;proposed.geometry.cropAspect=2;proposed.masks=[];proposed.raw.exposure=1;proposed.global.exposure=2;proposed.global.contrast=1.12
            return proposed
        })
        XCTAssertEqual(result.recipe.geometry,base.geometry);XCTAssertEqual(result.recipe.raw,base.raw)
        XCTAssertEqual(result.recipe.masks,base.masks);XCTAssertEqual(result.recipe.global.exposure,0.2);XCTAssertEqual(result.recipe.global.contrast,1.12)
        do {_=try await PluginRuntime.execute(p,on:base,context:.editor);XCTFail("Requires a planner") } catch {}
        var unsupported=p;unsupported.manifest.supports=[.editor]
        do {_=try await PluginRuntime.execute(unsupported,on:base,context:.agent);XCTFail("Must enforce supported contexts") } catch {}
    }
    func testInstallVersionConflictRollbackUninstallAndTamper() async throws {
        let folder=try temporary(),store=try PluginStore(root:folder)
        var p=try example("clear-portrait");let first=try p.encoded();_=try await store.install(first)
        p.payload.recipe?.global.contrast=1.2
        do {_=try await store.install(p.encoded());XCTFail("Published versions must be immutable") } catch {}
        p.manifest.version="1.1.0";_=try await store.install(p.encoded())
        try await store.activate(id:p.manifest.id,version:"1.0.0")
        let restored=try await store.package(id:p.manifest.id);XCTAssertEqual(restored.manifest.version,"1.0.0")
        let disk=folder.appendingPathComponent(p.manifest.id+"/1.0.0.lumaplugin");try Data("modified".utf8).write(to:disk)
        do {_=try await store.package(id:p.manifest.id);XCTFail("Must detect tampering") } catch {}
        try await store.uninstall(id:p.manifest.id);let all=await store.all();XCTAssertTrue(all.isEmpty)
    }
    func testCommercialInstallRequiresAuthorization() async throws {
        var p=try example("clear-portrait");p.manifest.license=PluginLicense(type:"commercial",terms:"个人席位授权，不可转售。",priceCents:1900,currency:"CNY")
        let store=try PluginStore(root:temporary())
        do {_=try await store.install(p.encoded());XCTFail("Unpaid commercial package cannot install") } catch {}
        _=try await store.install(p.encoded(),commercialAuthorized:true)
        let installed=try await store.package(id:p.manifest.id);XCTAssertEqual(installed.manifest.license.priceCents,1900)
    }
}
