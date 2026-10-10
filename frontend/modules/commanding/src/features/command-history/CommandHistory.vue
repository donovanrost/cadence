<script setup lang="ts">
import { ref, watch } from "vue";
import type { OpsPageContext, OpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import MatchedEvidence from "./MatchedEvidence.vue";
import { commandHistoryHref } from "./query";
import type { HistoryModel, HistoryQuery } from "./types";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  model: HistoryModel;
  context: OpsPageContext;
  port: OpsPageNavigationPort;
  refresh: () => Promise<void>;
}>();
const pending = ref(false);
watch(
  () => [props.model, props.port],
  () => {
    pending.value = false;
  },
);
const label = (v: string | null) => v?.replaceAll("_", " ") ?? "Not recorded";
const href = (query: HistoryQuery) =>
  commandHistoryHref(props.model.mission_id, props.model.request.id, query);
function follow(event: MouseEvent, destination: string) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  if (pending.value) return;
  pending.value = true;
  props.port.navigate(destination);
}
function selectRelease(id: string): HistoryQuery {
  return { release: id, release_after: "", verifier_after: "", verifier: "" };
}
function selectVerifier(id: string, release: string): HistoryQuery {
  return { ...selectRelease(release), verifier: id };
}
useOpsHeader("/missions/:mission_id/ops/commands/requests/:command_request_id/history", () => ({
  title: props.model.request.name,
  description: "Release attempts, verifiers and their recorded evidence.",
  refresh: { run: refreshPage, pending: pending.value },
}));
async function refreshPage() {
  if (pending.value) return;
  pending.value = true;
  try {
    await props.refresh();
  } catch {
    /* The host contains refresh failure. */
  } finally {
    pending.value = false;
  }
}
</script>
<template>
  <CadenceOpsViewport id="command-history">
    <CadenceOpsListBodyFrame>
      <div class="flex flex-wrap items-center justify-between gap-3 text-xs text-base-content/75">
        <p>
          Observed <time :datetime="model.observed_at">{{ model.observed_at }}</time
          >. Refresh reads current states. New records may appear between pages.
        </p>
      </div>
      <dl
        id="command-history-request"
        class="grid gap-4 border border-base-300 bg-base-200/20 p-4 text-xs sm:grid-cols-2 lg:grid-cols-3"
      >
        <div>
          <dt class="hud-label">Request</dt>
          <dd class="mt-1 break-all font-mono">{{ model.request.id }}</dd>
        </div>
        <div>
          <dt class="hud-label">Command</dt>
          <dd class="mt-1 break-all">
            {{ model.request.name }}<br /><span class="font-mono">{{
              model.request.command_id
            }}</span>
          </dd>
        </div>
        <div>
          <dt class="hud-label">Target</dt>
          <dd class="mt-1 break-all font-mono">
            {{ model.request.target_name || "Unnamed target" }}
          </dd>
        </div>
        <div>
          <dt class="hud-label">Model revision</dt>
          <dd class="mt-1 break-all font-mono">{{ model.request.model_revision_id }}</dd>
        </div>
        <div>
          <dt class="hud-label">Request state</dt>
          <dd class="mt-1">{{ label(model.request.state) }}</dd>
        </div>
        <div>
          <dt class="hud-label">Request verification</dt>
          <dd class="mt-1">{{ label(model.request.verification_state) }}</dd>
        </div>
      </dl>
      <section
        v-if="model.selection.release"
        id="command-history-release-selection"
        class="space-y-3 border-l-2 border-info bg-info/10 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="font-semibold">Selected release attempt</h2>
          <a
            id="command-history-clear-release"
            :href="href(selectRelease(''))"
            class="btn btn-ghost btn-xs"
            @click="follow($event, href(selectRelease('')))"
            >All releases and verifiers</a
          >
        </div>
        <p
          v-if="model.selection.release.state === 'release_uncertain'"
          id="command-history-selected-uncertain"
          role="status"
          class="text-warning"
        >
          Transmission outcome uncertain. This attempt may have been transmitted; no successful
          release completion is recorded.
        </p>
        <p class="break-all font-mono text-xs" :data-selected-release="model.selection.release.id">
          {{ model.selection.release.id }} · {{ label(model.selection.release.state) }}
        </p>
        <p class="text-xs">
          Verification {{ label(model.selection.release.verification_state) }} · Encoded size
          {{
            model.selection.release.encoded_size_bytes === null
              ? "Not recorded"
              : `${model.selection.release.encoded_size_bytes} bytes`
          }}
        </p>
        <dl class="grid gap-3 text-xs sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt class="hud-label">Queue</dt>
            <dd class="mt-1 break-all font-mono">{{ model.selection.release.queue_entry_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Contact</dt>
            <dd class="mt-1 break-all font-mono">{{ model.selection.release.contact_id }}</dd>
          </div>
          <div>
            <dt class="hud-label">Path</dt>
            <dd class="mt-1 break-all font-mono">
              {{ model.selection.release.path_id ?? "Not recorded" }}
            </dd>
          </div>
          <div>
            <dt class="hud-label">Transport binding</dt>
            <dd class="mt-1 break-all font-mono">
              {{ model.selection.release.binding_id ?? "Not recorded" }}
            </dd>
          </div>
          <div>
            <dt class="hud-label">Attempted</dt>
            <dd class="mt-1 break-all">
              <time
                v-if="model.selection.release.attempted_at"
                :datetime="model.selection.release.attempted_at"
                >{{ model.selection.release.attempted_at }}</time
              ><span v-else>Not recorded</span>
            </dd>
          </div>
          <div>
            <dt class="hud-label">Released</dt>
            <dd class="mt-1 break-all">
              <time
                v-if="model.selection.release.released_at"
                :datetime="model.selection.release.released_at"
                >{{ model.selection.release.released_at }}</time
              ><span v-else>Not recorded</span>
            </dd>
          </div>
        </dl>
      </section>
      <section
        v-if="model.selection.verifier"
        id="command-history-verifier-selection"
        class="space-y-3 border-l-2 border-info bg-info/10 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="font-semibold">Selected verifier · {{ model.selection.verifier.name }}</h2>
          <a
            id="command-history-clear-verifier"
            :href="href({ ...model.query, verifier: '' })"
            class="btn btn-ghost btn-xs"
            @click="follow($event, href({ ...model.query, verifier: '' }))"
            >Clear verifier</a
          >
        </div>
        <p
          class="break-all font-mono text-xs"
          :data-selected-verifier="model.selection.verifier.id"
        >
          {{ model.selection.verifier.id }} · {{ label(model.selection.verifier.state) }}
        </p>
        <p class="text-xs">
          {{ label(model.selection.verifier.phase) }} · Severity
          {{ label(model.selection.verifier.severity) }}
        </p>
        <p v-if="model.selection.verifier.failure_code" class="text-xs text-warning">
          {{ label(model.selection.verifier.failure_code) }}
        </p>
        <dl class="grid gap-3 text-xs sm:grid-cols-2">
          <div>
            <dt class="hud-label">Matched</dt>
            <dd class="mt-1 break-all">
              <time
                v-if="model.selection.verifier.matched_at"
                :datetime="model.selection.verifier.matched_at"
                >{{ model.selection.verifier.matched_at }}</time
              ><span v-else>Not recorded</span>
            </dd>
          </div>
          <div>
            <dt class="hud-label">Deadline</dt>
            <dd class="mt-1 break-all">
              <time
                v-if="model.selection.verifier.timeout_at"
                :datetime="model.selection.verifier.timeout_at"
                >{{ model.selection.verifier.timeout_at }}</time
              ><span v-else>Not recorded</span>
            </dd>
          </div>
        </dl>
      </section>
      <MatchedEvidence :evidence="model.evidence" />
      <div class="grid gap-6 xl:grid-cols-2">
        <section id="command-history-releases" class="min-w-0 space-y-3">
          <h2 class="font-semibold">Release attempts</h2>
          <p class="text-xs text-base-content/70">Ordered by attempt time and identity.</p>
          <p
            v-if="model.releases.entries.length === 0"
            id="command-history-releases-empty"
            role="status"
            class="border border-base-300 p-4 text-sm"
          >
            No release attempts on this page.
          </p>
          <article
            v-for="release in model.releases.entries"
            :key="release.id"
            :data-history-release="release.id"
            class="space-y-2 border border-base-300 p-4 text-xs"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="break-all font-mono">{{ release.id }}</p>
              <span
                :class="
                  release.state === 'release_failed'
                    ? 'text-error'
                    : release.state === 'release_uncertain'
                      ? 'text-warning'
                      : 'text-info'
                "
                >{{ label(release.state) }}</span
              >
            </div>
            <p
              v-if="release.state === 'release_uncertain'"
              data-history-release-uncertain
              role="status"
              class="text-warning"
            >
              Transmission outcome uncertain. This attempt may have been transmitted; no successful
              release completion is recorded.
            </p>
            <p class="break-all font-mono">Contact {{ release.contact_id }}</p>
            <p>
              Attempted
              <time v-if="release.attempted_at" :datetime="release.attempted_at">{{
                release.attempted_at
              }}</time
              ><span v-else>Not recorded</span>
            </p>
            <a
              :data-history-select-release="release.id"
              :href="href(selectRelease(release.id))"
              class="btn btn-ghost btn-xs"
              :aria-disabled="pending"
              @click="follow($event, href(selectRelease(release.id)))"
              >Open release and verifiers</a
            >
          </article>
          <nav aria-label="Release history pages" class="flex justify-between gap-3">
            <a
              v-if="model.query.release_after"
              id="command-history-releases-first"
              :href="href({ ...model.query, release_after: '' })"
              class="btn btn-ghost btn-sm"
              @click="follow($event, href({ ...model.query, release_after: '' }))"
              >First page</a
            >
            <a
              v-if="model.releases.next_after"
              id="command-history-releases-next"
              :href="href({ ...model.query, release_after: model.releases.next_after })"
              class="btn btn-ghost btn-sm"
              @click="
                follow($event, href({ ...model.query, release_after: model.releases.next_after }))
              "
              >Next releases</a
            >
          </nav>
        </section>
        <section id="command-history-verifiers" class="min-w-0 space-y-3">
          <h2 class="font-semibold">
            {{ model.query.release ? "Verifiers for selected release" : "All request verifiers" }}
          </h2>
          <p class="text-xs text-base-content/70">Ordered by creation time and identity.</p>
          <p
            v-if="model.verifiers.entries.length === 0"
            id="command-history-verifiers-empty"
            role="status"
            class="border border-base-300 p-4 text-sm"
          >
            No verifiers on this page.
          </p>
          <article
            v-for="verifier in model.verifiers.entries"
            :key="verifier.id"
            :data-history-verifier="verifier.id"
            class="space-y-2 border border-base-300 p-4 text-xs"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="font-semibold">{{ verifier.name }}</p>
              <span
                :class="
                  ['failed', 'timed_out'].includes(verifier.state) ? 'text-error' : 'text-info'
                "
                >{{ label(verifier.state) }}</span
              >
            </div>
            <p class="break-all font-mono">
              {{ verifier.id }}<br />Release {{ verifier.release_attempt_id }}
            </p>
            <p>{{ label(verifier.phase) }} · {{ label(verifier.severity) }}</p>
            <a
              :data-history-select-verifier="verifier.id"
              :href="href(selectVerifier(verifier.id, verifier.release_attempt_id))"
              class="btn btn-ghost btn-xs"
              :aria-disabled="pending"
              @click="
                follow($event, href(selectVerifier(verifier.id, verifier.release_attempt_id)))
              "
              >Inspect verifier and evidence</a
            >
          </article>
          <nav aria-label="Verifier history pages" class="flex justify-between gap-3">
            <a
              v-if="model.query.verifier_after"
              id="command-history-verifiers-first"
              :href="href({ ...model.query, verifier_after: '' })"
              class="btn btn-ghost btn-sm"
              @click="follow($event, href({ ...model.query, verifier_after: '' }))"
              >First page</a
            >
            <a
              v-if="model.verifiers.next_after"
              id="command-history-verifiers-next"
              :href="href({ ...model.query, verifier_after: model.verifiers.next_after })"
              class="btn btn-ghost btn-sm"
              @click="
                follow($event, href({ ...model.query, verifier_after: model.verifiers.next_after }))
              "
              >Next verifiers</a
            >
          </nav>
        </section>
      </div>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
