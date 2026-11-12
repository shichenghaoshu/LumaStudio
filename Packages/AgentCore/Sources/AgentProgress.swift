import Foundation
import PhotoDomain
import VisionEngine

/// Observable execution facts. These events contain no model reasoning text.
public enum AgentStage: String,Codable,CaseIterable,Sendable {
    case analysis,planning,rendering,evaluation,saving
}
public struct AgentEvent: Codable,Identifiable,Sendable {
    public enum Kind: String,Codable,Sendable { case started,finished }
    public let id: UUID
    public let stage: AgentStage
    public let kind: Kind
    public let roundIndex: Int?
    public let timestamp: Date
    public let detail: String
    public init(stage: AgentStage,kind: Kind,roundIndex: Int?=nil,detail: String) {
        id=UUID();self.stage=stage;self.kind=kind;self.roundIndex=roundIndex
        timestamp=Date();self.detail=detail
    }
}
public enum AgentUpdate: Sendable {
    case event(AgentEvent)
    case analysis(ImageAnalysis)
    case plan(AgentPlan)
    /// Emitted only after the preview and its round record have been saved.
    case round(AgentRound,directory: URL)
}
