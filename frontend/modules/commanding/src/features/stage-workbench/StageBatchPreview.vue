<script setup lang="ts">
import { targetLabel } from "../../shared/command-draft/target-label";
import { parseArgumentValues } from "../../shared/command-draft/exact-values";
import { priorityLabel } from "../../shared/priority";
import type { BatchPreview } from "./contracts";
defineProps<{ preview: BatchPreview; disabled: boolean; confirmed: boolean }>();
const emit = defineEmits<{ "update:confirmed": [value: boolean]; submit: [] }>();
</script>
<template>
  <section
    id="stage-batch-preview"
    class="border border-info/40 bg-base-100 p-4 space-y-5"
    aria-labelledby="stage-batch-title"
  >
    <h2 id="stage-batch-title" class="font-semibold">
      Review {{ preview.requests.length }} formal request{{
        preview.requests.length === 1 ? "" : "s"
      }}
    </h2>
    <p class="text-sm text-base-content/70">
      This submits the selected drafts. Required human approval and governed release remain separate
      steps.
    </p>
    <article
      v-for="request in preview.requests"
      :key="request.request_id"
      :data-reviewed-item="request.item_id"
      class="border-t border-base-300 pt-4 space-y-3"
    >
      <h3 class="font-semibold text-sm">
        {{ request.command_display_name || request.command_name }} →
        {{ targetLabel(request.target) }}
      </h3>
      <p v-if="request.hazardous || request.critical" class="text-sm text-warning">
        {{ request.hazardous ? "Hazardous command" : "Critical command" }} ·
        {{
          request.lifecycle_state === "approval_pending"
            ? "A separate reviewer is required"
            : "Review safety conditions before release"
        }}
      </p>
      <dl class="grid gap-2 text-xs md:grid-cols-2">
        <div>
          <dt class="text-base-content/50">Model revision</dt>
          <dd class="font-mono break-all">{{ request.revision_id }}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">Reserved request</dt>
          <dd class="font-mono break-all">{{ request.request_id }}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">Actor</dt>
          <dd class="font-mono break-all">{{ request.actor_id }}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">Timing</dt>
          <dd>
            {{ request.not_before || "No start restriction" }} →
            {{ request.expires_at || "No expiry" }}
          </dd>
        </div>
        <div>
          <dt class="text-base-content/50">Priority / order</dt>
          <dd>{{ priorityLabel(request.priority) }} / {{ request.order }}</dd>
        </div>
      </dl>
      <dl class="text-sm">
        <div
          v-for="(value, name) in parseArgumentValues(
            request.resolved_argument_values_json,
            131072,
          )"
          :key="name"
          class="flex flex-wrap justify-between gap-2 py-1"
        >
          <dt>{{ name }}</dt>
          <dd class="font-mono break-all">{{ value }}</dd>
        </div>
      </dl>
      <p v-if="request.notes" class="text-xs whitespace-pre-wrap">{{ request.notes }}</p>
    </article>
    <label class="flex gap-2 text-sm"
      ><input
        id="stage-batch-confirm"
        type="checkbox"
        class="checkbox checkbox-sm"
        :disabled="disabled"
        :checked="confirmed"
        @change="emit('update:confirmed', ($event.target as HTMLInputElement).checked)"
      />I reviewed these exact commands, targets, resolved arguments and timing.</label
    ><button
      id="stage-batch-submit"
      class="btn btn-primary"
      :disabled="disabled || !confirmed"
      @click="emit('submit')"
    >
      Create {{ preview.requests.length }} formal request{{
        preview.requests.length === 1 ? "" : "s"
      }}
    </button>
  </section>
</template>
