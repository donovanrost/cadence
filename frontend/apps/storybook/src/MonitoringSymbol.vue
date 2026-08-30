<script setup lang="ts">
import { CStatusSymbol } from "@cadence/ui";
import { computed, ref } from "vue";
import type { MonitoringItem } from "./monitoring-fixtures";
import SubjectGlyph from "./SubjectGlyph.vue";

const props = defineProps<{
  item: MonitoringItem;
}>();

const expanded = ref(false);
const evidenceId = computed(() => `monitoring-evidence-${props.item.id}`);
</script>

<template>
  <li class="monitoring-symbol" :data-monitoring-subject="item.id" :data-status="item.status">
    <button
      :id="`monitoring-trigger-${item.id}`"
      class="monitoring-symbol__trigger"
      type="button"
      :aria-controls="evidenceId"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <span class="monitoring-symbol__glyph">
        <SubjectGlyph :kind="item.subjectKind" :size="24" />
      </span>

      <span class="monitoring-symbol__identity">
        <strong>{{ item.identifier }}</strong>
        <small>{{ item.subject }}</small>
      </span>

      <span class="monitoring-symbol__state">
        <CStatusSymbol :status="item.status" :size="20" />
        <strong>{{ item.statusLabel }}</strong>
      </span>

      <span class="monitoring-symbol__summary">{{ item.summary }}</span>
      <time :datetime="item.observedAt">{{ item.observedLabel }}</time>
      <span class="monitoring-symbol__disclosure" aria-hidden="true">
        {{ expanded ? "−" : "+" }}
      </span>
    </button>

    <section
      v-if="expanded"
      :id="evidenceId"
      class="monitoring-symbol__evidence"
      role="region"
      :aria-label="`${item.identifier} monitoring evidence`"
    >
      <p>{{ item.summary }}</p>
      <dl>
        <div v-for="fact in item.evidence" :key="fact.label">
          <dt>{{ fact.label }}</dt>
          <dd>{{ fact.value }}</dd>
        </div>
      </dl>
    </section>
  </li>
</template>

<style scoped>
.monitoring-symbol {
  border-top: 1px solid var(--cadence-color-border-subtle);
}

.monitoring-symbol__trigger {
  display: grid;
  width: 100%;
  min-height: 66px;
  padding: 0;
  align-items: stretch;
  border: 0;
  color: var(--cadence-color-text);
  background: transparent;
  cursor: pointer;
  grid-template-columns:
    52px minmax(134px, 0.72fr) minmax(126px, 0.56fr) minmax(240px, 1.6fr) 82px
    36px;
  text-align: left;
}

.monitoring-symbol__trigger:hover,
.monitoring-symbol__trigger[aria-expanded="true"] {
  background: var(--cadence-color-surface-inset);
}

.monitoring-symbol__trigger > span,
.monitoring-symbol__trigger > time {
  display: flex;
  min-width: 0;
  padding-inline: var(--cadence-space-3);
  align-items: center;
  border-left: 1px solid var(--cadence-color-border-subtle);
}

.monitoring-symbol__trigger > :first-child {
  border-left: 0;
}

.monitoring-symbol__glyph {
  justify-content: center;
}

.monitoring-symbol__identity {
  flex-direction: column;
  justify-content: center;
  gap: 3px;
}

.monitoring-symbol__identity strong,
.monitoring-symbol__state strong {
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-body-sm);
  font-weight: 640;
}

.monitoring-symbol__identity strong {
  overflow-wrap: anywhere;
}

.monitoring-symbol__identity small {
  color: var(--cadence-color-text-muted);
  font-size: 0.6rem;
  line-height: 1.3;
}

.monitoring-symbol__state {
  gap: var(--cadence-space-2);
}

.monitoring-symbol__summary {
  overflow: hidden;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
  line-height: 1.35;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.monitoring-symbol__trigger time {
  justify-content: flex-end;
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 0.62rem;
}

.monitoring-symbol__disclosure {
  justify-content: center;
  color: var(--cadence-color-text-secondary);
  font-family: var(--cadence-font-mono);
  font-size: 1rem;
}

.monitoring-symbol__evidence {
  display: grid;
  padding: var(--cadence-space-4) var(--cadence-space-5) var(--cadence-space-5) 52px;
  border-top: 1px solid var(--cadence-color-border-subtle);
  background: var(--cadence-color-surface-inset);
  grid-template-columns: minmax(180px, 0.85fr) minmax(300px, 1.5fr);
  gap: var(--cadence-space-8);
}

.monitoring-symbol__evidence p {
  max-width: 44ch;
  margin: 0;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
  line-height: var(--cadence-leading-copy);
}

.monitoring-symbol__evidence dl {
  display: grid;
  margin: 0;
  border-top: 1px solid var(--cadence-color-border);
  border-left: 1px solid var(--cadence-color-border);
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.monitoring-symbol__evidence dl > div {
  display: grid;
  min-height: 58px;
  padding: var(--cadence-space-2) var(--cadence-space-3);
  align-content: center;
  border-right: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
  gap: var(--cadence-space-1);
}

.monitoring-symbol__evidence dt,
.monitoring-symbol__evidence dd {
  margin: 0;
  font-family: var(--cadence-font-mono);
}

.monitoring-symbol__evidence dt {
  color: var(--cadence-color-text-muted);
  font-size: 0.56rem;
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.monitoring-symbol__evidence dd {
  color: var(--cadence-color-text-strong);
  font-size: 0.68rem;
}

@media (width <= 940px) {
  .monitoring-symbol__trigger {
    grid-template-columns: 52px minmax(126px, 0.8fr) minmax(118px, 0.64fr) minmax(180px, 1fr) 36px;
  }

  .monitoring-symbol__trigger time {
    display: none;
  }
}

@media (width <= 680px) {
  .monitoring-symbol__trigger {
    min-height: 72px;
    grid-template-columns: 44px minmax(116px, 1fr) minmax(112px, 0.85fr) 32px;
  }

  .monitoring-symbol__summary {
    display: none !important;
  }

  .monitoring-symbol__evidence {
    padding-left: var(--cadence-space-4);
    grid-template-columns: 1fr;
    gap: var(--cadence-space-4);
  }

  .monitoring-symbol__evidence dl {
    grid-template-columns: 1fr;
  }
}
</style>
