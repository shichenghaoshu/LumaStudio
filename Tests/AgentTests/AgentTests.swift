import XCTest
import CoreImage
import PhotoCore

final class AgentTests: XCTestCase {
    func testIntensiveBeautyRespectsExplicitExclusionsAndManualState() throws {
        let cg=try XCTUnwrap(CIContext().createCGImage(CIImage(color:.gray).cropped(to:CGRect(x:0,y:0,width:32,height:32)),from:CGRect(x:0,y:0,width:32,height:32)))
        let analysis=ImageAnalysis(image:cg,faceCount:1,metrics:try PixelMetrics.measure(cg))
        let context=PlanningContext(instruction:"高强度磨皮，瓷白肤色，大眼，但不要瘦脸，不要美白",analysis:analysis,preferences:EditingPreferences())
        let r=try LocalRulePlanner().plan(context)
        XCTAssertTrue(r.beauty.enabled);XCTAssertGreaterThan(r.beauty.intensiveSmoothing,0.5)
        XCTAssertLessThan(r.beauty.texturePreservation,0.5);XCTAssertEqual(r.beauty.faceSlimming,0)
        XCTAssertGreaterThan(r.beauty.eyeEnlargement,0.5);XCTAssertEqual(r.beauty.skinWhitening,0)
        XCTAssertFalse(InstructionParser.parse(context.instruction).preserveTexture)
        var manual=EditRecipe();manual.beauty=BeautyStyle.intensive.settings
        let brightness=PlanningContext(instruction:"提亮一点",analysis:analysis,preferences:EditingPreferences(),currentRecipe:manual)
        let gated=try IntentSafetyGate.enforce(manual,context:brightness)
        XCTAssertEqual(gated.beauty,manual.beauty)
        XCTAssertTrue(InstructionParser.parse("瘦脸，大眼").unavailableRequests.isEmpty)
        let none=ImageAnalysis(image:cg,faceCount:0,metrics:try PixelMetrics.measure(cg))
        XCTAssertFalse(try LocalRulePlanner().plan(PlanningContext(instruction:"高强度美颜",analysis:none,preferences:EditingPreferences())).beauty.enabled)
    }
    func testStrictSchemaRejectsCommandsUnknownFieldsAndOutOfBounds() throws {
        let neutral=try EditRecipe().json()
        XCTAssertNoThrow(try ToolRegistry().decode(neutral))
        var root=try JSONSerialization.jsonObject(with:neutral) as! [String:Any]
        root["shell"]="touch /tmp/should-never-execute"
        XCTAssertThrowsError(try ToolRegistry().decode(JSONSerialization.data(withJSONObject:root)))
        root.removeValue(forKey:"shell");root["global"]=["exposure":true]
        XCTAssertThrowsError(try ToolRegistry().decode(JSONSerialization.data(withJSONObject:root)))
        root["global"]=["exposure":5.01]
        XCTAssertThrowsError(try ToolRegistry().decode(JSONSerialization.data(withJSONObject:root)))
        root["global"]=["exposure":0];root["operations"]=[["tool":"shell.exec"]]
        XCTAssertThrowsError(try ToolRegistry().decode(JSONSerialization.data(withJSONObject:root)))
    }
    func testUnsupportedMaskAndInvalidCurveNeverReachEngine() throws {
        var r=EditRecipe();r.masks=[LocalMask(id:"sky",kind:.sky)]
        XCTAssertThrowsError(try ToolRegistry().validate(r))
        r.masks=[LocalMask(id:"../../file",kind:.face)]
        XCTAssertThrowsError(try r.validateParameters())
        r.masks=[];r.color.curve.master=[CurvePoint(0,0),CurvePoint(0.7,0.8),CurvePoint(0.6,0.6),CurvePoint(1,1)]
        XCTAssertThrowsError(try r.validateParameters())
    }
    func testRecipeRoundTripAndManualControlsRemainEditable() throws {
        var edit=EditRecipe();edit.global.exposure=0.4;edit.global.shadows=0.3;edit.beauty.enabled=true
        var legacy=try edit.legacyRecipe();legacy.color.exposure = -0.2;legacy.beauty.strength=0.2
        let restored=try JSONDecoder().decode(Recipe.self,from:legacy.json())
        XCTAssertEqual(restored.edit?.global.exposure,-0.2);XCTAssertEqual(restored.edit?.global.shadows,0.3)
        XCTAssertEqual(restored.edit?.beauty.strength,0.2)
    }
    func testInstructionNegationAndLocalIntent() {
        let a=InstructionParser.parse("不要提亮，不要美颜，只把背景压暗")
        XCTAssertEqual(a.brightnessDirection,-1);XCTAssertTrue(a.beautyForbidden);XCTAssertFalse(a.beautyRequested)
        XCTAssertEqual(a.requestedLocalRegion,.background)
        XCTAssertEqual(InstructionParser.parse("不要压暗，亮一点").brightnessDirection,1)
        for text in ["自然提亮，不做美颜", "校正白平衡，不做磨皮", "不要做美颜", "不要做磨皮"] {
            let intent=InstructionParser.parse(text)
            XCTAssertTrue(intent.beautyForbidden,text);XCTAssertFalse(intent.beautyRequested,text)
        }
    }
    func testGrammarConstrainsActualFieldNames() throws {
        let grammar=try EditRecipeGrammar.make()
        XCTAssertTrue(grammar.contains("global-required"));XCTAssertTrue(grammar.contains("texturePreservation"))
        XCTAssertFalse(grammar.contains("shell.exec"));XCTAssertFalse(grammar.contains("Lut"))
    }
    func testRealPortraitRuleLoopAndOriginalPreservation() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else { throw XCTSkip("Set LUMA_PORTRAIT_FIXTURE for real-photo acceptance") }
        let url=URL(fileURLWithPath:path),before=try ModelManager.sha256(url),dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let asset=PhotoAsset(name:url.lastPathComponent,originalURL:url,thumbnailURL:url)
        let session=AgentSession(engine:NativeImageEngine(processor:try PhotoProcessor()),planner:RulesAgentPlanner(),history:try LocalHistoryStore(root:dir))
        let result=try await session.run(asset:asset,instruction:"自然提亮，暖一点，不要美颜")
        XCTAssertFalse(result.run.selectedRecipe.beauty.enabled)
        XCTAssertGreaterThan(result.run.rounds.last!.evaluation.after.meanLuminance,result.run.rounds.last!.evaluation.before.meanLuminance)
        XCTAssertLessThanOrEqual(result.run.rounds.count,3)
        for r in result.run.rounds { XCTAssertTrue(FileManager.default.fileExists(atPath:result.directory.appendingPathComponent(r.imageFilename).path));XCTAssertEqual(r.executedOperations,r.recipe.resolvedOperations) }
        XCTAssertEqual(before,try ModelManager.sha256(url))
    }
    func testEvaluatorStopsAtTwoCorrectionsAndCanBeDisabled() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let source=dir.appendingPathComponent("unit-test-flat.jpg"),context=CIContext()
        try context.writeJPEGRepresentation(of:CIImage(color:CIColor(red:0.3,green:0.3,blue:0.3)).cropped(to:CGRect(x:0,y:0,width:48,height:48)),to:source,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        struct BadPlanner: AgentPlanner {
            func plan(_ context: PlanningContext) async throws -> AgentPlan { var r=EditRecipe();r.global.exposure=1;return AgentPlan(recipe:r,source:"unit-test intentionally wrong direction",planningMilliseconds:0) }
        }
        let asset=PhotoAsset(name:"unit-test-flat",originalURL:source,thumbnailURL:source)
        let session=AgentSession(engine:NativeImageEngine(processor:try PhotoProcessor()),planner:BadPlanner(),history:try LocalHistoryStore(root:dir.appendingPathComponent("history")))
        let recorder=ProcessUpdateRecorder()
        let corrected=try await session.run(asset:asset,instruction:"压暗一点",updates:{ await recorder.record($0) })
        XCTAssertEqual(corrected.run.rounds.count,3)
        XCTAssertLessThan(corrected.run.rounds[2].recipe.global.exposure,corrected.run.rounds[0].recipe.global.exposure)
        let observed=await recorder.snapshot()
        XCTAssertEqual(observed.events.map(\.id),corrected.run.events?.map(\.id))
        XCTAssertEqual(observed.roundIndices,[0,1,2])
        XCTAssertTrue(observed.savedBeforeNotification.allSatisfy{$0})
        XCTAssertEqual(observed.events.first?.stage,.analysis)
        XCTAssertEqual(observed.events.last?.stage,.saving)
        XCTAssertEqual(observed.events.last?.kind,.finished)
        for event in observed.events where event.kind == .finished {
            let start=try XCTUnwrap(observed.events.first{$0.stage==event.stage && $0.roundIndex==event.roundIndex && $0.kind == .started})
            XCTAssertLessThanOrEqual(start.timestamp,event.timestamp)
        }
        let stored=corrected.directory.appendingPathComponent("run.json")
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let restored=try decoder.decode(AgentRun.self,from:Data(contentsOf:stored))
        XCTAssertTrue(restored.completed);XCTAssertEqual(restored.events?.count,18)
        // A pre-process-page run has no events field and must still load.
        var old=try JSONSerialization.jsonObject(with:Data(contentsOf:stored)) as! [String:Any]
        old.removeValue(forKey:"events")
        XCTAssertNil(try decoder.decode(AgentRun.self,from:JSONSerialization.data(withJSONObject:old)).events)
        let disabled=try await session.run(asset:asset,instruction:"压暗一点",automaticCorrection:false)
        XCTAssertEqual(disabled.run.rounds.count,1)
    }
    func testCancelledAnalysisNeverReportsCompletedStepsOrCreatesHistory() async throws {
        struct InterruptedEngine: ImageEngine {
            func analyze(_ asset: PhotoAsset) async throws -> ImageAnalysis { throw CancellationError() }
            func preview(_ asset: PhotoAsset,recipe: EditRecipe) async throws -> RenderResult { throw CancellationError() }
            func render(_ asset: PhotoAsset,recipe: EditRecipe) async throws -> RenderResult { throw CancellationError() }
        }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("unused.jpg"),asset=PhotoAsset(name:"interrupted",originalURL:url,thumbnailURL:url)
        let recorder=ProcessUpdateRecorder()
        let session=AgentSession(engine:InterruptedEngine(),planner:RulesAgentPlanner(),history:try LocalHistoryStore(root:directory))
        do { _=try await session.run(asset:asset,instruction:"提亮一点",updates:{ await recorder.record($0) });XCTFail("Cancellation should propagate") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let observed=await recorder.snapshot()
        XCTAssertEqual(observed.events.count,1)
        XCTAssertEqual(observed.events.first?.stage,.analysis);XCTAssertEqual(observed.events.first?.kind,.started)
        XCTAssertTrue(observed.roundIndices.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
    }
    func testAutomaticExposureAndWhiteBalanceAreNotDiscardedByNoBeautyConstraint() throws {
        let ci=CIImage(color:CIColor(red:0.12,green:0.13,blue:0.14)).cropped(to:CGRect(x:0,y:0,width:48,height:32)),image=CIContext().createCGImage(ci,from:ci.extent)!
        let analysis=ImageAnalysis(image:image,faceCount:0,metrics:try PixelMetrics.measure(image))
        let context=PlanningContext(instruction:"逐张自动校正曝光与白平衡，不要美颜",analysis:analysis,preferences:EditingPreferences(),currentRecipe:EditRecipe())
        var proposed=EditRecipe();proposed.global.exposure=0.72;proposed.global.temperature=6100
        let gated=try IntentSafetyGate.enforce(proposed,context:context)
        XCTAssertEqual(gated.global.exposure,0.72);XCTAssertEqual(gated.global.temperature,6100)
        XCTAssertGreaterThan(try LocalRulePlanner().plan(context).global.exposure,0.5)
    }
    func testSessionHonorsLocksThroughEvaluationAndNoBeautyOverridesEnabledLock() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("gray.jpg"),ci=CIImage(color:CIColor(red:0.35,green:0.35,blue:0.35)).cropped(to:CGRect(x:0,y:0,width:48,height:32))
        try CIContext().writeJPEGRepresentation(of:ci,to:source,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        struct AdversarialPlanner: AgentPlanner {
            func plan(_ context: PlanningContext) async throws -> AgentPlan {var recipe=EditRecipe();recipe.global.exposure=4;recipe.beauty.enabled=true;return AgentPlan(recipe:recipe,source:"unit-test adversarial",planningMilliseconds:0)}
        }
        var current=EditRecipe();current.global.exposure = -0.4;current.beauty.enabled=true;current.lockedParameters=["global.exposure","beauty.enabled"]
        let session=AgentSession(engine:NativeImageEngine(processor:try PhotoProcessor()),planner:AdversarialPlanner(),history:try LocalHistoryStore(root:root.appendingPathComponent("history")))
        let output=try await session.run(asset:PhotoAsset(name:"gray",originalURL:source,thumbnailURL:source),instruction:"提亮，但不要美颜",currentRecipe:current)
        XCTAssertTrue(output.run.rounds.allSatisfy{$0.recipe.global.exposure == -0.4 && !$0.recipe.beauty.enabled})
    }
    func testNativeQwenProducesExecutableRecipeWhenFixtureInstalled() async throws {
        guard let package=ProcessInfo.processInfo.environment["LUMA_AGENT_MODEL_PACKAGE"],let photo=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else { throw XCTSkip("Native model integration fixture is optional") }
        let root=URL(fileURLWithPath:package),manifest=try JSONDecoder().decode(ModelManifest.self,from:Data(contentsOf:root.appendingPathComponent("manifest.json")))
        let processor=try PhotoProcessor(),url=URL(fileURLWithPath:photo),asset=PhotoAsset(name:"portrait",originalURL:url,thumbnailURL:url)
        let analysis=try await NativeImageEngine(processor:processor).analyze(asset)
        let planner=NativeAgentPlanner(model:InstalledModel(manifest:manifest,url:root.appendingPathComponent(manifest.filename),active:true))
        let plan=try await planner.plan(PlanningContext(instruction:"提亮一点，暖一点，不要美颜",analysis:analysis,preferences:EditingPreferences()))
        XCTAssertNil(plan.fallbackReason);XCTAssertTrue(plan.source.hasPrefix(manifest.displayName));XCTAssertFalse(plan.recipe.beauty.enabled)
        XCTAssertEqual(plan.recipe.global.contrast,1);XCTAssertEqual(plan.recipe.global.highlights,0)
        try ToolRegistry().validate(plan.recipe)
    }
}

private actor ProcessUpdateRecorder {
    struct Snapshot {
        var events=[AgentEvent]()
        var roundIndices=[Int]()
        var savedBeforeNotification=[Bool]()
    }
    private var value=Snapshot()
    func record(_ update: AgentUpdate) {
        switch update {
        case .event(let event):value.events.append(event)
        case .round(let round,let directory):
            value.roundIndices.append(round.index)
            let image=directory.appendingPathComponent(round.imageFilename)
            let data=try? Data(contentsOf:directory.appendingPathComponent("run.json"))
            let object=data.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
            let rounds=object?["rounds"] as? [[String:Any]]
            value.savedBeforeNotification.append(FileManager.default.fileExists(atPath:image.path) && rounds?.contains{$0["index"] as? Int==round.index} == true)
        default:break
        }
    }
    func snapshot()->Snapshot { value }
}
