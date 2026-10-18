<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import {
  revisions,
  revisionLabel,
  type Configuration,
  type Inspector,
  type Section,
  type SetupIssue,
} from "./fixtures";

defineProps<{
  spacecraft: string;
  active: Configuration | null;
  draft: Configuration;
  changes: number;
  issues: readonly SetupIssue[];
  generation: number;
}>();
defineEmits<{
  navigate: [section: Section];
  inspect: [inspector: Inspector, event: MouseEvent];
  repair: [issue: SetupIssue, event: MouseEvent];
}>();
</script>

<template>
  <div class="sc-overview">
    <div class="sc-section-heading">
      <div>
        <p class="sc-eyebrow">{{ active ? "SPACECRAFT CONFIGURATION" : "FIRST CONFIGURATION" }}</p>
        <h2>{{ active ? "Configuration overview" : `Set up ${spacecraft}` }}</h2>
        <p class="sc-muted">
          {{
            active
              ? "Definitions, applications and delivery paths for this spacecraft."
              : "Start with the flight software catalog, then connect the applications that use it."
          }}
        </p>
      </div>
      <span class="sc-tag"
        ><CadenceStatusSymbol :status="active ? 'normal' : 'standby'" />{{
          active ? "Active configuration" : "Setup in progress"
        }}</span
      >
    </div>

    <section class="sc-configuration-map" aria-label="Active configuration connections">
      <div class="sc-map-spacecraft">
        <svg
          class="sc-spacecraft-drawing"
          viewBox="0 0 200 120"
          role="img"
          :aria-label="`${spacecraft} spacecraft schematic`"
        >
          <g fill="none" stroke="currentColor" stroke-width="1.2">
            <path
              d="M77 32 103 21 124 34 99 45Z M77 32v52l22 15 25-13V34 M99 45v54 M77 84l26-12 21 14 M103 21v51"
            />
            <path
              d="m16 44 52-7v35l-52 8Zm117-7 52 7v36l-52-8Z M42 41v35 M159 41v35 M16 56l52-5 M16 68l52-7 M133 50l52 6 M133 61l52 7 M68 54h9m47 0h9 M104 19V9m-10 0h20"
            />
            <circle cx="110" cy="48" r="4" />
            <path d="M86 59v14m5-11v8m19-7v13" />
          </g>
        </svg>
        <strong>{{ spacecraft }}</strong
        ><span>Onboard computer</span>
      </div>
      <span class="sc-connection" aria-hidden="true" />
      <button type="button" class="sc-map-node" @click="$emit('navigate', 'catalog')">
        <span class="hero-square-3-stack-3d sc-icon" aria-hidden="true" />
        <span class="sc-eyebrow">ACTIVE DEFINITIONS</span>
        <strong>{{
          active?.catalog ? `Kestrel FSW r${active.catalog}` : "No catalog bound"
        }}</strong>
        <span>{{
          active?.catalog
            ? `${revisions[active.catalog].packets} packets · ${revisions[active.catalog].commands} commands`
            : "Choose an exact revision"
        }}</span>
        <span v-if="draft.catalog !== active?.catalog && draft.catalog" class="sc-draft-label"
          >Draft → r{{ draft.catalog }}</span
        >
      </button>
      <span class="sc-connection" aria-hidden="true" />
      <div class="sc-map-consumers">
        <button
          type="button"
          class="sc-map-node sc-map-node--compact"
          @click="$emit('inspect', 'telemetry', $event)"
        >
          <span class="hero-chart-bar sc-icon" aria-hidden="true" /><span
            ><strong>Telemetry Decom</strong
            ><span>{{
              active?.telemetryEnabled ? "OBC downlink · VC 0" : "Not enabled"
            }}</span></span
          ><CadenceStatusSymbol :status="active?.telemetryEnabled ? 'normal' : 'off'" />
        </button>
        <button
          type="button"
          class="sc-map-node sc-map-node--compact"
          @click="$emit('inspect', 'commanding', $event)"
        >
          <span class="hero-command-line sc-icon" aria-hidden="true" /><span
            ><strong>Commanding</strong
            ><span>{{
              active?.commandingEnabled ? "Onboard computer · TC" : "Not enabled"
            }}</span></span
          ><CadenceStatusSymbol :status="active?.commandingEnabled ? 'normal' : 'off'" />
        </button>
      </div>
    </section>

    <div class="sc-overview-lower">
      <section class="sc-surface" aria-labelledby="sc-next-title">
        <header class="sc-block-heading">
          <h3 id="sc-next-title">
            {{
              issues.length
                ? "Next steps"
                : changes
                  ? "Ready for review"
                  : "Keep this spacecraft current"
            }}
          </h3>
          <span class="sc-count">{{ issues.length || changes || 1 }}</span>
        </header>
        <div v-if="issues.length" class="sc-task-list">
          <button
            v-for="(issue, index) in issues"
            :key="issue.id"
            type="button"
            class="sc-task"
            @click="$emit('repair', issue, $event)"
          >
            <span class="sc-step-number">{{ index + 1 }}</span
            ><span
              ><strong>{{ issue.action }}</strong
              ><span>{{ issue.label }}</span></span
            ><span class="hero-chevron-right sc-icon-sm" aria-hidden="true" />
          </button>
        </div>
        <div v-else-if="changes" class="sc-block-body sc-stack">
          <p>
            <strong>{{ changes }} configuration {{ changes === 1 ? "change" : "changes" }}</strong>
            prepared for this spacecraft.
          </p>
          <p class="sc-muted">
            Review the exact changes and their application impact before activation.
          </p>
          <CadenceButton size="sm" variant="primary" @click="$emit('navigate', 'changes')"
            >Review configuration</CadenceButton
          >
        </div>
        <div v-else class="sc-block-body sc-stack">
          <span class="sc-eyebrow">FLIGHT SOFTWARE CATALOG</span>
          <h3>
            {{ draft.catalog === "3.3" ? "Revision 3.4 is available" : "Using revision 3.4" }}
          </h3>
          <p class="sc-muted">
            {{
              draft.catalog === "3.3"
                ? "Adds image capture and payload health definitions. Check the software running on this vehicle before changing its binding."
                : "This spacecraft has the latest imported revision. KESTREL-02 can continue to use revision 3.3 independently."
            }}
          </p>
          <CadenceButton size="sm" @click="$emit('inspect', 'catalog', $event)"
            >Browse revisions<span class="hero-arrow-right sc-icon-sm" aria-hidden="true"
          /></CadenceButton>
        </div>
      </section>
      <section class="sc-surface" aria-labelledby="sc-active-title">
        <header class="sc-block-heading">
          <h3 id="sc-active-title">Active configuration</h3>
          <span class="sc-muted">{{ active ? `Generation ${generation}` : "Not activated" }}</span>
        </header>
        <dl class="sc-facts">
          <div>
            <dt>Catalog</dt>
            <dd>{{ revisionLabel(active?.catalog ?? null) }}</dd>
          </div>
          <div>
            <dt>Applications</dt>
            <dd>
              {{
                Number(active?.telemetryEnabled ?? false) +
                Number(active?.commandingEnabled ?? false)
              }}
              enabled
            </dd>
          </div>
          <div>
            <dt>Framing</dt>
            <dd>{{ active?.downlink ?? "—" }} ↓ / {{ active?.uplink ?? "—" }} ↑</dd>
          </div>
          <div>
            <dt>Delivery</dt>
            <dd>{{ active?.route ? "S-band · primary" : "Not connected" }}</dd>
          </div>
        </dl>
        <p class="sc-section-note">
          Configuration describes how Cadence handles data. Contact and execution status are
          available in Ops.
        </p>
      </section>
    </div>
  </div>
</template>
