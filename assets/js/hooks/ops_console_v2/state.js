/**
 * State initialization for Ops Console V2 Hook
 *
 * Separates state management from the main hook for better maintainability.
 */

/**
 * Initialize all state on the hook instance from data attributes
 * @param {Object} hook - The LiveView hook instance (this)
 */
export function initializeState(hook) {
  // Get configuration from data attributes
  hook.missionId = hook.el.dataset.missionId
  hook.frameLayout = JSON.parse(hook.el.dataset.layout || "null")
  hook.widgets = JSON.parse(hook.el.dataset.widgets || "[]")
  hook.targets = JSON.parse(hook.el.dataset.targets || "[]")
  hook.dashboards = JSON.parse(hook.el.dataset.dashboards || "[]")
  hook.alarms = JSON.parse(hook.el.dataset.alarms || "[]")
  hook.commands = JSON.parse(hook.el.dataset.commands || "[]")
  hook.commandDefinitions = JSON.parse(hook.el.dataset.commandDefinitions || "[]")
  hook.targetGroups = JSON.parse(hook.el.dataset.targetGroups || "[]")
  hook.currentDashboardId = hook.el.dataset.currentDashboardId
  hook.token = hook.el.dataset.token

  // Track collapsed state for context panel sections
  hook.collapsedSections = {
    alarms: false,
    commands: false
  }

  // Track managers
  hook.panelLayout = null
  hook.gridManager = null
  hook.telemetryStore = null
  hook._windowResizeHandler = null
  hook._initialized = false
  hook._fullscreenWidget = null
  hook.currentMode = "overview"
  hook.selectedTargetId = null

  // Initialize commands mode state
  initializeCommandsState(hook)

  // Initialize timeline mode state
  initializeTimelineState(hook)

  // Live time update interval for timeline mode
  hook._timelineUpdateInterval = null
}

/**
 * Initialize commands mode state
 * @param {Object} hook - The LiveView hook instance
 */
export function initializeCommandsState(hook) {
  // Commands mode state
  hook.cmdSelectedTargets = new Set()
  hook.cmdSelectedCommand = null
  hook.cmdTargetFilter = ""
  hook.cmdCommandFilter = ""
  hook.cmdQueuePaused = false
  hook.cmdPriority = 3 // Normal priority by default
  hook.cmdTargetViewMode = "compact" // "compact" or "detailed"

  // Per-target parameterized command state
  hook.cmdStagedParams = new Map()      // targetId -> { params: {...} }
  hook.cmdActiveTargetIndex = 0         // Index of currently active target in selection
  hook.cmdPerTargetMode = false         // Whether we're in per-target configuration mode
  hook.cmdReviewMode = false            // Whether showing review screen before queue

  // Persistent staging area (loaded from server)
  hook.cmdStagedCommands = JSON.parse(hook.el.dataset.stagedCommands || '[]')
  hook.cmdStagePanelExpanded = false    // Whether staging panel is expanded
  hook.cmdStagePanelHeight = null       // Custom height when resized (null = auto)
  hook.cmdStageFilter = ''              // Filter text for staging table
  hook.cmdEditingStaged = null          // { cmdIndex, targetIndex } when editing a staged entry
  hook.cmdStageViewMode = 'table'       // 'table' or 'cards' view mode
}

/**
 * Initialize timeline mode state
 * @param {Object} hook - The LiveView hook instance
 */
export function initializeTimelineState(hook) {
  // Timeline mode state
  hook.timelineEvents = JSON.parse(hook.el.dataset.timelineEvents || '[]')
  hook.timelinePaused = false           // Whether live updates are paused
  hook.timelineTypeFilter = new Set(['command', 'alarm', 'procedure', 'automation'])
  hook.timelineTargetFilter = null      // Target ID to filter by, or null for all
  hook.timelineSearchQuery = ''         // Search text filter
  hook.timelineView = 'stream'          // 'stream', 'matrix', or 'lanes'

  // Matrix view state
  hook.matrixGroupBy = 'target'         // 'target', 'group' (for target groups)
  hook.matrixTimeBucket = 15            // Time bucket in minutes (5, 15, 60, 240)
  hook.matrixSelectedCell = null        // { groupId, timeIndex } of selected cell

  // Lanes view state
  hook.lanesPinnedTargets = []          // Array of pinned target IDs
  hook.lanesSelectedEvent = null        // Currently selected event for detail view
  hook.lanesTimeRange = 2               // Hours to show (2, 6, 12, 24)
  hook.lanesScrubbingTime = null        // DateTime when scrubbing, null = live mode
  hook.lanesIsDragging = false          // Whether currently dragging the NOW marker
  hook.lanesActivityExpanded = false    // Whether activity panel is expanded
  hook.lanesActivityHeight = null       // Custom height when resized (null = default)
  hook.lanesTargetSearch = ''           // Target search/filter text for picker
  hook.lanesTargetPanelWidth = 220      // Target panel width in pixels
  hook.lanesViewOffset = 0              // Time offset in ms from NOW (negative = past)
  hook.lanesScrubberPosition = 80       // Scrubber position as percentage (0-100)
  hook.lanesIsPanning = false           // Whether currently panning via drag
  hook.lanesPanStartX = 0               // Mouse X at drag start
  hook.lanesPanStartOffset = 0          // Offset at drag start

  // Stream view enhanced state
  hook.streamExpandedEvent = null       // ID of currently expanded event
  hook.streamExpandedCluster = null     // ID of currently expanded cluster
  hook.streamLoadingMore = false        // Whether currently loading more from server
  hook.streamHasMoreEvents = true       // Whether there are more events to load

  // Stream view target filtering
  hook.streamTargetFilter = new Set()   // Selected target IDs (initialized with all on first render)
  hook.streamTargetFilterInitialized = false  // Whether we've populated initial selection
  hook.streamShowSystem = true          // Show system-level events (no target_id)
  hook.streamTargetSearch = ''          // Target search/filter text
  hook.streamFilterPanelWidth = 30      // Filter panel width percentage (default 30%)
}

/**
 * Reset commands mode state (useful when switching modes)
 * @param {Object} hook - The LiveView hook instance
 */
export function resetCommandsState(hook) {
  hook.cmdSelectedTargets = new Set()
  hook.cmdSelectedCommand = null
  hook.cmdTargetFilter = ""
  hook.cmdCommandFilter = ""
  hook.cmdStagedParams = new Map()
  hook.cmdActiveTargetIndex = 0
  hook.cmdPerTargetMode = false
  hook.cmdReviewMode = false
  hook.cmdEditingStaged = null
}

/**
 * Reset timeline mode state (useful when switching modes)
 * @param {Object} hook - The LiveView hook instance
 */
export function resetTimelineState(hook) {
  hook.streamExpandedEvent = null
  hook.streamExpandedCluster = null
  hook.lanesSelectedEvent = null
  hook.matrixSelectedCell = null
}
