# Chaos lab (paused)

The chaos lab is paused. On 2026-11-28, #1128 removed its direct Earendil seed and activation actions. `dev/chaos/lab.py` can still build, deploy, inspect, and renew contacts in an already seeded lab, but it cannot prepare a fresh dataset or run a valid fresh continuity experiment.

Before reviving it, add a standalone REST seed for the lab's production-like image. The seed must use `/api/v1` and person sessions, including the independent approver. That image does not compile the development `/dev/mailbox/json` route, so invitation links need a real SMTP sink with a mailbox API that the seed can read. Do not add a development mailbox route or an invitation-token shortcut to the production build. The revival must also migrate QuestDB and establish the active mission and contacts before traffic starts.

`dev/reflect_orbital/{fixture,configuration,activation,live_contacts}.exs` remain for the scale harness and development commands. The lab's `renew-contacts` command uses `live_contacts.exs` only after a dataset already exists.
