<script setup lang="ts">
import { ref } from "vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import DefinitionEvidence from "../../shared/DefinitionEvidence.vue";
import { fields, envelope } from "../../shared/contracts";
import type { DefinitionsDocument, DefinitionsPort } from "./contracts";
import { useDefinitions } from "./state";
const props = defineProps<{ initial: DefinitionsDocument; port: DefinitionsPort }>();
const state = useDefinitions(() => props.initial, props.port);
const {
  page,
  identity,
  draft,
  pending,
  confirmed,
  working,
  reading,
  readFailed,
  storageError,
  notice,
  locked,
  stale,
  canSave,
} = state;
const search = ref(page.value.query.q as string),
  pointSearch = ref(page.value.query.points_q as string);
useManagementHeader("/missions/:mission_id/applications/:application_key/:surface_id", {
  title: "Limit definitions",
  description: "Governed thresholds and activation evidence.",
});
</script>
<template>
  <div id="limits-definitions-page" class="space-y-5">
    <div class="flex flex-wrap items-center justify-between gap-3 text-sm">
      <div class="flex gap-4">
        <a
          :href="page.links.applications"
          class="link"
          @click="state.navigate(page.links.applications, $event)"
          >Mission applications</a
        ><a
          :href="page.links.activity"
          class="link"
          @click="state.navigate(page.links.activity, $event)"
          >Current posture</a
        >
      </div>
      <button
        id="refresh-limits"
        class="btn btn-ghost btn-sm"
        :disabled="working || reading"
        @click="state.refresh"
      >
        {{ reading ? "Refreshing…" : "Refresh evidence" }}
      </button>
    </div>
    <p v-if="notice" id="limits-notice" role="status" class="border border-info/30 p-3 text-sm">
      {{ notice }}
    </p>
    <p
      v-if="storageError"
      id="limits-storage-error"
      role="alert"
      class="border border-warning/40 p-3 text-sm"
    >
      {{ storageError }}
    </p>
    <div
      v-if="pending"
      id="limits-pending"
      role="alert"
      class="space-y-3 border border-warning/40 p-4 text-sm"
    >
      <p>
        This save is awaiting confirmation. Recover its response before editing or submitting again.
      </p>
      <button
        id="recover-limits-save"
        class="btn btn-sm"
        :disabled="working || reading"
        @click="state.recover"
      >
        Recover save response
      </button>
    </div>
    <p v-if="readFailed" role="alert" class="text-sm text-warning">
      Current evidence is unavailable. Refresh before saving.
    </p>
    <div class="grid items-start gap-5 xl:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)]">
      <div class="min-w-0 space-y-5">
        <CadenceCard body-class="space-y-4 p-5 min-w-0">
          <div class="flex flex-wrap justify-between gap-2">
            <h2 class="font-semibold">Definition directory</h2>
            <span class="font-mono text-xs">{{ page.definitions.total_count }} definitions</span>
          </div>
          <form class="flex items-end gap-2" @submit.prevent="state.search('q', search)">
            <CadenceField label="Find a definition" wrapper-class="min-w-0 flex-1"
              ><input
                id="limits-search"
                v-model="search"
                type="search"
                maxlength="240"
                class="input input-bordered w-full"
                :disabled="locked" /></CadenceField
            ><button class="btn btn-sm" :disabled="locked">Find</button>
          </form>
          <p
            v-if="!page.definitions.items.length"
            id="limits-empty"
            class="text-sm text-base-content/60"
          >
            No definitions match this view.
          </p>
          <ul class="divide-y divide-base-300/40">
            <li v-for="d in page.definitions.items" :key="d.id" class="space-y-1 py-3">
              <a
                :href="d.href"
                class="link font-mono text-sm [overflow-wrap:anywhere]"
                @click="state.navigate(d.href, $event)"
                >{{ d.point_id }}</a
              >
              <p class="text-sm">{{ d.limit_set_name }} · v{{ d.version }}</p>
              <p class="font-mono text-xs text-base-content/60 [overflow-wrap:anywhere]">
                {{ envelope(d.thresholds) }}
              </p>
            </li>
          </ul>
          <nav aria-label="Limit definition pages" class="flex justify-between gap-2 text-xs">
            <a
              v-if="page.definitions.previous_href"
              :href="page.definitions.previous_href"
              class="link"
              @click="state.navigate(page.definitions.previous_href, $event)"
              >Previous definitions</a
            ><span>Page {{ page.definitions.page }}</span
            ><a
              v-if="page.definitions.next_href"
              :href="page.definitions.next_href"
              class="link"
              @click="state.navigate(page.definitions.next_href, $event)"
              >Next definitions</a
            >
          </nav>
        </CadenceCard>
        <CadenceCard body-class="space-y-4 p-5 min-w-0">
          <h2 class="font-semibold">Choose a point and limit set</h2>
          <form
            id="limits-identity-form"
            class="space-y-3"
            @submit.prevent="state.choose(identity.point, identity.set)"
          >
            <CadenceField label="Canonical point ID"
              ><input
                id="limits-point"
                v-model="identity.point"
                required
                maxlength="240"
                class="input input-bordered w-full font-mono"
                :disabled="locked" /></CadenceField
            ><CadenceField label="Limit set"
              ><input
                id="limits-set"
                v-model="identity.set"
                required
                maxlength="240"
                class="input input-bordered w-full"
                :disabled="locked" /></CadenceField
            ><button
              id="review-limits-identity"
              class="btn btn-sm"
              :disabled="locked || !identity.point.trim() || !identity.set.trim()"
            >
              Review current definition
            </button>
          </form>
          <form
            class="flex items-end gap-2"
            @submit.prevent="state.search('points_q', pointSearch)"
          >
            <CadenceField label="Find telemetry or derived points" wrapper-class="min-w-0 flex-1"
              ><input
                id="limits-point-search"
                v-model="pointSearch"
                type="search"
                maxlength="240"
                class="input input-bordered w-full"
                :disabled="locked" /></CadenceField
            ><button class="btn btn-sm" :disabled="locked">Find</button>
          </form>
          <p class="text-xs text-base-content/60">
            {{ page.points.total_count }} matching points from active telemetry and governed derived
            definitions.
          </p>
          <ul class="divide-y divide-base-300/40">
            <li v-for="p in page.points.items" :key="p.id" class="py-2">
              <button
                class="link text-left font-mono text-xs [overflow-wrap:anywhere]"
                :disabled="locked"
                @click="identity.point = p.id"
              >
                {{ p.id }}
              </button>
              <p class="text-xs text-base-content/60">{{ p.kind }} · {{ p.label }}</p>
            </li>
          </ul>
          <nav aria-label="Limit point pages" class="flex justify-between gap-2 text-xs">
            <a
              v-if="page.points.previous_href"
              :href="page.points.previous_href"
              class="link"
              @click="state.navigate(page.points.previous_href, $event)"
              >Previous points</a
            ><span>Page {{ page.points.page }}</span
            ><a
              v-if="page.points.next_href"
              :href="page.points.next_href"
              class="link"
              @click="state.navigate(page.points.next_href, $event)"
              >Next points</a
            >
          </nav>
        </CadenceCard>
      </div>
      <div class="min-w-0 space-y-5">
        <CadenceCard body-class="space-y-4 p-5 min-w-0">
          <h2 class="font-semibold">Review and edit thresholds</h2>
          <p class="text-sm text-base-content/65">
            Saving creates and activates a new immutable version. Existing evaluated states may
            still refer to an older version until telemetry is evaluated again.
          </p>
          <div
            v-if="page.editor"
            id="limits-reviewed"
            class="space-y-2 border border-base-300/50 p-3 text-sm"
          >
            <p class="font-mono [overflow-wrap:anywhere]">
              {{ page.editor.point_id }} · {{ page.editor.limit_set_name }}
            </p>
            <p>
              Newest saved:
              {{ page.editor.current ? `v${page.editor.current.version}` : "No definition" }} ·
              Active:
              {{
                page.editor.active && !page.editor.active.active_to
                  ? `v${page.editor.active.version}`
                  : "None"
              }}
            </p>
            <p class="font-mono text-xs [overflow-wrap:anywhere]">
              Activation evidence:
              {{ page.editor.review.activation_event_id || "No prior activation" }}
            </p>
            <button
              id="edit-reviewed-limits"
              class="btn btn-sm"
              :disabled="locked || readFailed"
              @click="state.adopt()"
            >
              {{
                page.editor.current ? "Edit reviewed version" : "Start reviewed definition"
              }}</button
            ><button
              v-if="page.selection?.available"
              id="reuse-limit-thresholds"
              class="btn btn-ghost btn-sm"
              :disabled="locked || readFailed"
              @click="state.adopt(page.selection.inspected.thresholds)"
            >
              Reuse inspected v{{ page.selection.inspected.version }} thresholds
            </button>
          </div>
          <p v-else class="text-sm text-base-content/60">
            Choose a point and set, or open an existing definition, to review its current evidence.
          </p>
          <p
            v-if="draft.point_id && stale"
            id="limits-stale"
            role="alert"
            class="text-sm text-warning"
          >
            This draft does not match the current review. Your thresholds are retained. Review the
            current definition before saving.
          </p>
          <form id="limits-definition-form" class="space-y-4" @submit.prevent="state.save">
            <p class="font-mono text-xs [overflow-wrap:anywhere]">
              Draft: {{ draft.point_id || "No point selected" }} · {{ draft.limit_set_name }}
            </p>
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <CadenceField v-for="field in fields" :key="field" :label="field.replaceAll('_', ' ')"
                ><input
                  :id="`limits-${field}`"
                  v-model="draft[field]"
                  inputmode="decimal"
                  maxlength="80"
                  placeholder="Not configured"
                  class="input input-bordered w-full font-mono"
                  :disabled="locked || !draft.point_id"
              /></CadenceField>
            </div>
            <p class="text-xs text-base-content/60">
              Configure at least one threshold. Values must increase from red low to yellow low,
              yellow high, then red high. Blank thresholds are omitted.
            </p>
            <button id="save-limit-definition" class="btn btn-primary btn-sm" :disabled="!canSave">
              {{ working ? "Saving…" : "Save and activate" }}
            </button>
          </form>
          <div
            v-if="confirmed"
            id="limits-confirmed"
            role="status"
            class="space-y-1 border border-success/40 p-3 text-sm"
          >
            <p>
              Confirmed: {{ confirmed.result.pointId }} · {{ confirmed.result.limitSetName }} · v{{
                confirmed.result.version
              }}
              saved and activated.
            </p>
            <p class="font-mono text-xs [overflow-wrap:anywhere]">
              {{ confirmed.receiptId }} · {{ confirmed.completedAt }}
            </p>
            <p class="text-xs">
              This receipt records that save. Current activation evidence is shown separately above.
            </p>
          </div>
        </CadenceCard>
        <DefinitionEvidence :selection="page.selection" :navigate="state.navigate" />
      </div>
    </div>
  </div>
</template>
