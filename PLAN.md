# Implementation Plan: Epsilon3-Inspired Review & Approval Workflow UI Improvements

## Overview

This plan enhances Cadence's procedure review and approval workflow UI, drawing heavy inspiration from Epsilon3.io. The improvements focus on providing C2 engineers and operators with clear visual feedback, streamlined notifications, and better review status visibility.

## Phase 1: Quick Wins (High Impact, Low Effort)

### 1.1 Add Review Notification Badge to Sidebar Navigation

**Goal**: Show pending review count badge next to "Reviews" nav item (like Epsilon3's bell icon approach).

**Files to modify**:
- `lib/cadence_web/components/layouts.ex` (lines 278-285)
- `lib/cadence_web/live/live_auth.ex` (add review counts to on_mount)

**Implementation**:
1. Extend the existing `on_mount :subscribe_notifications` hook to also load review inbox counts
2. Add `review_pending_count` to socket assigns
3. Modify `sidebar_nav_item` for Reviews to show badge with count

**Pattern to follow**: Existing `notification_unread_count` pattern in layouts.ex (lines 94-96)

```elixir
# In sidebar_navigation, update Reviews nav item:
<.sidebar_nav_item navigate={~p"/reviews"} active={...}>
  <:icon><.icon name="hero-chat-bubble-left-right" class="h-5 w-5" /></:icon>
  <span class="flex items-center gap-2">
    Reviews
    <span :if={@review_pending_count > 0} class="badge badge-xs badge-primary">
      {@review_pending_count}
    </span>
  </span>
</.sidebar_nav_item>
```

### 1.2 Show Approval Progress on Procedure Cards

**Goal**: Display "2/3 approvals" on procedure cards in the procedures list.

**Files to modify**:
- `lib/cadence_web/live/mission_live/procedures/components.ex` (procedure_card)
- `lib/cadence_web/live/mission_live/procedures/index.ex` (load approval data)

**Implementation**:
1. Add `approval_progress` attr to `procedure_card` component
2. Load review status for versions in `in_review` or `changes_requested` status
3. Display compact progress indicator: `2/3` with checkmark icon

**Pattern to follow**: Existing `execution_count` badge in procedure_card (lines 146-154)

```elixir
# New component: approval_progress_badge
attr :approved, :integer, default: 0
attr :required, :integer, default: 0

defp approval_progress_badge(assigns) do
  ~H"""
  <span :if={@required > 0} class={[
    "badge badge-sm gap-1",
    @approved >= @required && "badge-success",
    @approved < @required && "badge-outline"
  ]}>
    <.icon name="hero-check" class="h-3 w-3" />
    {@approved}/{@required}
  </span>
  """
end
```

### 1.3 Visually Distinguish Blocking vs Regular Comments

**Goal**: Make blocking threads (from request_changes reviews) visually prominent.

**Files to modify**:
- `lib/cadence_web/live/review_live/changes.ex` (inline_thread_item, thread_panel)
- `lib/cadence_web/live/review_live/overview.ex` (threads_summary)

**Implementation**:
1. Add red/error styling for threads where `thread.review_id != nil` (blocking)
2. Add "Blocking" badge that's more prominent than current small badge
3. Show blocking threads first in lists

**Pattern to follow**: Existing thread status styling (open=warning, resolved=success)

---

## Phase 2: Enhanced Review Experience (Medium Effort)

### 2.1 Version Comparison Selector

**Goal**: Allow comparing current version against any historical version, not just previous.

**Files to modify**:
- `lib/cadence_web/live/review_live/changes.ex`
- `lib/cadence/procedures/v2.ex` (add compare_versions function if needed)

**Implementation**:
1. Add dropdown in Changes header to select comparison base version
2. Default to "Previous version (v{N-1})"
3. Load diff dynamically when comparison changes
4. Store selected comparison in URL params for shareability

**UI Pattern**:
```
[Compare to: v2 (previous) ▼]  +5 sections, -2 steps, ~3 blocks modified
```

### 2.2 Responsive Thread Panel

**Goal**: Make thread panel work on mobile/tablet screens.

**Files to modify**:
- `lib/cadence_web/live/review_live/changes.ex` (thread_panel component)

**Implementation**:
1. Change fixed `w-96` panel to responsive drawer on mobile
2. Use `lg:w-96 lg:fixed` for desktop, full-screen modal on mobile
3. Add close button always visible on mobile

**Pattern to follow**: Existing drawer pattern in layouts.ex

### 2.3 Real-time Review Updates

**Goal**: Update review status in real-time when others approve/request changes.

**Files to modify**:
- `lib/cadence_web/live/review_live/overview.ex` (add PubSub subscription)
- `lib/cadence/procedures.ex` (broadcast events on review actions)

**Implementation**:
1. Subscribe to `review:#{version_id}` topic in mount
2. Broadcast events on `add_review`, `resolve_thread`, etc.
3. Handle PubSub messages to reload review data
4. Show toast notification when status changes

**Pattern to follow**: Existing notification PubSub pattern in `lib/cadence_web/live/notification_live/index.ex`

---

## Phase 3: Advanced C2 Operations Features (Higher Effort)

### 3.1 Print/Export to PDF

**Goal**: Enable printing procedures for pre-flight reviews, audits, and backup.

**Files to create**:
- `lib/cadence_web/live/procedure_v2_live/print.ex` (print-optimized view)
- `lib/cadence_web/controllers/procedure_pdf_controller.ex` (PDF generation)

**Implementation**:
1. Create print-optimized HTML view with `@media print` styles
2. Add "Print" button to procedure header
3. Consider PDF generation library (chromic_pdf or similar) for true PDF export

### 3.2 Step-Level Sign-offs

**Goal**: Enable role-based sign-offs at individual step level during execution.

**Schema changes needed**:
- Add `step_signoffs` table (step_id, user_id, role, signed_at)
- Add `required_signoffs` to step block configuration

**This is a significant feature requiring**:
- Schema migrations
- New context functions
- Execution LiveView updates
- Potentially new review workflow integration

### 3.3 Conditional Logic Visualization

**Goal**: Show decision trees and conditional branching in review view.

**Files to modify**:
- `lib/cadence_web/live/review_live/changes.ex` (add flow visualization)
- New component for rendering conditional logic diagrams

**Implementation**:
- Parse step conditions and render as visual flow
- Show expected execution paths
- Highlight conditions that depend on telemetry values

---

## Implementation Order

| Priority | Task | Estimated Effort | Dependencies |
|----------|------|------------------|--------------|
| 1 | Review badge in sidebar | 2-3 hours | None |
| 2 | Approval progress on cards | 2-3 hours | None |
| 3 | Blocking thread distinction | 1-2 hours | None |
| 4 | Version comparison selector | 4-6 hours | None |
| 5 | Responsive thread panel | 3-4 hours | None |
| 6 | Real-time review updates | 4-6 hours | PubSub infra |
| 7 | Print/Export to PDF | 8-12 hours | None |
| 8 | Step-level sign-offs | 16-24 hours | Schema design |
| 9 | Conditional logic viz | 12-16 hours | Block config schema |

---

## Files Summary

### Phase 1 Files to Modify:
- `lib/cadence_web/components/layouts.ex`
- `lib/cadence_web/live/live_auth.ex`
- `lib/cadence_web/live/mission_live/procedures/components.ex`
- `lib/cadence_web/live/mission_live/procedures/index.ex`
- `lib/cadence_web/live/review_live/changes.ex`
- `lib/cadence_web/live/review_live/overview.ex`

### Phase 2 Files to Modify:
- `lib/cadence_web/live/review_live/changes.ex`
- `lib/cadence/procedures.ex`

### Phase 3 Files to Create:
- `lib/cadence_web/live/procedure_v2_live/print.ex`
- `lib/cadence_web/controllers/procedure_pdf_controller.ex`
- Migrations for step_signoffs

---

## Design Principles

1. **Follow existing patterns**: Use DaisyUI components, status_badge patterns, PubSub infrastructure
2. **Maintain HUD aesthetic**: Keep the mission control visual language consistent
3. **Progressive enhancement**: Start with visual improvements, then add interactivity
4. **Mobile consideration**: Ensure all features work on tablets (common in C2 environments)
5. **Real-time first**: Leverage LiveView's real-time capabilities for collaborative reviews

---

## Questions for User

1. **Priority confirmation**: Should we start with Phase 1 Quick Wins, or are there specific Phase 2/3 items you'd like to prioritize?

2. **Step-level sign-offs**: Is this a critical requirement for your C2 operations, or can it be deferred?

3. **PDF generation**: Do you have a preferred PDF library, or should we start with print-optimized HTML and add true PDF later?

4. **Version comparison**: Should comparison persist in URL (shareable links) or just be session state?
