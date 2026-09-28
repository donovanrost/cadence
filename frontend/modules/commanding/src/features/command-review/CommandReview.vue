<script setup lang="ts">
import { priorityLabel } from "../../shared/priority";
import { queueSubmissionHref } from "@cadence/commanding/queue-submission";
import { computed, onBeforeUnmount, ref, shallowRef } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import {
  commandReviewHref,
  decisionInput,
  readCommandReviewPage,
  readOperation,
  type CommandReviewPage,
  type Decision,
  type Operation,
  type Actor,
} from "./contracts";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  page: CommandReviewPage;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
}>();
// Keep the reviewed basis captured until an explicit read. A new host token remounts the page.
const page = shallowRef(props.page),
  operation = shallowRef<Operation | null>(props.page.operation);
const choice = ref<Decision | "">(""),
  reason = ref(""),
  confirmed = ref(false),
  busy = ref(false),
  reading = ref(false),
  feedback = ref("");
const disposeGuard = props.port.guardNavigation?.(() => !busy.value);
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
  disposeGuard?.();
});
const review = computed(() => page.value.review),
  request = computed(() => review.value.request);
const context = { ...props.page.review.context },
  reviewer = props.page.review.actor_id;
const allowed = computed(
  () => review.value.can_decide && !operation.value && !busy.value && !reading.value,
);
const monitor = `/missions/${encodeURIComponent(context.missionId)}/ops/commands?focus_command_id=${encodeURIComponent(context.resourceId)}`;
const format = (v: unknown) =>
  v === null ? "Not recorded" : typeof v === "object" ? JSON.stringify(v, null, 2) : String(v);
