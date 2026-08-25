import Foundation

@MainActor
final class AgentStore {
    private(set) var agents: [Agent] = []
    var onChange: (() -> Void)?

    private let seeds: SeedStore
    private var lingerTimer: Timer?
    private var bloomQueue: [AgentID] = []

    init(seeds: SeedStore = SeedStore()) {
        self.seeds = seeds
        lingerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sweepLingered()
            }
        }
    }

    deinit {
        lingerTimer?.invalidate()
    }

    func agent(id: AgentID) -> Agent? {
        agents.first { $0.id == id }
    }

    func apply(_ event: HookEvent) {
        if event.parseError { return }
        switch event.kind {
        case .ignore:
            return
        case .sessionStart:
            applySessionStart(event)
        case .userPromptSubmit:
            mutate(event.sessionID) { agent in
                agent.turnOpen = true
                agent.status = .thinking
                agent.sessionEndedAt = nil
                agent.lastEventAt = Date()
            }
        case .preToolUse:
            mutate(event.sessionID) { agent in
                agent.currentTool = ToolEvent(
                    id: UUID().uuidString,
                    name: event.toolName ?? "Tool",
                    fileHint: event.toolInputSummary,
                    phase: .started,
                    at: Date()
                )
                agent.status = .working
                agent.lastEventAt = Date()
            }
        case .postToolUse:
            applyPostTool(event, phase: .succeeded)
        case .postToolUseFailure:
            applyPostTool(event, phase: .failed)
        case .permissionRequest:
            mutate(event.sessionID) { agent in
                agent.status = .waitingOnUser
                agent.lastEventAt = Date()
            }
        case .notification:
            applyNotification(event)
        case .stop:
            applyStop(event, error: event.stopStatus == "error")
        case .stopFailure:
            applyStop(event, error: true)
        case .subagentStart:
            mutate(event.sessionID) { agent in
                let id = event.agentID ?? UUID().uuidString
                if !agent.subagents.contains(where: { $0.id == id }) {
                    agent.subagents.append(SubagentRecord(id: id, type: event.agentType, startedAt: Date()))
                }
                if agent.currentTool?.name == "Task" {
                    agent.currentTool = nil
                }
                agent.lastEventAt = Date()
            }
        case .subagentStop:
            mutate(event.sessionID) { agent in
                if let id = event.agentID {
                    agent.subagents.removeAll { $0.id == id }
                }
                if let preview = event.lastAssistantMessage {
                    agent.lastAssistantPreview = preview
                }
                agent.lastEventAt = Date()
            }
        case .sessionEnd:
            mutate(event.sessionID) { agent in
                agent.sessionEndedAt = Date()
                agent.turnOpen = false
                if isErrorEnd(event.sessionEndReason) || agent.status == .error {
                    agent.status = .error
                } else if agent.status != .error {
                    agent.status = .finished
                }
                agent.lastEventAt = Date()
            }
        case .afterAgentThought:
            mutate(event.sessionID) { agent in
                if agent.turnOpen, agent.currentTool == nil {
                    agent.status = .thinking
                }
                agent.lastEventAt = Date()
            }
        case .afterAgentResponse:
            mutate(event.sessionID) { agent in
                if let preview = event.lastAssistantMessage {
                    agent.lastAssistantPreview = preview
                }
                agent.lastEventAt = Date()
            }
        }
        notify()
    }

    func injectDebugAgents(count: Int) {
        var next = (0..<count).map { index -> Agent in
            var agent = Agent.debugDummy(index: index)
            agent.status = debugStatus(index: index, count: count)
            return agent
        }
        LatticeSlots.assign(&next)
        let live = agents.filter { !$0.isInjected }
        agents = next + live
        LatticeSlots.assign(&agents)
        notify()
    }

    func clearInjected() {
        agents.removeAll { $0.isInjected }
        notify()
    }

    func setStatus(_ status: AgentStatus, for id: AgentID) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        applyTransition(from: agents[index].status, to: status, on: &agents[index], forceBloom: false)
        agents[index].lastEventAt = Date()
        if status == .finished || status == .error {
            agents[index].turnOpen = false
        }
        notify()
    }

    func fireBloom(for id: AgentID) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        requestBloom(index: index, force: true)
        notify()
    }

    func advanceAnimationTime(_ dt: Float) {
        for index in agents.indices where MotionEngine.shouldAdvanceTime(agents[index].status) {
            agents[index].animationTime += dt
        }
        releaseQueuedBlooms()
    }

    func cycleSeed(for id: AgentID) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        let next = Identity.nextSeed(agents[index].seed)
        agents[index].seed = next
        if !agents[index].isInjected {
            seeds.assign(next, to: agents[index].id)
        }
        notify()
    }

    func cycleTool(for id: AgentID) {
        let names = ["Read", "Edit", "Bash", "Grep", "Task"]
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        let current = agents[index].currentTool?.name ?? names.last!
        let nextName = names[((names.firstIndex(of: current) ?? -1) + 1) % names.count]
        agents[index].currentTool = ToolEvent(
            id: UUID().uuidString,
            name: nextName,
            fileHint: "Example.swift",
            phase: .started,
            at: Date()
        )
        agents[index].status = .working
        agents[index].lastEventAt = Date()
        notify()
    }

    private func applySessionStart(_ event: HookEvent) {
        let source = event.sessionStartSource ?? ""
        let revive = source == "resume" || source == "compact"
        if let index = agents.firstIndex(where: { $0.id == event.sessionID }) {
            if revive {
                agents[index].currentTool = nil
                agents[index].status = .idle
                agents[index].sessionEndedAt = nil
                agents[index].lastEventAt = Date()
            } else {
                agents[index].recentTools = []
                agents[index].currentTool = nil
                agents[index].lastAssistantPreview = nil
                agents[index].subagents = []
                agents[index].turnOpen = false
                agents[index].status = .idle
                agents[index].sessionEndedAt = nil
                agents[index].lastEventAt = Date()
            }
            if let cwd = event.cwd { agents[index].cwd = URL(fileURLWithPath: cwd) }
            if let hint = event.sourceHint { agents[index].source = hint }
            return
        }
        let agent = Agent.make(
            id: event.sessionID,
            source: event.sourceHint ?? .cli,
            cwd: event.cwd.map { URL(fileURLWithPath: $0) },
            conductorWorkspaceID: conductorID(from: event.cwd),
            seed: seeds.seed(for: event.sessionID)
        )
        agents.append(agent)
        LatticeSlots.assign(&agents)
    }

    private func applyPostTool(_ event: HookEvent, phase: ToolEvent.Phase) {
        mutate(event.sessionID) { agent in
            if var tool = agent.currentTool {
                tool.phase = phase
                agent.recentTools.insert(tool, at: 0)
                if agent.recentTools.count > 3 { agent.recentTools = Array(agent.recentTools.prefix(3)) }
            }
            agent.currentTool = nil
            let next: AgentStatus = agent.turnOpen ? .thinking : .finished
            applyTransition(from: agent.status, to: next, on: &agent, forceBloom: false)
            agent.lastEventAt = Date()
        }
    }

    private func applyNotification(_ event: HookEvent) {
        let type = event.notificationType ?? ""
        if type == "agent_completed" {
            applyStop(event, error: false)
            return
        }
        let needsYou = ["permission_prompt", "idle_prompt", "agent_needs_input"].contains(type)
        mutate(event.sessionID) { agent in
            if needsYou {
                agent.status = .waitingOnUser
            }
            agent.lastEventAt = Date()
        }
    }

    private func applyStop(_ event: HookEvent, error: Bool) {
        mutate(event.sessionID) { agent in
            agent.turnOpen = false
            if let preview = event.lastAssistantMessage {
                agent.lastAssistantPreview = preview
            }
            if error {
                applyTransition(from: agent.status, to: .error, on: &agent, forceBloom: false)
            } else if agent.status != .error {
                applyTransition(from: agent.status, to: .finished, on: &agent, forceBloom: false)
            }
            agent.lastEventAt = Date()
        }
    }

    private func mutate(_ sessionID: AgentID, _ body: (inout Agent) -> Void) {
        if !agents.contains(where: { $0.id == sessionID }) {
            applySessionStart(HookEvent(
                hookEventName: "SessionStart",
                sessionID: sessionID,
                cwd: nil,
                transcriptPath: nil,
                toolName: nil,
                toolInputSummary: nil,
                lastAssistantMessage: nil,
                notificationType: nil,
                agentID: nil,
                agentType: nil,
                sessionEndReason: nil,
                sessionStartSource: "startup",
                composerMode: nil,
                isBackgroundAgent: nil,
                stopStatus: nil,
                sourceHint: nil,
                parseError: false
            ))
        }
        guard let index = agents.firstIndex(where: { $0.id == sessionID }) else { return }
        body(&agents[index])
    }

    private func sweepLingered() {
        let cutoff = Date().addingTimeInterval(-IngestConstants.linger)
        let before = agents.count
        agents.removeAll { agent in
            guard let ended = agent.sessionEndedAt else { return false }
            return ended < cutoff
        }
        if agents.count != before { notify() }
    }

    private func notify() {
        onChange?()
    }

    private func debugStatus(index: Int, count: Int) -> AgentStatus {
        if count == 3 {
            return [.working, .thinking, .finished][index]
        }
        let all: [AgentStatus] = [.working, .thinking, .waitingOnUser, .finished, .error, .idle]
        return all[index % all.count]
    }

    private func applyTransition(from previous: AgentStatus, to next: AgentStatus, on agent: inout Agent, forceBloom: Bool) {
        agent.status = next
        if next == .error {
            agent.bloomStartedAt = nil
            agent.errorHueStartedAt = Date()
            agent.errorHueReleasedAt = nil
            bloomQueue.removeAll { $0 == agent.id }
            return
        }
        if previous == .error {
            agent.errorHueReleasedAt = Date()
        }
        if next == .finished, previous != .error || forceBloom {
            agent.bloomStartedAt = Date()
        }
    }

    private func requestBloom(index: Int, force: Bool) {
        if agents[index].status == .error, !force { return }
        let now = Date()
        let active = agents.filter { MotionEngine.bloomEnvelope(startedAt: $0.bloomStartedAt, now: now) > 0 }.count
        if active >= MotionEngine.maxConcurrentBlooms {
            if !bloomQueue.contains(agents[index].id) {
                bloomQueue.append(agents[index].id)
            }
            return
        }
        agents[index].bloomStartedAt = now
    }

    private func releaseQueuedBlooms() {
        let now = Date()
        let active = agents.filter { MotionEngine.bloomEnvelope(startedAt: $0.bloomStartedAt, now: now) > 0 }.count
        guard active < MotionEngine.maxConcurrentBlooms, let next = bloomQueue.first else { return }
        bloomQueue.removeFirst()
        if let index = agents.firstIndex(where: { $0.id == next }) {
            agents[index].bloomStartedAt = now
        }
    }

    private func conductorID(from cwd: String?) -> String? {
        guard let cwd, cwd.contains("/conductor/workspaces/") else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

private func isErrorEnd(_ reason: String?) -> Bool {
    switch reason {
    case "error", "process_crash", "crash", "prompt_input_exit":
        return true
    default:
        return false
    }
}
