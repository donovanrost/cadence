<script setup lang="ts">
import { ref } from "vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import type { DefinitionsDocument, DefinitionsPort } from "./contracts";
import { useDefinitions } from "./state";
const props = defineProps<{ initial: DefinitionsDocument; port: DefinitionsPort }>();
const state = useDefinitions(() => props.initial, props.port);
const {
  page,
  draft,
  current,
  pending,
  confirmed,
  working,
  reading,
  readFailed,
  storageError,
  notice,
  dirty,
  stale,
  locked,
  canSave,
} = state;
const search = ref(page.value.query.q),
  valuesSearch = ref(page.value.query.values_q),
  spacecraft = ref(page.value.query.spacecraft),
  spacecraftSearch = ref(page.value.query.spacecraft_q);
useManagementHeader("/missions/:mission_id/applications/:application_key/:surface_id", {
  title: "Derived telemetry",
  description: "Definitions and latest values.",
});
</script>
<template>
  <div id="derived-definitions-page" class="space-y-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <a
        :href="page.links.applications"
        class="link text-sm"
        @click="state.navigate(page.links.applications, $event)"
        >Mission applications</a
      ><button
        id="refresh-derived"
        class="btn btn-ghost btn-sm"
        :disabled="working || reading"
        @click="state.refresh"
      >
        {{ reading ? "Refreshing…" : "Refresh evidence" }}
      </button>
    </div>
    <p v-if="notice" id="derived-notice" role="status" class="border border-info/30 p-3 text-sm">
      {{ notice }}
    </p>
    <p
      v-if="storageError"
      id="derived-storage-error"
      role="alert"
      class="border border-warning/40 p-3 text-sm text-warning"
    >
      {{ storageError }}
    </p>
    <div
      v-if="pending"
      id="derived-pending"
      role="alert"
      class="space-y-3 border border-warning/40 p-4"
    >
      <p class="text-sm">
        This save is awaiting confirmation. Recover its response before editing or submitting again.
      </p>
      <button
        id="recover-derived-save"
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
    <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <CadenceCard body-class="space-y-4 p-5 min-w-0">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="font-semibold">Definition directory</h2>
          <span class="font-mono text-xs">{{ page.definitions.total_count }} definitions</span>
        </div>
        <form class="flex items-end gap-2" @submit.prevent="state.search('q', search)">
          <CadenceField label="Find a definition" wrapper-class="min-w-0 flex-1"
            ><input
              id="derived-search"
              v-model="search"
              type="search"
              maxlength="240"
              class="input input-bordered w-full"
              :disabled="!!pending || working" /></CadenceField
          ><button class="btn btn-sm" :disabled="!!pending || working">Find</button>
        </form>
        <p
          v-if="!page.definitions.items.length"
          id="derived-empty"
          class="text-sm text-base-content/60"
        >
          No definitions match this view. Create a derived point to begin.
        </p>
        <ul class="divide-y divide-base-300/40">
          <li
            v-for="d in page.definitions.items"
            :key="d.id"
            class="space-y-2 py-3"
            :data-definition-id="d.id"
          >
            <a
              :href="d.href"
              class="link font-mono text-sm [overflow-wrap:anywhere]"
              @click="state.navigate(d.href, $event)"
              >{{ d.point_id }}</a
            >
            <p class="text-sm">
              {{ d.point_name }} · v{{ d.version }} · {{ d.source_count }} sources
            </p>
            <p class="font-mono text-xs text-base-content/60 [overflow-wrap:anywhere]">
              {{ d.expression_preview }}
            </p>
          </li>
        </ul>
        <nav aria-label="Definition pages" class="flex flex-wrap justify-between gap-2 text-xs">
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
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="font-semibold">
            {{ draft.expected_definition_id ? "Edit definition" : "New derived point" }}
          </h2>
          <button
            id="new-derived-definition"
            class="btn btn-ghost btn-sm"
            :disabled="locked"
            @click="state.replace(null)"
          >
            New definition
          </button>
        </div>
        <p class="text-sm text-base-content/65">
          Use canonical point IDs in a stateless expression, such as HK.voltage * HK.current. Saving
          appends an immutable version; it does not start evaluation.
        </p>
        <div
          v-if="stale"
          id="derived-stale"
          role="alert"
          class="space-y-2 border border-warning/40 p-3 text-sm"
        >
          <p>
            This point has a newer saved version. Your draft is retained. Open the current
            definition and review it before saving.
          </p>
          <button
            v-if="current?.point_id === draft.point_id"
            id="review-derived-current"
            class="btn btn-sm"
            :disabled="locked"
            @click="state.replace(current)"
          >
            Review current version
          </button>
        </div>
        <form id="derived-definition-form" class="space-y-4" @submit.prevent="state.save">
          <fieldset :disabled="locked || stale" class="space-y-4">
            <CadenceField label="Point ID"
              ><input
                id="derived-point-id"
                v-model="draft.point_id"
                maxlength="240"
                class="input input-bordered w-full font-mono"
                :readonly="!!draft.expected_definition_id"
                required
                placeholder="DERIVED.bus_power"
            /></CadenceField>
            <CadenceField label="Display name"
              ><input
                id="derived-point-name"
                v-model="draft.point_name"
                maxlength="240"
                class="input input-bordered w-full"
                placeholder="Bus power"
            /></CadenceField>
            <CadenceField label="Expression">
              <textarea
                id="derived-expression"
                v-model="draft.expression"
                maxlength="8192"
                rows="5"
                class="textarea textarea-bordered w-full font-mono"
                required
                placeholder="HK.voltage * HK.current"
              ></textarea>
            </CadenceField>
          </fieldset>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p class="text-xs text-base-content/60">
              {{
                draft.expected_definition_id
                  ? `Based on version ${draft.expected_version}`
                  : "Creates version 1"
              }}
              · {{ dirty ? "Unsaved draft" : "Draft ready" }}
            </p>
            <button
              id="save-derived-definition"
              type="submit"
              class="btn btn-primary btn-sm"
              :disabled="!canSave"
            >
              {{ working ? "Saving…" : "Save definition" }}
            </button>
          </div>
        </form>
        <p v-if="confirmed" id="derived-save-receipt" class="text-xs [overflow-wrap:anywhere]">
          Saved v{{ confirmed.result.version }} · {{ confirmed.receiptId }} ·
          {{ confirmed.completedAt }}
        </p>
      </CadenceCard>
    </div>
    <CadenceCard v-if="page.selection" body-class="space-y-4 p-5 min-w-0">
      <p
        v-if="!page.selection.available"
        id="derived-selection-unavailable"
        role="alert"
        class="text-sm text-warning"
      >
        The requested definition version is unavailable in this mission.
      </p>
      <template v-else>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="font-mono [overflow-wrap:anywhere]">
              {{ page.selection.inspected.point_id }} · v{{ page.selection.inspected.version }}
            </h2>
            <p class="mt-1 text-xs text-base-content/60">
              Current version: {{ page.selection.current.version }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              id="edit-derived-current"
              class="btn btn-sm"
              :disabled="locked"
              @click="state.replace(page.selection.current)"
            >
              Edit current version</button
            ><button
              v-if="page.selection.inspected.version !== page.selection.current.version"
              id="restore-derived-expression"
              class="btn btn-ghost btn-sm"
              :disabled="locked"
              @click="state.replace(page.selection.current, page.selection.inspected.expression)"
            >
              Use this expression in a new version
            </button>
          </div>
        </div>
        <pre
          id="derived-inspected-expression"
          class="whitespace-pre-wrap border border-base-300/40 p-3 font-mono text-sm [overflow-wrap:anywhere]"
          >{{ page.selection.inspected.expression }}</pre>
        <h3 class="hud-label">Source points · {{ page.selection.inspected.source_count }}</h3>
        <ul class="space-y-1">
          <li
            v-for="source in page.selection.sources.items"
            :key="source"
            class="font-mono text-xs [overflow-wrap:anywhere]"
          >
            {{ source }}
          </li>
        </ul>
        <nav aria-label="Source pages" class="flex flex-wrap justify-between gap-2 text-xs">
          <a
            v-if="page.selection.sources.previous_href"
            :href="page.selection.sources.previous_href"
            class="link"
            @click="state.navigate(page.selection.sources.previous_href, $event)"
            >Previous sources</a
          ><span>Page {{ page.selection.sources.page }}</span
          ><a
            v-if="page.selection.sources.next_href"
            :href="page.selection.sources.next_href"
            class="link"
            @click="state.navigate(page.selection.sources.next_href, $event)"
            >Next sources</a
          >
        </nav>
        <h3 class="hud-label">
          Immutable history · {{ page.selection.history.total_count }} versions
        </h3>
        <ol id="derived-history" class="divide-y divide-base-300/40">
          <li v-for="version in page.selection.history.items" :key="version.version" class="py-2">
            <a
              :href="version.href"
              class="link text-sm"
              @click="state.navigate(version.href, $event)"
              >Version {{ version.version }}</a
            >
            <p class="mt-1 font-mono text-xs text-base-content/60 [overflow-wrap:anywhere]">
              {{ version.expression_preview }}
            </p>
          </li>
        </ol>
        <nav aria-label="History pages" class="flex flex-wrap justify-between gap-2 text-xs">
          <a
            v-if="page.selection.history.previous_href"
            :href="page.selection.history.previous_href"
            class="link"
            @click="state.navigate(page.selection.history.previous_href, $event)"
            >Previous versions</a
          ><span>Page {{ page.selection.history.page }}</span
          ><a
            v-if="page.selection.history.next_href"
            :href="page.selection.history.next_href"
            class="link"
            @click="state.navigate(page.selection.history.next_href, $event)"
            >Next versions</a
          >
        </nav>
      </template>
    </CadenceCard>
    <CadenceCard body-class="space-y-4 p-5 min-w-0">
      <h2 class="font-semibold">Latest values · {{ page.values.total_count }}</h2>
      <p class="text-sm text-base-content/65">
        {{ page.spacecraft_filter }}. Each value identifies the immutable definition version that
        produced it; receipt and generation times describe its freshness.
      </p>
      <form
        class="flex flex-wrap items-end gap-2"
        @submit.prevent="state.search('values_q', valuesSearch)"
      >
        <CadenceField label="Find latest point" wrapper-class="min-w-0 flex-1"
          ><input
            id="derived-value-search"
            v-model="valuesSearch"
            maxlength="240"
            type="search"
            class="input input-bordered w-full"
            :disabled="!!pending || working" /></CadenceField
        ><button class="btn btn-sm" :disabled="!!pending || working">Find</button>
      </form>
      <form
        class="flex flex-wrap items-end gap-2"
        @submit.prevent="state.search('spacecraft_q', spacecraftSearch)"
      >
        <CadenceField label="Find spacecraft" wrapper-class="min-w-0 flex-1"
          ><input
            id="derived-spacecraft-search"
            v-model="spacecraftSearch"
            maxlength="240"
            type="search"
            class="input input-bordered w-full"
            :disabled="!!pending || working" /></CadenceField
        ><button class="btn btn-sm" :disabled="!!pending || working">Find spacecraft</button>
      </form>
      <CadenceField label="Value scope"
        ><select
          id="derived-spacecraft-filter"
          v-model="spacecraft"
          class="select select-bordered w-full"
          :disabled="!!pending || working"
          @change="state.search('spacecraft', spacecraft)"
        >
          <option value="">All spacecraft and mission values</option>
          <option value="mission">Mission values</option>
          <option
            v-if="
              page.query.spacecraft &&
              page.query.spacecraft !== 'mission' &&
              !page.spacecraft.items.some((c) => c.id === page.query.spacecraft)
            "
            :value="page.query.spacecraft"
          >
            {{ page.spacecraft_filter }} (selected)
          </option>
          <option v-for="craft in page.spacecraft.items" :key="craft.id" :value="craft.id">
            {{ craft.label }}
          </option>
        </select></CadenceField
      >
      <nav aria-label="Spacecraft pages" class="flex flex-wrap justify-between gap-2 text-xs">
        <a
          v-if="page.spacecraft.previous_href"
          :href="page.spacecraft.previous_href"
          class="link"
          @click="state.navigate(page.spacecraft.previous_href, $event)"
          >Previous spacecraft</a
        ><span>{{ page.spacecraft.total_count }} spacecraft · Page {{ page.spacecraft.page }}</span
        ><a
          v-if="page.spacecraft.next_href"
          :href="page.spacecraft.next_href"
          class="link"
          @click="state.navigate(page.spacecraft.next_href, $event)"
          >Next spacecraft</a
        >
      </nav>
      <p
        v-if="!page.values.items.length"
        id="derived-values-empty"
        class="text-sm text-base-content/60"
      >
        No latest values match this scope. Saved definitions do not imply that evaluation has
        produced data.
      </p>
      <ul id="derived-latest-values" class="divide-y divide-base-300/40">
        <li
          v-for="value in page.values.items"
          :key="value.id"
          class="space-y-2 py-4"
          :data-value-id="value.id"
        >
          <div class="flex flex-wrap justify-between gap-2">
            <strong class="font-mono text-sm [overflow-wrap:anywhere]">{{ value.point_id }}</strong
            ><span class="border border-base-300 px-2 py-1 text-xs">{{ value.quality }}</span>
          </div>
          <p class="font-mono text-lg [overflow-wrap:anywhere]">{{ value.value }}</p>
          <p class="text-xs text-base-content/65 [overflow-wrap:anywhere]">
            Scope: {{ value.spacecraft_id ?? "Mission" }} · Received {{ value.receipt_time }} ·
            Generated {{ value.generation_time ?? "Unavailable" }}
          </p>
          <a
            :href="value.definition_href"
            class="link text-xs"
            @click="state.navigate(value.definition_href, $event)"
            >Inspect producing definition v{{ value.definition_version }}</a
          >
          <p class="font-mono text-xs text-base-content/50 [overflow-wrap:anywhere]">
            Sample {{ value.id }} · Trigger {{ value.trigger_sample_id }}
          </p>
        </li>
      </ul>
      <nav aria-label="Value pages" class="flex flex-wrap justify-between gap-2 text-xs">
        <a
          v-if="page.values.previous_href"
          :href="page.values.previous_href"
          class="link"
          @click="state.navigate(page.values.previous_href, $event)"
          >Previous values</a
        ><span>Page {{ page.values.page }}</span
        ><a
          v-if="page.values.next_href"
          :href="page.values.next_href"
          class="link"
          @click="state.navigate(page.values.next_href, $event)"
          >Next values</a
        >
      </nav>
    </CadenceCard>
  </div>
</template>
