<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import type { ConfigurationDocument, ConfigurationSnapshot, Inspector } from "./contracts";
import { revisionLabel, sourceLabel, type SetupIssue } from "./presentation";
defineProps<{
  snapshot: ConfigurationSnapshot;
  draft: ConfigurationDocument;
  changes: number;
  issues: readonly SetupIssue[];
}>();
defineEmits<{ inspect: [kind: Inspector, event: MouseEvent] }>();
</script>
<template>
  <div class="scw-stack">
    <div class="scw-section-heading">
      <div>
        <p class="scw-eyebrow">
          {{ snapshot.active ? "SPACECRAFT CONFIGURATION" : "FIRST CONFIGURATION" }}
        </p>
        <h2>{{ snapshot.active ? "Configuration overview" : `Set up ${snapshot.name}` }}</h2>
        <p class="scw-muted">Definitions, applications and communications for this spacecraft.</p>
      </div>
      <span class="scw-tag"
        ><CadenceStatusSymbol :status="snapshot.active ? 'normal' : 'standby'" />{{
          snapshot.active ? "Configuration active" : "Setup in progress"
        }}</span
      >
    </div>
    <section class="scw-map" aria-label="Active configuration connections">
      <div class="scw-map-spacecraft">
        <svg class="scw-drawing" viewBox="0 0 200 120" aria-hidden="true">
          <g fill="none" stroke="currentColor" stroke-width="1.2">
            <path
              d="M77 32 103 21 124 34 99 45Z M77 32v52l22 15 25-13V34 M99 45v54 M77 84l26-12 21 14 M103 21v51"
            />
            <path
              d="m16 44 52-7v35l-52 8Zm117-7 52 7v36l-52-8Z M42 41v35 M159 41v35 M16 56l52-5 M16 68l52-7 M133 50l52 6 M133 61l52 7 M68 54h9m47 0h9 M104 19V9m-10 0h20"
            />
            <circle cx="110" cy="48" r="4" />
            <path d="M86 59v14m5-11v8m19-7v13" />
          </g></svg
        ><strong>{{ snapshot.name }}</strong
        ><span>Onboard computer</span>
      </div>
      <span class="scw-connection" aria-hidden="true" />
      <a class="scw-node" :href="`${snapshot.base_href}?section=catalog`"
        ><span class="hero-square-3-stack-3d scw-icon" aria-hidden="true" /><span
          class="scw-eyebrow"
          >ACTIVE DEFINITIONS</span
        ><strong>{{
          revisionLabel(snapshot, snapshot.active?.document.catalog_revision_id)
        }}</strong
        ><span v-if="snapshot.active">Generation {{ snapshot.active.generation }}</span
        ><span v-else>Choose an exact revision</span
        ><span
          v-if="
            draft.catalog_revision_id &&
            draft.catalog_revision_id !== snapshot.active?.document.catalog_revision_id
          "
          class="scw-draft-label"
          >Draft → {{ revisionLabel(snapshot, draft.catalog_revision_id) }}</span
        ></a
      >
      <span class="scw-connection" aria-hidden="true" />
      <div class="scw-consumers">
        <button
          type="button"
          class="scw-node scw-node--compact"
          @click="$emit('inspect', 'telemetry', $event)"
        >
          <span class="hero-chart-bar scw-icon" aria-hidden="true" /><span
            ><strong>Telemetry Decom</strong
            ><span>{{
              snapshot.active?.document.telemetry_enabled
                ? sourceLabel(snapshot, snapshot.active.document.telemetry_source_endpoint_id)
                : "Not enabled"
            }}</span></span
          ><CadenceStatusSymbol
            :status="snapshot.active?.document.telemetry_enabled ? 'normal' : 'off'"
          /></button
        ><button
          type="button"
          class="scw-node scw-node--compact"
          @click="$emit('inspect', 'commanding', $event)"
        >
          <span class="hero-command-line scw-icon" aria-hidden="true" /><span
            ><strong>Commanding</strong
            ><span>{{
              snapshot.active?.document.commanding_enabled
                ? "Active command definitions"
                : "Not enabled"
            }}</span></span
          ><CadenceStatusSymbol
            :status="snapshot.active?.document.commanding_enabled ? 'normal' : 'off'"
          />
        </button>
      </div>
    </section>
    <div class="scw-columns">
      <section class="scw-surface">
        <header class="scw-block-heading">
          <h3>
            {{
              issues.length
                ? "Next steps"
                : changes
                  ? "Ready for review"
                  : "Keep this spacecraft current"
            }}
          </h3>
          <span class="scw-count">{{ issues.length || changes || 1 }}</span>
        </header>
        <div v-if="issues.length" class="scw-task-list">
          <a
            v-for="(issue, index) in issues"
            :key="issue.id"
            class="scw-task"
            :href="`${snapshot.base_href}?section=${issue.section}`"
            ><span class="scw-step">{{ index + 1 }}</span
            ><span
              ><strong>{{ issue.label }}</strong
              ><span>{{ issue.detail }}</span></span
            ><span class="hero-chevron-right scw-icon" aria-hidden="true"
          /></a>
        </div>
        <div v-else class="scw-block-body scw-stack">
          <p>
            {{
              changes
                ? `${changes} configuration changes prepared for this spacecraft.`
                : "Compare imported revisions with the software running on this vehicle."
            }}
          </p>
          <CadenceLink v-if="changes" :href="`${snapshot.base_href}?section=changes`"
            >Review configuration</CadenceLink
          ><CadenceButton v-else size="sm" @click="$emit('inspect', 'catalog', $event)"
            >Browse revisions</CadenceButton
          >
        </div>
      </section>
      <section class="scw-surface">
        <header class="scw-block-heading">
          <h3>Active configuration</h3>
          <span class="scw-muted">{{
            snapshot.active ? `Generation ${snapshot.active.generation}` : "Not activated"
          }}</span>
        </header>
        <dl class="scw-facts">
          <div>
            <dt>Catalog</dt>
            <dd>{{ revisionLabel(snapshot, snapshot.active?.document.catalog_revision_id) }}</dd>
          </div>
          <div>
            <dt>Capabilities</dt>
            <dd>
              {{
                Number(snapshot.active?.document.telemetry_enabled ?? false) +
                Number(snapshot.active?.document.commanding_enabled ?? false)
              }}
              enabled
            </dd>
          </div>
          <div>
            <dt>Framing</dt>
            <dd>
              {{ snapshot.active?.document.protocol?.downlink.toUpperCase() ?? "—" }} ↓ /
              {{ snapshot.active?.document.protocol?.uplink.toUpperCase() ?? "—" }} ↑
            </dd>
          </div>
          <div>
            <dt>Delivery paths</dt>
            <dd><CadenceLink :href="snapshot.links.communications">View in Comms</CadenceLink></dd>
          </div>
        </dl>
        <p class="scw-note">Contact, delivery and execution status remain available in Ops.</p>
      </section>
    </div>
  </div>
</template>
