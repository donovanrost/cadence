<script setup lang="ts">
import type { State } from "./states";
defineProps<{ items: State[]; navigate: (href: string, event?: MouseEvent) => void }>();
</script>
<template>
  <ul class="divide-y divide-base-300/40">
    <li
      v-for="s in items"
      :key="s.id"
      class="grid gap-3 py-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto]"
      :data-limit-event="s.id"
    >
      <div class="min-w-0 space-y-1">
        <p class="font-mono text-sm [overflow-wrap:anywhere]">
          {{ s.point_name || s.point_id }}
        </p>
        <p class="text-xs text-base-content/60 [overflow-wrap:anywhere]">
          {{ s.spacecraft_id || "Mission" }} · {{ s.point_id }} · {{ s.limit_set_name }}
        </p>
        <p
          class="text-xs uppercase"
          :class="
            s.severity === 'red'
              ? 'text-error'
              : s.severity === 'yellow'
                ? 'text-warning'
                : s.severity === 'green'
                  ? 'text-success'
                  : 'text-info'
          "
        >
          {{ s.severity }} · {{ s.state.replaceAll("_", " ") }}
        </p>
      </div>
      <div class="min-w-0 space-y-1 text-xs">
        <p class="font-mono [overflow-wrap:anywhere]">Value {{ s.value }}</p>
        <p>Generated: {{ s.generation_time || "Unavailable" }}</p>
        <p>Received: {{ s.receipt_time }}</p>
        <p class="[overflow-wrap:anywhere]">
          Produced by {{ s.definition_id }} · v{{ s.definition_version }}
        </p>
      </div>
      <div class="flex flex-wrap items-start gap-3 text-xs lg:flex-col">
        <a :href="s.definition_href" class="link" @click="navigate(s.definition_href, $event)"
          >Inspect producing v{{ s.definition_version }}</a
        ><a :href="s.evidence_href" class="link" @click="navigate(s.evidence_href, $event)"
          >Open exact sample</a
        >
      </div>
    </li>
  </ul>
</template>
