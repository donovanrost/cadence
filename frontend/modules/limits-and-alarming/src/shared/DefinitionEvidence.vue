<script setup lang="ts">
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import { envelope, type Selection } from "./contracts";
defineProps<{ selection: Selection; navigate: (href: string, event?: MouseEvent) => void }>();
</script>
<template>
  <CadenceCard v-if="selection" body-class="space-y-4 p-5 min-w-0">
    <h2 class="font-semibold">Definition evidence</h2>
    <p
      v-if="!selection.available"
      id="limits-version-unavailable"
      role="alert"
      class="text-sm text-warning"
    >
      The selected definition or immutable version is unavailable. A newer version has not been
      substituted.
    </p>
    <template v-else>
      <div id="limits-inspected" class="space-y-2 border-l-2 border-info pl-3 text-sm">
        <p class="font-mono [overflow-wrap:anywhere]">
          {{ selection.inspected.point_id }} · {{ selection.inspected.limit_set_name }}
        </p>
        <p>
          Inspecting v{{ selection.inspected.version }} · Newest saved v{{
            selection.current.version
          }}
        </p>
        <p class="font-mono text-xs [overflow-wrap:anywhere]">
          {{ envelope(selection.inspected.thresholds) }}
        </p>
      </div>
      <div id="limits-active-evidence" class="text-sm">
        <p v-if="selection.active">
          {{ selection.active.active_to ? "Ended activation" : "Active definition" }}:
          {{ selection.active.definition_id }} · v{{ selection.active.version }}
        </p>
        <p v-else>No activation is recorded for this point and set.</p>
        <p
          v-if="selection.active"
          class="mt-1 font-mono text-xs text-base-content/60 [overflow-wrap:anywhere]"
        >
          {{ selection.active.event_id }} · From {{ selection.active.active_from
          }}<template v-if="selection.active.active_to">
            · To {{ selection.active.active_to }}</template
          >
        </p>
      </div>
      <details open>
        <summary class="cursor-pointer text-sm font-semibold">
          Immutable versions · {{ selection.history.total_count }}
        </summary>
        <ul class="mt-2 divide-y divide-base-300/40 text-sm">
          <li v-for="d in selection.history.items" :key="d.version" class="py-2">
            <a :href="d.href" class="link font-mono" @click="navigate(d.href, $event)"
              >Version {{ d.version }}</a
            >
            <p class="mt-1 text-xs [overflow-wrap:anywhere]">{{ envelope(d.thresholds) }}</p>
          </li>
        </ul>
        <nav aria-label="Limit version pages" class="flex justify-between gap-2 text-xs">
          <a
            v-if="selection.history.previous_href"
            :href="selection.history.previous_href"
            class="link"
            @click="navigate(selection.history.previous_href, $event)"
            >Previous versions</a
          ><span>Page {{ selection.history.page }}</span
          ><a
            v-if="selection.history.next_href"
            :href="selection.history.next_href"
            class="link"
            @click="navigate(selection.history.next_href, $event)"
            >Next versions</a
          >
        </nav>
      </details>
      <details>
        <summary class="cursor-pointer text-sm font-semibold">
          Activation history · {{ selection.activations.total_count }}
        </summary>
        <ul class="mt-2 divide-y divide-base-300/40 text-sm">
          <li v-for="a in selection.activations.items" :key="a.id" class="space-y-1 py-2">
            <p>{{ a.event_type }} · {{ a.definition_id }} · v{{ a.version }}</p>
            <p class="font-mono text-xs text-base-content/65 [overflow-wrap:anywhere]">
              {{ a.observed_at }} · {{ a.scope_type || "Default scope" }} {{ a.scope_ref }} ·
              {{ a.realm || "Default realm" }}
            </p>
            <p class="font-mono text-xs [overflow-wrap:anywhere]">{{ a.id }}</p>
          </li>
        </ul>
        <nav aria-label="Limit activation pages" class="flex justify-between gap-2 text-xs">
          <a
            v-if="selection.activations.previous_href"
            :href="selection.activations.previous_href"
            class="link"
            @click="navigate(selection.activations.previous_href, $event)"
            >Previous activations</a
          ><span>Page {{ selection.activations.page }}</span
          ><a
            v-if="selection.activations.next_href"
            :href="selection.activations.next_href"
            class="link"
            @click="navigate(selection.activations.next_href, $event)"
            >Next activations</a
          >
        </nav>
      </details>
    </template>
  </CadenceCard>
</template>
