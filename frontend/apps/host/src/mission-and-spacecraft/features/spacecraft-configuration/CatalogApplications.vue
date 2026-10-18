<script setup lang="ts">
import { computed } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import type { ConfigurationDocument, ConfigurationSnapshot, Inspector } from "./contracts";
import { revisionLabel, sourceLabel } from "./presentation";
const props = defineProps<{ snapshot: ConfigurationSnapshot; draft: ConfigurationDocument }>();
defineEmits<{ inspect: [kind: Inspector, event: MouseEvent] }>();
const selected = computed(() =>
  props.snapshot.catalogs.find((item) => item.id === props.draft.catalog_revision_id),
);
</script>
<template>
  <div class="scw-stack">
    <div class="scw-section-heading">
      <div>
        <p class="scw-eyebrow">DEFINITIONS & CONSUMERS</p>
        <h2>Catalog & applications</h2>
        <p class="scw-muted">
          Select an imported revision in this draft, save the configuration, then review and
          activate it to change the active configuration.
        </p>
      </div>
      <CadenceLink :href="snapshot.links.catalog"
        >Mission catalog<template #icon><span class="hero-arrow-up-right" /></template
      ></CadenceLink>
    </div>
    <section class="scw-surface">
      <header class="scw-block-heading">
        <h3>Onboard computer</h3>
        <span class="scw-muted">{{ snapshot.name }}</span>
      </header>
      <div class="scw-binding">
        <span class="scw-resource-icon"
          ><span class="hero-square-3-stack-3d" aria-hidden="true"
        /></span>
        <div class="scw-binding-copy">
          <span class="scw-eyebrow">FLIGHT SOFTWARE CATALOG</span>
          <h3>{{ selected?.name ?? "Bind your flight software catalog" }}</h3>
          <span class="scw-muted">{{
            selected
              ? "An exact revision for this spacecraft."
              : "An imported catalog supplies command and telemetry definitions."
          }}</span>
        </div>
        <span v-if="selected" class="scw-revision">{{ selected.label }}</span
        ><CadenceButton
          size="sm"
          :variant="selected ? 'secondary' : 'primary'"
          @click="$emit('inspect', 'catalog', $event)"
          >{{ selected ? "Change revision" : "Choose catalog" }}</CadenceButton
        >
      </div>
      <div v-if="selected" class="scw-definition-counts">
        <span
          ><strong>{{ selected.packets }}</strong> packets</span
        ><span
          ><strong>{{ selected.commands }}</strong> commands</span
        ><span
          ><strong>{{ selected.declarations }}</strong> declarations</span
        ><span class="scw-muted">{{
          snapshot.active?.document.catalog_revision_id === selected.id
            ? "Matches active configuration"
            : "Selected in draft"
        }}</span>
      </div>
    </section>
    <section>
      <header class="scw-block-heading scw-block-heading--plain">
        <div>
          <h3>Applications & capabilities</h3>
          <p class="scw-muted">Enable a capability, then connect its inputs.</p>
        </div>
        <CadenceLink :href="snapshot.links.applications">Manage applications</CadenceLink>
      </header>
      <div class="scw-application-list">
        <button
          type="button"
          class="scw-application"
          @click="$emit('inspect', 'telemetry', $event)"
        >
          <span class="scw-resource-icon"><span class="hero-chart-bar" aria-hidden="true" /></span
          ><span class="scw-application-copy"
            ><strong>Telemetry Decom</strong
            ><span>Turn incoming packets into named, typed measurements.</span
            ><span v-if="draft.telemetry_enabled" class="scw-application-binding"
              >{{ sourceLabel(snapshot, draft.telemetry_source_endpoint_id) }} ·
              {{ draft.handled_apids.length }} APIDs</span
            ></span
          ><span class="scw-tag"
            ><CadenceStatusSymbol
              :status="
                !draft.telemetry_enabled
                  ? 'off'
                  : draft.handled_apids.length && draft.telemetry_source_endpoint_id
                    ? 'normal'
                    : 'caution'
              "
            />{{
              !draft.telemetry_enabled
                ? "Not enabled"
                : draft.handled_apids.length && draft.telemetry_source_endpoint_id
                  ? "Configured"
                  : "Needs input"
            }}</span
          ><span class="hero-chevron-right scw-icon" aria-hidden="true" /></button
        ><button
          type="button"
          class="scw-application"
          @click="$emit('inspect', 'commanding', $event)"
        >
          <span class="scw-resource-icon"
            ><span class="hero-command-line" aria-hidden="true" /></span
          ><span class="scw-application-copy"
            ><strong>Commanding</strong
            ><span>Build and validate commands for the onboard computer.</span
            ><span v-if="draft.commanding_enabled" class="scw-application-binding">{{
              revisionLabel(snapshot, draft.catalog_revision_id)
            }}</span></span
          ><span class="scw-tag"
            ><CadenceStatusSymbol :status="draft.commanding_enabled ? 'normal' : 'off'" />{{
              draft.commanding_enabled ? "Configured" : "Not enabled"
            }}</span
          ><span class="hero-chevron-right scw-icon" aria-hidden="true" />
        </button>
      </div>
      <p class="scw-note">
        These settings belong to {{ snapshot.name }}. Other spacecraft retain their own catalog
        revisions.
      </p>
    </section>
  </div>
</template>
