<script setup lang="ts">
import type { CommandObservation } from "./monitor.contracts";
defineProps<{ row: CommandObservation }>();
const label = (value: string | null) => value?.replaceAll("_", " ") ?? "Not recorded";
</script>
<template>
  <div class="space-y-3 text-xs">
    <p
      v-if="row.queue?.state === 'release_pending'"
      data-command-release-held
      role="status"
      class="border-l-2 border-warning pl-3 text-warning"
    >
      {{
        row.release?.state === "release_uncertain"
          ? "Transmission outcome uncertain."
          : "Release completion has not been confirmed."
      }}
      This command may have been transmitted. Its queue lane remains held; it will not be
      automatically retried.
    </p>
    <dl class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <div>
        <dt class="hud-label">Request</dt>
        <dd class="mt-1 break-all font-mono">{{ row.id }} · {{ label(row.request_state) }}</dd>
      </div>
      <div>
        <dt class="hud-label">Verification</dt>
        <dd class="mt-1 font-mono">{{ label(row.verification_state) }}</dd>
      </div>
      <div>
        <dt class="hud-label">Requested</dt>
        <dd class="mt-1">
          <time v-if="row.requested_at" :datetime="row.requested_at">{{ row.requested_at }}</time
          ><span v-else>Not recorded</span>
        </dd>
      </div>
      <div>
        <dt class="hud-label">Projection ordering time</dt>
        <dd class="mt-1">
          <time v-if="row.occurred_at" :datetime="row.occurred_at">{{ row.occurred_at }}</time
          ><span v-else>Not recorded</span>
          <p class="mt-1 text-base-content/70">May include a verifier deadline.</p>
        </dd>
      </div>
      <div v-if="row.queue" :data-command-queue="row.queue.id">
        <dt class="hud-label">Queue entry</dt>
        <dd class="mt-1 break-all font-mono">
          {{ row.queue.id }} · {{ label(row.queue.state) }}<br />Lane {{ row.queue.lane
          }}<br /><time v-if="row.queue.enqueued_at" :datetime="row.queue.enqueued_at">{{
            row.queue.enqueued_at
          }}</time>
        </dd>
      </div>
      <div v-else>
        <dt class="hud-label">Queue entry</dt>
        <dd class="mt-1">Not recorded</dd>
      </div>
      <div v-if="row.release" :data-command-release="row.release.id" class="sm:col-span-2">
        <dt class="hud-label">Release attempt</dt>
        <dd class="mt-1 break-all font-mono">
          {{ row.release.id }} · {{ label(row.release.state) }}<br />Queue
          {{ row.release.queue_entry_id }} · Contact {{ row.release.contact_id }}<br />Verification
          {{ label(row.release.verification_state) }}<br /><span v-if="row.release.attempted_at"
            >Attempted
            <time :datetime="row.release.attempted_at">{{ row.release.attempted_at }}</time></span
          ><br /><span v-if="row.release.released_at"
            >Released
            <time :datetime="row.release.released_at">{{ row.release.released_at }}</time></span
          >
        </dd>
      </div>
      <div v-else>
        <dt class="hud-label">Release attempt</dt>
        <dd class="mt-1">Not recorded</dd>
      </div>
    </dl>
    <div class="border-t border-base-300 pt-3">
      <p class="hud-label">Verifier records · {{ row.verifier_total }}</p>
      <p v-if="row.verifier_total === 0" class="mt-2 text-base-content/70">No verifier records.</p>
      <ul v-else class="mt-2 space-y-2">
        <li
          v-for="verifier in row.verifiers"
          :key="verifier.id"
          :data-command-verifier="verifier.id"
          class="border-l border-base-300 pl-3"
        >
          <p class="font-semibold">{{ verifier.name }} · {{ label(verifier.state) }}</p>
          <p class="break-all font-mono text-base-content/75">
            {{ verifier.id }} · Release {{ verifier.release_attempt_id }}
          </p>
          <p v-if="verifier.matched_record_id" class="break-all font-mono">
            {{ label(verifier.matched_record_kind) }} · {{ verifier.matched_record_id }}
          </p>
          <p v-if="verifier.matched_at">
            Matched <time :datetime="verifier.matched_at">{{ verifier.matched_at }}</time>
          </p>
          <p v-if="verifier.timeout_at">
            Deadline <time :datetime="verifier.timeout_at">{{ verifier.timeout_at }}</time>
          </p>
        </li>
      </ul>
      <p v-if="row.verifier_total > row.verifiers.length" class="mt-2 text-warning">
        Showing {{ row.verifiers.length }} of {{ row.verifier_total }} verifier records. This is not
        the complete evidence history.
      </p>
    </div>
  </div>
</template>
