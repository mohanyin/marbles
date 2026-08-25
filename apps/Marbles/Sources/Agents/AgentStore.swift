import Foundation

@MainActor
final class AgentStore {
    private(set) var agents: [Agent] = []
    var onChange: (() -> Void)?

    private let seeds: SeedStore
    private var lingerTimer: Timer?
    private var bloomQueue: [AgentID] = []
    private var pendingStarts: [AgentID: HookEvent] = [:]
    private var previewRetry: [AgentID: Int] = [:]

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
        if event.kind == .ignore { return }
        switch event.kind {
        case .ignore:
            return
        case .sessionStart:
            applySessionStart(event)
        case .userPromptSubmit:
            mutate(event) { agent in
                agent.turnOpen = true
                agent.status = .thinking
                agent.sessionEndedAt = nil
                agent.lastEventAt = Date()
            }
            refreshFromTranscript(event.sessionID)
        case .preToolUse:
            mutate(event) { agent in
                presentTool(
                    ToolEvent(
                        id: UUID().uuidString,
                        name: event.toolName ?? "Tool",
                        fileHint: event.toolInputSummary,
                        phase: .started,
                        at: Date()
                    ),
                    on: &agent
                )
                agent.lastEventAt = Date()
            }
        case .postToolUse:
            applyPostTool(event, phase: .succeeded)
        case .postToolUseFailure:
            applyPostTool(event, phase: .failed)
        case .permissionRequest:
            mutate(event) { agent in
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
            mutate(event) { agent in
                let id = event.agentID ?? UUID().uuidString
                if !agent.subagents.contains(where: { $0.id == id }) {
                    agent.subagents.append(SubagentRecord(id: id, type: event.agentType, startedAt: Date()))
                }
                if agent.currentTool?.name == "Task" {
                    if !agent.pendingTools.isEmpty {
                        let next = agent.pendingTools.removeFirst()
                        show(next, on: &agent, now: Date())
                    } else {
                        agent.currentTool = nil
                        agent.toolHoldUntil = nil
                    }
                }
                agent.lastEventAt = Date()
            }
        case .subagentStop:
            mutate(event) { agent in
                if let id = event.agentID {
                    agent.subagents.removeAll { $0.id == id }
                }
                agent.lastEventAt = Date()
            }
        case .sessionEnd:
            pendingStarts.removeValue(forKey: event.sessionID)
            mutate(event, createIfMissing: false) { agent in
                clearTools(on: &agent, retireCurrent: true)
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
            mutate(event) { agent in
                if agent.turnOpen, agent.currentTool == nil, agent.pendingTools.isEmpty {
                    agent.status = .thinking
                }
                agent.lastEventAt = Date()
            }
        case .afterAgentResponse:
            mutate(event) { agent in
                agent.lastEventAt = Date()
            }
            refreshFromTranscript(event.sessionID, fallback: event.lastAssistantMessage)
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

    func ensureDemo() {
        guard !agents.contains(where: { $0.isDemo }) else { return }
        agents.insert(DemoMarble.make(), at: 0)
        LatticeSlots.assign(&agents)
        notify()
    }

    func removeDemo() {
        let before = agents.count
        agents.removeAll { $0.isDemo }
        if agents.count != before {
            LatticeSlots.assign(&agents)
            notify()
        }
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

    func advanceAnimationTime(_ dt: Float, now: Date = Date()) {
        for index in agents.indices where MotionEngine.shouldAdvanceTime(agents[index].status) {
            agents[index].animationTime += dt
        }
        releaseQueuedBlooms()
        if releaseToolHolds(now: now) {
            notify()
        }
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
        agents[index].pendingTools = []
        agents[index].toolHoldUntil = Date().addingTimeInterval(IngestConstants.toolDwell)
        agents[index].status = .working
        agents[index].lastEventAt = Date()
        notify()
    }

    private func applySessionStart(_ event: HookEvent) {
        let source = event.sessionStartSource ?? ""
        let revive = source == "resume" || source == "compact"
        if let index = agents.firstIndex(where: { $0.id == event.sessionID }) {
            removeDemo()
            if revive {
                clearTools(on: &agents[index], retireCurrent: false)
                agents[index].status = .idle
                agents[index].sessionEndedAt = nil
                agents[index].lastEventAt = Date()
            } else {
                agents[index].recentTools = []
                clearTools(on: &agents[index], retireCurrent: false)
                agents[index].lastAssistantPreview = nil
                agents[index].subagents = []
                agents[index].turnOpen = false
                agents[index].status = .idle
                agents[index].sessionEndedAt = nil
                agents[index].lastEventAt = Date()
            }
            if let cwd = event.cwd { agents[index].cwd = URL(fileURLWithPath: cwd) }
            if let hint = event.sourceHint { agents[index].source = hint }
            if let path = event.transcriptPath { agents[index].transcriptPath = path }
            refreshFromTranscript(event.sessionID)
            pendingStarts.removeValue(forKey: event.sessionID)
            return
        }
        let snapshot = peek(event)
        if snapshot.hasConversation || revive {
            insertAgent(from: event, title: snapshot.title)
            pendingStarts.removeValue(forKey: event.sessionID)
        } else {
            pendingStarts[event.sessionID] = event
        }
    }

    private func applyPostTool(_ event: HookEvent, phase: ToolEvent.Phase) {
        mutate(event) { agent in
            finishFirstStarted(phase: phase, on: &agent)
            _ = advanceHeldTool(now: Date(), on: &agent)
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
        mutate(event) { agent in
            if needsYou {
                agent.status = .waitingOnUser
            }
            agent.lastEventAt = Date()
        }
    }

    private func applyStop(_ event: HookEvent, error: Bool) {
        mutate(event) { agent in
            clearTools(on: &agent, retireCurrent: true)
            agent.turnOpen = false
            if error {
                applyTransition(from: agent.status, to: .error, on: &agent, forceBloom: false)
            } else if agent.status != .error {
                applyTransition(from: agent.status, to: .finished, on: &agent, forceBloom: false)
            }
            agent.lastEventAt = Date()
        }
        refreshFromTranscript(event.sessionID, fallback: event.lastAssistantMessage)
        schedulePreviewRetry(event.sessionID)
    }

    private func mutate(_ event: HookEvent, createIfMissing: Bool = true, _ body: (inout Agent) -> Void) {
        if !agents.contains(where: { $0.id == event.sessionID }) {
            guard createIfMissing else { return }
            let start = pendingStarts.removeValue(forKey: event.sessionID) ?? event
            insertAgent(from: start, title: peek(start).title)
        }
        guard let index = agents.firstIndex(where: { $0.id == event.sessionID }) else { return }
        if let path = event.transcriptPath { agents[index].transcriptPath = path }
        body(&agents[index])
    }

    private func insertAgent(from event: HookEvent, title: String?) {
        removeDemo()
        var agent = Agent.make(
            id: event.sessionID,
            source: event.sourceHint ?? .cli,
            cwd: event.cwd.map { URL(fileURLWithPath: $0) },
            conductorWorkspaceID: conductorID(from: event.cwd),
            title: title,
            transcriptPath: event.transcriptPath,
            seed: seeds.seed(for: event.sessionID)
        )
        if agent.transcriptPath == nil {
            agent.transcriptPath = TranscriptPeek.resolvedPath(
                sessionID: event.sessionID,
                cwd: event.cwd,
                explicit: event.transcriptPath
            )
        }
        agents.append(agent)
        LatticeSlots.assign(&agents)
    }

    private func peek(_ event: HookEvent) -> TranscriptSnapshot {
        let path = TranscriptPeek.resolvedPath(
            sessionID: event.sessionID,
            cwd: event.cwd,
            explicit: event.transcriptPath
        )
        return TranscriptPeek.inspect(path: path)
    }

    private func refreshFromTranscript(_ id: AgentID, fallback: String? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        let path = TranscriptPeek.resolvedPath(
            sessionID: agents[index].id,
            cwd: agents[index].cwd?.path,
            explicit: agents[index].transcriptPath
        )
        let snapshot = TranscriptPeek.inspect(path: path)
        if let title = snapshot.title {
            agents[index].title = title
        }
        if let text = TranscriptPeek.latestAssistantText(path: path) {
            agents[index].lastAssistantPreview = text
        } else if let fallback, !fallback.isEmpty, agents[index].source == .cursor {
            agents[index].lastAssistantPreview = String(fallback.prefix(IngestConstants.previewLimit))
        }
    }

    private func schedulePreviewRetry(_ id: AgentID) {
        let token = (previewRetry[id] ?? 0) + 1
        previewRetry[id] = token
        Task { @MainActor in
            for delay in [400_000_000, 1_200_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delay)
                guard previewRetry[id] == token else { return }
                let before = agent(id: id)?.lastAssistantPreview
                refreshFromTranscript(id)
                if agent(id: id)?.lastAssistantPreview != before {
                    notify()
                }
            }
        }
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

    private func presentTool(_ tool: ToolEvent, on agent: inout Agent, now: Date = Date()) {
        if agent.currentTool == nil {
            show(tool, on: &agent, now: now)
            return
        }
        agent.pendingTools.append(tool)
        if agent.pendingTools.count > IngestConstants.maxQueuedTools {
            agent.pendingTools = Array(agent.pendingTools.suffix(IngestConstants.maxQueuedTools))
        }
        agent.status = .working
    }

    private func show(_ tool: ToolEvent, on agent: inout Agent, now: Date) {
        agent.currentTool = tool
        agent.toolHoldUntil = now.addingTimeInterval(IngestConstants.toolDwell)
        agent.status = .working
    }

    private func finishFirstStarted(phase: ToolEvent.Phase, on agent: inout Agent) {
        if var tool = agent.currentTool, tool.phase == .started {
            tool.phase = phase
            agent.currentTool = tool
            return
        }
        if let index = agent.pendingTools.firstIndex(where: { $0.phase == .started }) {
            agent.pendingTools[index].phase = phase
        }
    }

    private func retire(_ tool: ToolEvent, on agent: inout Agent) {
        agent.recentTools.insert(tool, at: 0)
        if agent.recentTools.count > 3 {
            agent.recentTools = Array(agent.recentTools.prefix(3))
        }
    }

    private func clearTools(on agent: inout Agent, retireCurrent: Bool) {
        if retireCurrent, let tool = agent.currentTool {
            retire(tool, on: &agent)
        }
        agent.currentTool = nil
        agent.pendingTools = []
        agent.toolHoldUntil = nil
    }

    @discardableResult
    private func releaseToolHolds(now: Date) -> Bool {
        var changed = false
        for index in agents.indices {
            if advanceHeldTool(now: now, on: &agents[index]) {
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    private func advanceHeldTool(now: Date, on agent: inout Agent) -> Bool {
        guard let current = agent.currentTool else { return false }
        guard let until = agent.toolHoldUntil else { return false }
        if now < until { return false }
        if current.phase == .started { return false }

        retire(current, on: &agent)
        if !agent.pendingTools.isEmpty {
            let next = agent.pendingTools.removeFirst()
            show(next, on: &agent, now: now)
            return true
        }
        agent.currentTool = nil
        agent.toolHoldUntil = nil
        if agent.turnOpen,
           agent.status != .waitingOnUser,
           agent.status != .error,
           agent.status != .finished
        {
            applyTransition(from: agent.status, to: .thinking, on: &agent, forceBloom: false)
        }
        return true
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
