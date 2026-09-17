<script setup lang="ts">
import { computed } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadencePopover from "@cadence/ui/CadencePopover.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import { configurationChanges, fleet, type SpacecraftId } from "./fixtures";
import type { SpacecraftState } from "./state";

const props = defineProps<{
  selected: SpacecraftId;
  spacecraft: Readonly<Record<SpacecraftId, SpacecraftState>>;
}>();
defineEmits<{ select: [id: SpacecraftId] }>();
const activeCount = computed(
  () => fleet.filter((craft) => props.spacecraft[craft.id].active).length,
);
</script>

<template>
  <CadencePopover id="sc-spacecraft-switcher" identity="sc-spacecraft-switcher" align="start">
    <template #trigger
      ><CadenceButton size="sm" variant="quiet" aria-label="Switch spacecraft" data-overlay-trigger
        ><span class="hero-cpu-chip sc-icon" aria-hidden="true" />Switch spacecraft<span
          class="hero-chevron-down sc-icon-sm"
          aria-hidden="true" /></CadenceButton
    ></template>
    <template #content="{ open, close }">
      <section v-show="open" class="sc-switcher-panel" aria-labelledby="sc-switcher-title">
        <header>
          <div>
            <p>KESTREL / SPACECRAFT</p>
            <h2 id="sc-switcher-title">Switch spacecraft</h2>
          </div>
          <span class="sc-count">{{ fleet.length }}</span>
        </header>
        <div class="sc-switcher-choices" role="group" aria-label="Mission spacecraft">
          <button
            v-for="craft in fleet"
            :key="craft.id"
            type="button"
            class="sc-switcher-choice"
            :aria-label="`Open ${craft.id}`"
            :aria-pressed="selected === craft.id"
            @click="
              $emit('select', craft.id);
              close();
            "
          >
            <span class="sc-switcher-choice-heading"
              ><span class="hero-cpu-chip sc-icon" aria-hidden="true" /><strong>{{
                craft.id
              }}</strong
              ><CadenceStatusSymbol :status="spacecraft[craft.id].active ? 'normal' : 'standby'"
            /></span>
            <span class="sc-switcher-role">{{ craft.role }}</span>
            <span class="sc-switcher-details"
              ><code>SCID {{ craft.scid }}</code
              ><span :data-testid="`sc-fleet-revision-${craft.id}`">{{
                spacecraft[craft.id].active
                  ? `Active r${spacecraft[craft.id].active?.catalog}`
                  : "Awaiting setup"
              }}</span></span
            >
            <span
              v-if="
                configurationChanges(spacecraft[craft.id].active, spacecraft[craft.id].draft).length
              "
              class="sc-switcher-draft"
              >Draft changes preserved</span
            >
          </button>
        </div>
        <footer>
          {{ activeCount }} active configurations · {{ fleet.length - activeCount }} awaiting setup
        </footer>
      </section>
    </template>
  </CadencePopover>
</template>

<style scoped>
.sc-switcher-panel {
  width: min(306px, calc(100vw - 32px));
  max-height: var(--reka-popover-content-available-height);
  overflow: auto;
  z-index: var(--z-popover);
  border: 1px solid var(--border-strong);
  border-radius: var(--radius-md);
  background: var(--surface-raised);
  color: var(--text-bright);
  box-shadow: var(--shadow-floating);
  font: 12px/1.5 var(--font-sans);
}
.sc-switcher-panel > header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  padding: 16px;
  border-bottom: 1px solid var(--border-subtle);
}
.sc-switcher-panel header p {
  margin: 0 0 5px;
  color: var(--text-subtle);
  font: 10px var(--font-mono);
  letter-spacing: 0.07em;
}
.sc-switcher-panel header h2 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}
.sc-switcher-choices {
  display: grid;
  gap: 5px;
  padding: 8px;
}
.sc-switcher-choice {
  display: flex;
  flex-direction: column;
  gap: 6px;
  width: 100%;
  padding: 12px;
  border: 1px solid transparent;
  border-left: 2px solid transparent;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-bright);
  text-align: left;
  cursor: pointer;
}
.sc-switcher-choice:hover {
  background: var(--state-hover);
}
.sc-switcher-choice[aria-pressed="true"] {
  background: var(--state-selected);
  border-color: var(--border-default);
  border-left-color: var(--color-action);
}
.sc-switcher-choice:focus-visible {
  outline: 2px solid var(--color-action);
  outline-offset: -2px;
}
.sc-switcher-choice-heading {
  display: flex;
  align-items: center;
  gap: 8px;
}
.sc-switcher-choice-heading > strong {
  flex: 1;
  font: 600 12px var(--font-mono);
}
.sc-switcher-choice-heading > .sc-icon {
  color: var(--text-subtle);
}
.sc-switcher-role {
  padding-left: 25px;
  color: var(--text-subtle);
  font-size: 11px;
}
.sc-switcher-details {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  padding-left: 25px;
  color: var(--text-subtle);
  font: 10px var(--font-mono);
}
.sc-switcher-draft {
  padding-left: 25px;
  color: var(--status-warning-text);
  font-size: 10px;
}
.sc-switcher-panel > footer {
  padding: 12px 16px;
  border-top: 1px solid var(--border-subtle);
  color: var(--text-subtle);
  font-size: 10px;
}
</style>
