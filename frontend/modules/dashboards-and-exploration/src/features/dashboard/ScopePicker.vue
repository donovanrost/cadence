<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadencePopover from "@cadence/ui/CadencePopover.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { ScopeOption } from "./contracts";

const props = defineProps<{ options: readonly ScopeOption[]; selected: string | null }>();
const emit = defineEmits<{ select: [id: string | null] }>();
const query = ref("");
const current = computed(() => props.options.find((o) => o.id === props.selected));
const matches = computed(() => {
  const q = query.value.trim().toLowerCase();
  const found = q
    ? props.options.filter((o) => `${o.name} ${o.id}`.toLowerCase().includes(q))
    : props.options;
  return found.slice(0, 100);
});
function choose(id: string | null, close: () => void) {
  emit("select", id);
  close();
}
</script>

<template>
  <CadencePopover
    id="dashboard-scope"
    identity="dashboard-scope"
    class="cadence-overlay"
    :data-query-overrides="selected ? 'true' : 'false'"
    align="start"
  >
    <template #trigger="{ open }">
      <button
        type="button"
        class="cadence-dashboard-query-trigger inline-flex items-center"
        data-overlay-trigger
        :aria-expanded="open"
        aria-haspopup="dialog"
      >
        <CadenceIcon name="hero-rocket-launch" size="xs" />
        <span class="cadence-dashboard-query-trigger-label">Spacecraft</span>
        <span class="cadence-dashboard-query-trigger-value">{{
          current?.name ?? "Dashboard default"
        }}</span>
        <CadenceIcon name="hero-chevron-down" size="xs" />
      </button>
    </template>
    <template #content="{ open, close }">
      <div
        class="cadence-overlay-panel cadence-popover-panel"
        data-overlay-width="md"
        :hidden="!open"
        role="dialog"
        aria-label="Spacecraft scope"
      >
        <div class="cadence-dashboard-query-panel-header flex-col">
          <span class="hud-label">Spacecraft scope</span>
          <span class="text-xs text-base-content/70"
            >Widgets that follow the dashboard context show this spacecraft.</span
          >
        </div>
        <div class="cadence-dashboard-query-panel-body space-y-2">
          <CadenceTextField
            v-if="options.length > 8"
            id="dashboard-scope-search"
            v-model="query"
            label="Find spacecraft"
            placeholder="Name or ID"
          />
          <ul class="space-y-0.5">
            <li class="cadence-menu-item">
              <button
                type="button"
                :aria-pressed="selected === null"
                :class="selected === null ? 'text-primary' : ''"
                @click="choose(null, close)"
              >
                Dashboard default
              </button>
            </li>
            <li v-for="option in matches" :key="option.id" class="cadence-menu-item">
              <button
                type="button"
                :aria-pressed="selected === option.id"
                :class="selected === option.id ? 'text-primary' : ''"
                @click="choose(option.id, close)"
              >
                <span class="truncate">{{ option.name }}</span>
                <span
                  v-if="option.name !== option.id"
                  class="ml-auto truncate font-mono text-[0.65rem] text-base-content/60"
                  >{{ option.id }}</span
                >
              </button>
            </li>
          </ul>
          <p v-if="!options.length" class="text-xs text-base-content/60">
            This mission has no spacecraft yet.
          </p>
        </div>
      </div>
    </template>
  </CadencePopover>
</template>
