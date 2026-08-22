  ✅ Fully Migrated Contexts (10)

  | Context             | Domain | Ports | Adapters | Application |
  |---------------------|--------|-------|----------|-------------|
  | Accounts            | ✓      | ✓     | ✓        | ✓           |
  | Organizations       | ✓      | ✓     | ✓        | ✓           |
  | Schedules           | ✓      | ✓     | ✓        | ✓           |
  | Dashboard Layouts   | ✓      | ✓     | ✓        | ✓           |
  | Automations         | ✓      | ✓     | ✓        | ✓           |
  | Alerting (Alarms)   | ✓      | ✓     | ✓        | ✓           |
  | Targeting (Targets) | ✓      | ✓     | ✓        | ✓           |
  | Commanding          | ✓      | ✓     | ✓        | ✓           |
  | Interfaces          | ✓      | ✓     | ✓        | ✓           |
  | Procedures          | ✓      | ✓     | ✓        | ✓           |

  ⚠️ Partially Migrated (2)

  | Context       | Issue                                                                        |
  |---------------|------------------------------------------------------------------------------|
  | Settings      | Has ports/adapters but no domain entities - works directly with Ecto schemas |
  | Notifications | Has ports but no domain layer, business logic mixed in facade                |

  ✅ Recently Completed

  | Context   | Status                                                                       |
  |-----------|------------------------------------------------------------------------------|
  | Missions  | Full hexagonal + runtime separation (domain, application, ports, adapters)  |
  | Interfaces| Runtime refactoring complete - entity injection, hot reload via PubSub       |

  ❌ Legacy/Non-Hexagonal Contexts (7)

  | Context         | Pattern        | Issues                                                    |
  |-----------------|----------------|-----------------------------------------------------------|
  | Recordings      | Event sourcing | Direct Repo.all(), import Ecto.Query, no ports/adapters   |
  | Shifts          | Pure Ecto      | Direct Repo.get(), Repo.insert(), no abstraction          |
  | Buckets         | Pure Ecto      | Direct Repo calls, no repository pattern                  |
  | Timeline        | Hybrid         | Direct Ecto queries, works with Recording schema directly |
  | Outbox          | Custom         | Transactional outbox pattern, direct Ecto                 |
  | Telemetry       | Streaming      | Complex Broadway/GenStage, no hexagonal layers            |
  | MissionDatabase | Unknown        | Needs detailed analysis                                   |

  Priority Migration Order

  1. Notifications - Already has port infrastructure, just needs domain entities
  2. Settings - Simple context, quick win to add domain layer
  3. Shifts - Small context, straightforward migration
  4. Buckets - Small context with polymorphic protocol
  5. Recordings - Core event system, more complex
  6. Timeline - Depends on Recordings
  7. Telemetry - Complex streaming, may need custom approach
  8. Outbox - Custom pattern, evaluate if hexagonal makes sense