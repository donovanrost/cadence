<script setup lang="ts">
import type { MonitoringScenario } from "./monitoring-fixtures";
import MonitoringSymbol from "./MonitoringSymbol.vue";

defineProps<{
  scenario: MonitoringScenario;
}>();
</script>

<template>
  <section
    :id="`mission-monitoring-rail-${scenario.id}`"
    class="mission-monitoring-rail"
    :data-monitoring-scenario="scenario.id"
    :aria-label="`${scenario.label} operational monitoring`"
  >
    <header class="mission-monitoring-rail__header">
      <div>
        <p>Operational state / {{ scenario.items.length }} monitored subjects</p>
        <h2 :id="`mission-monitoring-title-${scenario.id}`">{{ scenario.label }}</h2>
      </div>
      <p class="mission-monitoring-rail__note">{{ scenario.note }}</p>
      <div class="mission-monitoring-rail__time">
        <span>{{ scenario.scope }}</span>
        <strong>{{ scenario.timeBasis }}</strong>
        <time :datetime="scenario.asOf">As of {{ scenario.asOfLabel }}</time>
      </div>
    </header>

    <div class="mission-monitoring-rail__columns" aria-hidden="true">
      <span>Subject</span>
      <span>Status</span>
      <span>Current evidence</span>
      <span>Observed</span>
      <span></span>
    </div>

    <ul class="mission-monitoring-rail__list" aria-label="Monitored mission subjects">
      <MonitoringSymbol v-for="item in scenario.items" :key="item.id" :item="item" />
    </ul>
  </section>
</template>

<style scoped>
.mission-monitoring-rail {
  margin-bottom: var(--cadence-space-6);
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface);
}

.mission-monitoring-rail__header {
  display: grid;
  min-height: 92px;
  padding: var(--cadence-space-4) var(--cadence-space-5);
  align-items: center;
  grid-template-columns: minmax(210px, 0.8fr) minmax(280px, 1.35fr) minmax(190px, 0.7fr);
  gap: var(--cadence-space-6);
}

.mission-monitoring-rail__header p,
.mission-monitoring-rail__header h2 {
  margin: 0;
}

.mission-monitoring-rail__header > div:first-child p,
.mission-monitoring-rail__time span,
.mission-monitoring-rail__time strong,
.mission-monitoring-rail__time time,
.mission-monitoring-rail__columns {
  font-family: var(--cadence-font-mono);
  font-size: 0.58rem;
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.mission-monitoring-rail__header > div:first-child p,
.mission-monitoring-rail__time span,
.mission-monitoring-rail__time time,
.mission-monitoring-rail__columns {
  color: var(--cadence-color-text-muted);
}

.mission-monitoring-rail__header h2 {
  margin-top: var(--cadence-space-2);
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-title-md);
  font-weight: 660;
  letter-spacing: -0.025em;
  text-transform: uppercase;
}

.mission-monitoring-rail__note {
  max-width: 62ch;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
  line-height: var(--cadence-leading-copy);
}

.mission-monitoring-rail__time {
  display: grid;
  justify-items: end;
  gap: 5px;
  text-align: right;
}

.mission-monitoring-rail__time strong {
  color: var(--cadence-color-signal);
  font-weight: 600;
}

.mission-monitoring-rail__columns {
  display: grid;
  min-height: 28px;
  padding-left: 52px;
  align-items: center;
  border-top: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface-inset);
  grid-template-columns: minmax(134px, 0.72fr) minmax(126px, 0.56fr) minmax(240px, 1.6fr) 82px 36px;
}

.mission-monitoring-rail__columns span {
  padding-inline: var(--cadence-space-3);
}

.mission-monitoring-rail__list {
  margin: 0;
  padding: 0;
  list-style: none;
}

@media (width <= 940px) {
  .mission-monitoring-rail__header {
    grid-template-columns: minmax(200px, 0.8fr) 1fr;
  }

  .mission-monitoring-rail__note {
    display: none;
  }

  .mission-monitoring-rail__columns {
    grid-template-columns: minmax(126px, 0.8fr) minmax(118px, 0.64fr) minmax(180px, 1fr) 36px;
  }

  .mission-monitoring-rail__columns span:nth-child(4) {
    display: none;
  }
}

@media (width <= 680px) {
  .mission-monitoring-rail__header {
    min-height: 0;
    padding: var(--cadence-space-4);
    grid-template-columns: 1fr;
    gap: var(--cadence-space-4);
  }

  .mission-monitoring-rail__time {
    justify-items: start;
    text-align: left;
  }

  .mission-monitoring-rail__columns {
    display: none;
  }
}
</style>
