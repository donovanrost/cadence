<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadencePopover from "@cadence/ui/CadencePopover.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import type { ConfigurationSnapshot } from "./contracts";
import type { ConfigurationDrafts } from "./drafts";
import { revisionLabel } from "./presentation";
defineProps<{ snapshot: ConfigurationSnapshot; drafts: ConfigurationDrafts }>();
</script>
<template>
  <CadencePopover id="spacecraft-switcher" identity="spacecraft-switcher" align="start">
    <template #trigger
      ><CadenceButton size="sm" variant="quiet" data-overlay-trigger aria-label="Switch spacecraft"
        ><span class="hero-cpu-chip scw-icon" aria-hidden="true" />Switch spacecraft<span
          class="hero-chevron-down scw-icon"
          aria-hidden="true" /></CadenceButton
    ></template>
    <template #content="{ open, close }">
      <section v-show="open" class="scw-switcher" aria-labelledby="spacecraft-switcher-title">
        <header>
          <p class="scw-eyebrow">{{ snapshot.mission_name }} / SPACECRAFT</p>
          <h2 id="spacecraft-switcher-title">
            Switch spacecraft <span class="scw-count">{{ snapshot.fleet_total }}</span>
          </h2>
        </header>
        <nav aria-label="Mission spacecraft">
          <a
            v-for="craft in snapshot.fleet"
            :key="craft.id"
            :href="craft.href"
            :aria-current="craft.id === snapshot.spacecraft_id ? 'page' : undefined"
            @click="close"
          >
            <span class="scw-switcher-top"
              ><span class="hero-cpu-chip scw-icon" aria-hidden="true" /><strong>{{
                craft.name
              }}</strong
              ><CadenceStatusSymbol :status="craft.active_catalog_id ? 'normal' : 'standby'"
            /></span>
            <span class="scw-muted">{{ revisionLabel(snapshot, craft.active_catalog_id) }}</span>
            <span class="scw-switcher-details"
              ><code>SCID {{ craft.scid ?? "—" }}</code
              ><span v-if="drafts.changed(craft.id)">Unsaved edits</span
              ><span v-else-if="craft.has_changes">Saved changes</span></span
            >
          </a>
        </nav>
        <footer>
          <a :href="`/missions/${snapshot.mission_id}/spacecraft`">View all spacecraft</a>
        </footer>
      </section>
    </template>
  </CadencePopover>
</template>