const actor = (v: Actor) => v.user_id ?? v.service_identity_id ?? "Not recorded";
async function submit() {
  if (!allowed.value || !confirmed.value) return;
  let input;
  try {
    input = decisionInput(choice.value, reason.value, review.value.expected_review);
  } catch {
    feedback.value = "Choose a decision and keep the reason within 2,000 bytes.";
    return;
  }
  busy.value = true;
  feedback.value = "";
  operation.value = { status: "unconfirmed" };
  try {
    const result = await props.port.execute("decide", input);
    if (!disposed) operation.value = readOperation(result, context.resourceId, reviewer);
  } catch {
    /* Keep the consumed submission unconfirmed until a successful read. */
  } finally {
    if (!disposed) busy.value = false;
  }
}
async function refresh() {
  if (busy.value || reading.value) return;
  reading.value = true;
  feedback.value = "";
  try {
    const result = readCommandReviewPage(await props.readPort.read(), context);
    if (result.review.actor_id !== reviewer) throw Error("Changed actor");
    if (!disposed) {
      if (result.review.expected_review !== review.value.expected_review) {
        choice.value = "";
        confirmed.value = false;
        if (!operation.value)
          feedback.value = "The request changed. Review its current details and confirm again.";
      }
      page.value = result;
      if (result.operation) operation.value = result.operation;
    }
  } catch {
    if (!disposed)
      feedback.value = operation.value
        ? "The request could not be refreshed. Your decision will not be sent again."
        : "The request could not be refreshed. The last observed details remain visible.";
  } finally {
    if (!disposed) reading.value = false;
  }
}
function follow(event: MouseEvent, href: string) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  if (!busy.value && !reading.value) props.port.navigate(href);
}
</script>
<template>
  <CadenceOpsViewport id="command-review">
    <CadencePageHeading>
      <template #eyebrow>{{ review.mission_name }} / Commanding</template>
      <template #title>{{ request.command_display_name || request.command_name }}</template>
      <template #description
        >Review the formal command request and record a human decision.</template
      >
      <template #actions
        ><a
          id="command-review-back"
          :href="monitor"
          class="btn btn-ghost btn-sm"
          @click="follow($event, monitor)"
          >Return to Commands</a
        ></template
      >
    </CadencePageHeading>
    <a
      id="command-review-queue"
      :href="queueSubmissionHref(context.missionId, context.resourceId)"
      class="btn btn-primary btn-sm self-start"
      @click="follow($event, queueSubmissionHref(context.missionId, context.resourceId))"
      >{{
        ["validated", "approved"].includes(request.lifecycle_state) ||
        (operation?.status === "completed" && operation.receipt.decision === "approved")
          ? "Review for queueing"
          : "Queue details"
      }}</a
    >
    <CadenceOpsListBodyFrame>
      <div class="flex flex-wrap items-center justify-between gap-3 text-xs text-base-content/70">
        <p>
          Observed <time :datetime="review.observed_at">{{ review.observed_at }}</time>
        </p>
        <button
          id="command-review-refresh"
          class="btn btn-ghost btn-sm"
          :disabled="busy || reading"
          @click="refresh"
        >
          {{ reading ? "Refreshing…" : "Refresh request and receipt" }}
        </button>
      </div>
      <p v-if="feedback" id="command-review-feedback" role="alert" class="text-sm text-warning">
        {{ feedback }}
      </p>
      <section
        class="border border-base-300 bg-base-100 p-4 space-y-4"
        aria-labelledby="review-request-title"
      >
        <div class="flex flex-wrap justify-between gap-3">
          <h2 id="review-request-title" class="font-semibold">Request details</h2>
          <span id="command-review-state" class="badge badge-outline">{{
            format(request.lifecycle_state)
          }}</span>
        </div>
        <p
          v-if="request.critical || request.hazardous"
          id="command-review-criticality"
          role="note"
          class="border-l-2 border-warning pl-3 text-sm text-warning"
        >
          {{ request.hazardous ? "Hazardous command" : "Critical command" }}. Verify the target,
          arguments and timing before recording a decision.
        </p>
        <dl class="grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="field in [
              ['Request ID', request.command_request_id],
              ['Command target', review.target_name || 'Unnamed target'],
              ['Model revision', request.mission_model_revision_id],
              ['Command ID', request.command_id],
              ['Command name', request.command_name],
              ['Requested by', actor(request.requested_by)],
              ['Requested at', request.requested_at],
              ['Not before', request.not_before],
              ['Expires at', request.expires_at],
              ['Priority', priorityLabel(request.priority)],
              ['Significance', request.significance],
              ['Critical', request.critical],
              ['Hazardous', request.hazardous],
              ['Stage', request.source_command_stage_id],
              ['Staged item', request.source_staged_command_item_id],
              ['Subsystem', request.subsystem],
              ['Group', request.group_name],
              ['Uplink service preference', request.preferred_uplink_service],
              ['Release policy hint', request.release_policy_hint],
              ['APID', request.apid],
              ['Service type', request.service_type],
              ['Service subtype', request.service_subtype],
              ['Opcode', request.opcode_json === 'null' ? null : request.opcode_json],
              ['Verification state', request.verification_state],
            ]"
            :key="String(field[0])"
            class="min-w-0"
          >
            <dt class="hud-label">{{ field[0] }}</dt>
            <dd
              class="mt-1 whitespace-pre-wrap break-all font-mono text-xs"
              :data-review-field="field[0]"
            >
              {{ format(field[1]) }}
            </dd>
          </div>
        </dl>
      </section>
      <div class="grid gap-4 lg:grid-cols-2">
        <section
          v-for="item in [
            { id: 'submitted', title: 'Submitted arguments', values: request.argument_values_json },
            {
              id: 'resolved',
              title: 'Resolved arguments',
              values: request.resolved_argument_values_json,
            },
          ]"
          :key="item.id"
          class="min-w-0 border border-base-300 bg-base-100 p-4 space-y-3"
          :aria-labelledby="`review-${item.id}-title`"
        >
          <h2 :id="`review-${item.id}-title`" class="font-semibold">{{ item.title }}</h2>
          <pre
            :id="`review-${item.id}-arguments`"
            class="whitespace-pre-wrap break-all font-mono text-xs"
            >{{ item.values }}</pre>
        </section>
      </div>
      <section
        class="border border-base-300 bg-base-100 p-4 space-y-4"
        aria-labelledby="review-decision-title"
      >
        <h2 id="review-decision-title" class="font-semibold">Review decision</h2>
        <div v-if="operation" id="command-review-operation" role="status" class="space-y-2 text-sm">
          <template v-if="operation.status === 'completed'"
            ><p>
              Decision recorded: <strong>{{ format(operation.receipt.decision) }}</strong
              >.
            </p>
            <p class="break-all font-mono text-xs" data-review-receipt>
              {{ operation.receipt.approval_id }} · {{ operation.receipt.decided_at }}
            </p>
            <p>Approval records the review. Queueing and release are separate steps.</p></template
          >
          <p v-else-if="operation.status === 'rejected'">{{ operation.feedback }}</p>
          <p v-else>
            {{
              busy
                ? "Recording your decision…"
                : "The result is unconfirmed. Refresh the receipt to check whether it was recorded. This page will not send the decision again."
            }}
          </p>
        </div>
        <p
          v-else-if="!review.can_decide"
          id="command-review-readonly"
          class="text-sm text-base-content/70"
        >
          {{
            request.lifecycle_state === "approval_pending"
              ? "A different person must review this request."
              : "This request is not awaiting a decision."
          }}
        </p>
        <form v-else id="command-review-form" class="space-y-4" @submit.prevent="submit">
          <div class="max-w-sm space-y-1">
            <label for="command-review-choice" class="hud-label">Decision</label
            ><select
              id="command-review-choice"
              v-model="choice"
              class="select select-bordered w-full"
              :disabled="!allowed"
              required
            >
              <option value="" disabled>Choose a decision</option>
              <option value="approved">Approve</option>
              <option value="rejected">Reject</option>
            </select>
          </div>
          <div class="space-y-1">
            <label for="command-review-reason" class="hud-label">Review reason (optional)</label
            ><textarea
              id="command-review-reason"
              v-model="reason"
              class="textarea textarea-bordered w-full"
              rows="3"
              maxlength="2000"
              :disabled="!allowed"
            />
          </div>
          <label class="flex items-start gap-3 text-sm"
            ><input
              id="command-review-confirm"
              v-model="confirmed"
              type="checkbox"
              class="checkbox checkbox-sm"
              :disabled="!allowed"
              required
            /><span
              >I reviewed the target, model revision, arguments, criticality and timing shown
              above.</span
            ></label
          >
          <button
            id="command-review-submit"
            class="btn btn-primary"
            type="submit"
            :disabled="!allowed || !confirmed || !choice"
          >
            Record decision
          </button>
        </form>
      </section>
      <section
        class="border border-base-300 bg-base-100 p-4 space-y-4"
        aria-labelledby="review-history-title"
      >
        <h2 id="review-history-title" class="font-semibold">Decision history</h2>
        <p v-if="!review.history.entries.length" class="text-sm text-base-content/70">
          No decisions on this page.
        </p>
        <ol v-else id="command-review-history" class="divide-y divide-base-300">
          <li
            v-for="entry in review.history.entries"
            :key="entry.id"
            :data-approval-id="entry.id"
            class="space-y-2 py-3 text-sm"
          >
            <p>
              <strong>{{ format(entry.decision) }}</strong> · {{ actor(entry.actor) }} ·
              <time :datetime="entry.decided_at">{{ entry.decided_at }}</time>
            </p>
            <p class="break-all font-mono text-xs">{{ entry.id }}</p>
            <p v-if="entry.reason" class="whitespace-pre-wrap break-words">{{ entry.reason }}</p>
          </li>
        </ol>
        <nav aria-label="Decision history pages" class="flex flex-wrap gap-3">
          <a
            v-if="review.query.after"
            id="review-history-first"
            :href="commandReviewHref(context.missionId, context.resourceId)"
            class="btn btn-ghost btn-sm"
            @click="follow($event, commandReviewHref(context.missionId, context.resourceId))"
            >First decisions</a
          ><a
            v-if="review.history.next_after"
            id="review-history-next"
            :href="
              commandReviewHref(context.missionId, context.resourceId, review.history.next_after)
            "
            class="btn btn-ghost btn-sm"
            @click="
              follow(
                $event,
                commandReviewHref(
                  context.missionId,
                  context.resourceId,
                  review.history.next_after!,
                ),
              )
            "
            >More decisions</a
          >
        </nav>
      </section>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
