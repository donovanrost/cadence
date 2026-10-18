<script setup lang="ts">
import type { HistoryModel } from "./types";
defineProps<{ evidence: HistoryModel["evidence"] }>();
const label = (value: string | null) => value?.replaceAll("_", " ") ?? "Not recorded";
</script>
<template>
  <section
    id="command-history-evidence"
    class="space-y-4 border border-base-300 bg-base-200/20 p-4"
  >
    <h2 class="font-semibold">Matched evidence</h2>
    <p v-if="evidence.status === 'not_selected'" role="status" class="text-sm text-base-content/75">
      Select a verifier to inspect its recorded match.
    </p>
    <p
      v-else-if="evidence.status === 'unmatched'"
      role="status"
      class="text-sm text-base-content/75"
    >
      This verifier has no recorded match. Its state and deadline are shown above.
    </p>
    <p
      v-else-if="evidence.status === 'unavailable'"
      id="command-history-evidence-unavailable"
      role="status"
      class="text-sm text-warning"
    >
      The matched record is unavailable. You can continue reviewing this command's history.
    </p>
    <template v-else-if="evidence.status === 'ready'">
      <p :data-command-evidence="evidence.record.id" class="break-all font-mono text-xs">
        {{ label(evidence.record.kind) }} · {{ evidence.record.id }}
      </p>
      <template v-if="evidence.record.kind === 'telemetry_sample'">
        <dl class="grid gap-4 text-xs sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt class="hud-label">Telemetry point</dt>
            <dd class="mt-1 break-all">
              {{ evidence.record.point_name }}<br />{{ evidence.record.point_id }}
            </dd>
          </div>
          <div>
            <dt class="hud-label">Packet</dt>
            <dd class="mt-1 break-all font-mono">{{ evidence.record.packet_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Evidence</dt>
            <dd class="mt-1 break-all font-mono">{{ evidence.record.evidence_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Spacecraft</dt>
            <dd class="mt-1 break-all font-mono">
              {{ evidence.record.spacecraft_id ?? "Not recorded" }}
            </dd>
          </div>
          <div>
            <dt class="hud-label">Quality</dt>
            <dd class="mt-1">{{ evidence.record.quality_state }}</dd>
          </div>
          <div>
            <dt class="hud-label">Received</dt>
            <dd class="mt-1 break-all">
              <time :datetime="evidence.record.receipt_time">{{
                evidence.record.receipt_time
              }}</time>
            </dd>
          </div>
          <div>
            <dt class="hud-label">Generated</dt>
            <dd class="mt-1 break-all">
              <time
                v-if="evidence.record.generation_time"
                :datetime="evidence.record.generation_time"
                >{{ evidence.record.generation_time }}</time
              ><span v-else>Not recorded</span>
            </dd>
          </div>
        </dl>
        <div class="grid min-w-0 gap-4 lg:grid-cols-2">
          <div class="min-w-0">
            <h3 class="mb-2 text-xs font-semibold">Raw value</h3>
            <pre
              id="command-history-raw-value"
              class="max-h-80 overflow-auto whitespace-pre-wrap break-all font-mono text-xs"
              >{{ evidence.record.raw_value_json }}</pre>
          </div>
          <div class="min-w-0">
            <h3 class="mb-2 text-xs font-semibold">Engineering value</h3>
            <pre
              id="command-history-engineering-value"
              class="max-h-80 overflow-auto whitespace-pre-wrap break-all font-mono text-xs"
              >{{ evidence.record.engineering_value_json }}</pre>
          </div>
        </div>
      </template>
      <template v-else>
        <dl class="grid gap-4 text-xs sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt class="hud-label">Request</dt>
            <dd class="mt-1 break-all font-mono">{{ evidence.record.request_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Release attempt</dt>
            <dd class="mt-1 break-all font-mono">{{ evidence.record.release_attempt_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Contact</dt>
            <dd class="mt-1 break-all font-mono">{{ evidence.record.contact_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Path</dt>
            <dd class="mt-1 break-all font-mono">{{ evidence.record.path_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Transport family</dt>
            <dd class="mt-1 break-all">{{ label(evidence.record.family_key) }}</dd>
          </div>
          <template v-if="evidence.record.kind === 'transport_action_request'">
            <div>
              <dt class="hud-label">Signal phase</dt>
              <dd class="mt-1">{{ label(evidence.record.signal_phase) }}</dd>
            </div>
            <div>
              <dt class="hud-label">Action</dt>
              <dd class="mt-1">{{ label(evidence.record.action_kind) }}</dd>
            </div>
            <div>
              <dt class="hud-label">Requested</dt>
              <dd class="mt-1 break-all">
                <time :datetime="evidence.record.requested_at">{{
                  evidence.record.requested_at
                }}</time>
              </dd>
            </div>
          </template>
          <template v-else>
            <div>
              <dt class="hud-label">Event</dt>
              <dd class="mt-1">{{ label(evidence.record.event_kind) }}</dd>
            </div>
            <div>
              <dt class="hud-label">Recorded</dt>
              <dd class="mt-1 break-all">
                <time :datetime="evidence.record.recorded_at">{{
                  evidence.record.recorded_at
                }}</time>
              </dd>
            </div>
          </template>
        </dl>
        <p class="text-xs text-base-content/70">
          This is recorded transport evidence. A transport action alone does not establish
          spacecraft execution.
        </p>
      </template>
    </template>
  </section>
</template>
