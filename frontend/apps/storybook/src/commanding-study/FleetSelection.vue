<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceSelectionTile from "@cadence/ui/CadenceSelectionTile.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import SpacecraftSchematic from "./SpacecraftSchematic.vue";
import { fleet } from "./fixtures";
const props = defineProps<{ selected: string[] }>();
const emit = defineEmits<{ toggle: [id: string]; select: [ids: string[]] }>();
const query = ref("");
const visible = computed(() =>
  fleet.filter((target) => target.id.toLowerCase().includes(query.value.toLowerCase())),
);
function selectVisible() {
  emit("select", [...new Set([...props.selected, ...visible.value.map((target) => target.id)])]);
}
</script>
<template>
  <section class="study-pane study-fleet" aria-labelledby="study-fleet-title">
    <header class="study-pane-heading">
      <h2 id="study-fleet-title">
        <span class="hero-square-3-stack-3d study-icon" aria-hidden="true" />Spacecraft
      </h2>
      <span class="study-count">{{ selected.length }} / {{ fleet.length }}</span>
    </header>
    <div class="study-search">
      <span class="hero-magnifying-glass study-icon" aria-hidden="true" />
      <input
        id="study-fleet-search"
        v-model="query"
        aria-label="Find spacecraft"
        placeholder="Find spacecraft…"
        type="search"
      />
    </div>
    <div class="study-fleet-actions">
      <CadenceButton size="xs" variant="quiet" @click="selectVisible">Select visible</CadenceButton>
      <CadenceButton
        size="xs"
        variant="quiet"
        :disabled="!selected.length"
        @click="emit('select', [])"
        >Clear</CadenceButton
      >
    </div>
    <div class="study-scroll study-fleet-grid">
      <CadenceSelectionTile
        v-for="target in visible"
        :key="target.id"
        :data-target="target.id"
        :selected="selected.includes(target.id)"
        :label="'Select ' + target.id"
        @click="emit('toggle', target.id)"
      >
        <template #title
          ><span class="study-mono">{{ target.id }}</span></template
        >
        <template #visual
          ><SpacecraftSchematic :selected="selected.includes(target.id)"
        /></template>
        <span class="study-target-condition"
          ><CadenceStatusSymbol :status="target.health" :size="16" />{{ target.condition }}</span
        >
        <span class="study-target-bottom">
          <span
            ><span class="hero-signal study-icon-small" aria-hidden="true" />{{
              target.contact ? "In contact" : "No contact"
            }}</span
          >
          <span
            class="study-battery"
            :aria-label="
              target.battery === null ? 'Battery unknown' : 'Battery ' + target.battery + ' percent'
            "
          >
            <span aria-hidden="true" class="study-battery-track"
              ><span :style="{ width: (target.battery ?? 0) + '%' }"
            /></span>
            {{ target.battery === null ? "—" : target.battery + "%" }}
          </span>
        </span>
      </CadenceSelectionTile>
      <p v-if="!visible.length" class="study-empty">No spacecraft match this search.</p>
    </div>
    <footer class="study-pane-footer">
      <span>2 orbital planes</span><span>Snapshot · 14:32:07 UTC</span>
    </footer>
  </section>
</template>
