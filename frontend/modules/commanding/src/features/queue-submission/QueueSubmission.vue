<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import { priorityLabel } from "../../shared/priority";
import type { QueuePage, Actor } from "./contracts";
import { useQueueSubmission } from "./useQueueSubmission";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: QueuePage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const {
  model,
  preview,
  request,
  operation,
  busy,
  reading,
  confirmed,
  feedback,
  locked,
  canQueue,
  monitor,
  review,
  submit,
  refresh,
  follow,
} = useQueueSubmission(props.page, props.port, props.readPort);
const format = (v: unknown) => (v === null || v === "" ? "Not recorded" : String(v));
const actor = (v: Actor) =>
  v.display_name ?? v.user_id ?? v.service_identity_id ?? v.id ?? "Not recorded";
</script>
<template>
  <CadenceOpsViewport id="command-queue">
    <CadencePageHeading>
      <template #eyebrow>{{ model.mission_name }} / Commanding</template>
      <template #title>Queue command</template>
      <template #description
        >Review the approved request before admitting it for dispatch.</template
      >
      <template #actions
        ><a
          id="command-queue-back"
          :href="monitor"
          class="btn btn-ghost btn-sm"
          @click="follow($event, monitor)"
          >Return to Commands</a
        ></template
      >
    </CadencePageHeading>
    <CadenceOpsListBodyFrame>
      <div class="flex flex-wrap items-center justify-between gap-3 text-xs text-base-content/70">
        <p>
          Observed <time :datetime="model.observed_at">{{ model.observed_at }}</time>
        </p>
        <button
          id="command-queue-refresh"
          type="button"
          class="btn btn-ghost btn-sm"
          :disabled="busy || reading"
          @click="refresh"
        >
          {{ reading ? "Refreshing…" : "Refresh request and receipt" }}
        </button>
      </div>
      <p v-if="feedback" id="command-queue-feedback" role="alert" class="text-sm text-warning">
        {{ feedback }}
      </p>
      <section
        class="border border-base-300 bg-base-100 p-4 space-y-4"
        aria-labelledby="command-queue-request-title"
      >
        <div class="flex flex-wrap justify-between gap-3">
          <h2 id="command-queue-request-title" class="font-semibold">
            {{ request.command_display_name || request.command_name || request.command_id }}
          </h2>
          <span id="command-queue-request-state" class="badge badge-outline">{{
            model.request.lifecycle_state
          }}</span>
        </div>
        <p
          v-if="request.hazardous || request.critical"
          id="command-queue-criticality"
          role="note"
          class="border-l-2 border-warning pl-3 text-sm text-warning"
        >
          {{ request.hazardous ? "Hazardous command" : "Critical command" }}. Confirm the approved
          target, arguments and timing before queueing.
        </p>
        <dl class="grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="field in [
              ['Request ID', request.command_request_id],
              ['Target', model.target_name || 'Unnamed target'],
              ['Mission model', request.mission_model_revision_id],
              ['Command ID', request.command_id],
              ['Priority', priorityLabel(request.priority)],
              ['Not before', request.not_before],
              ['Expires at', request.expires_at],
              ['Requested by', actor(request.requested_by)],
              ['Requested at', request.requested_at],
              ['Uplink service', request.preferred_uplink_service],
              ['APID', request.apid],
              ['Opcode', request.opcode_json],
            ]"
            :key="String(field[0])"
            class="min-w-0"
          >
            <dt class="text-xs text-base-content/60">{{ field[0] }}</dt>
            <dd class="mt-1 break-all font-mono text-xs">{{ format(field[1]) }}</dd>
          </div>
        </dl>
        <div class="grid gap-4 lg:grid-cols-2">
          <div class="min-w-0">
            <h3 class="mb-2 text-xs font-semibold">Supplied arguments</h3>
            <pre
              id="command-queue-supplied"
              class="whitespace-pre-wrap break-all border border-base-300 bg-base-200/30 p-3 text-xs"
              >{{ request.argument_values_json }}</pre>
          </div>
          <div class="min-w-0">
            <h3 class="mb-2 text-xs font-semibold">Resolved arguments to dispatch</h3>
            <pre
              id="command-queue-resolved"
              class="whitespace-pre-wrap break-all border border-base-300 bg-base-200/30 p-3 text-xs"
              >{{ request.resolved_argument_values_json }}</pre>
          </div>
        </div>
        <div
          v-if="preview"
          id="command-queue-approval"
          class="border-t border-base-300 pt-3 text-xs space-y-1"
        >
          <p>
            Approved by {{ actor(preview.approval.actor) }} at {{ preview.approval.decided_at }}
          </p>
          <p class="break-all font-mono">{{ preview.approval.id }}</p>
          <details>
            <summary class="cursor-pointer text-base-content/70">
              Approved content reference
            </summary>
            <code class="block break-all pt-2">{{ preview.approval.basis_sha256 }}</code>
          </details>
        </div>
        <a
          id="command-queue-review"
          :href="review"
          class="link text-sm"
          @click="follow($event, review)"
          >View request and approval history</a
        >
      </section>
      <section
        v-if="model.queue"
        id="command-queue-existing"
        class="border border-base-300 bg-base-100 p-4 space-y-2"
        aria-labelledby="command-queue-entry-title"
      >
        <h2 id="command-queue-entry-title" class="font-semibold">Observed queue entry</h2>
        <p class="text-sm">{{ model.queue.state }} · Sequence {{ model.queue.sequence }}</p>
        <p class="break-all font-mono text-xs">{{ model.queue.id }}</p>
        <p class="text-xs text-base-content/70">
          Queued by {{ actor(model.queue.actor) }} at {{ model.queue.enqueued_at }}
        </p>
      </section>
      <p
        v-else-if="model.availability === 'approval_required'"
        id="command-queue-unavailable"
        role="status"
        class="text-sm"
      >
        This request needs approval before it can enter the queue.
      </p>
      <p
        v-else-if="model.availability === 'expired' || model.availability === 'closed'"
        id="command-queue-unavailable"
        role="status"
        class="text-sm"
      >
        This request is no longer available to queue. Review its current state in Commands.
      </p>
      <form
        v-if="preview && model.availability === 'available' && (!operation || busy)"
        id="command-queue-form"
        class="border border-warning/40 bg-warning/5 p-4 space-y-4"
        @submit.prevent="submit"
      >
        <p class="text-sm">
          Queue admission can lead to immediate transmission when an eligible route is available.
        </p>
        <label class="flex items-start gap-3 text-sm" for="command-queue-confirm"
          ><input
            id="command-queue-confirm"
            v-model="confirmed"
            type="checkbox"
            class="checkbox checkbox-sm mt-0.5"
            :disabled="locked"
          /><span
            >I have reviewed the target, resolved arguments and timing, and I authorize this command
            to enter the dispatch queue.</span
          ></label
        >
        <button
          id="command-queue-submit"
          type="submit"
          class="btn btn-primary btn-sm"
          :disabled="!canQueue || !confirmed"
        >
          {{ busy ? "Queueing…" : "Queue command" }}
        </button>
      </form>
      <section
        v-if="operation?.status === 'unconfirmed'"
        id="command-queue-unconfirmed"
        role="status"
        class="border border-warning/40 p-4 space-y-2"
      >
        <h2 class="font-semibold">Queue result unconfirmed</h2>
        <p class="text-sm">
          This attempt will not be sent again. Refresh the request and receipt to check whether it
          entered the queue.
        </p>
      </section>
      <p
        v-if="operation?.status === 'rejected'"
        id="command-queue-rejected"
        role="alert"
        class="border border-warning/40 p-4 text-sm"
      >
        {{ operation.feedback }}
      </p>
      <section
        v-if="operation?.status === 'completed'"
        id="command-queue-receipt"
        role="status"
        class="border border-success/40 bg-success/5 p-4 space-y-2"
      >
        <h2 class="font-semibold">Command queued</h2>
        <p class="break-all font-mono text-xs">{{ operation.receipt.queue_id }}</p>
        <p class="text-sm">Queue entry created at {{ operation.receipt.enqueued_at }}.</p>
        <p class="text-sm">Release and verification status are available in Commands.</p>
        <a
          id="command-queue-receipt-monitor"
          :href="monitor"
          class="link text-sm"
          @click="follow($event, monitor)"
          >View command status</a
        >
      </section>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
