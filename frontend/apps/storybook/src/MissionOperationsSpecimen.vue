<script setup lang="ts">
import { CButton, CCheckbox, CTooltip } from "@cadence/ui";
import { computed, ref } from "vue";
import MissionMonitoringRail from "./MissionMonitoringRail.vue";
import { getMonitoringScenario } from "./monitoring-fixtures";
import type { MonitoringScenarioId } from "./monitoring-fixtures";

const props = withDefaults(
  defineProps<{
    monitoringScenario?: MonitoringScenarioId;
  }>(),
  {
    monitoringScenario: "nominal-live",
  },
);

const commandReady = ref(false);
const activeMonitoringScenario = computed(() => getMonitoringScenario(props.monitoringScenario));

const metrics = [
  { label: "Range", value: "384,211", unit: "km", delta: "+18.4" },
  { label: "Doppler", value: "−4.82", unit: "kHz", delta: "closing" },
  { label: "Link margin", value: "12.6", unit: "dB", delta: "+0.7" },
] as const;

const events = [
  { time: "14:22:08", label: "Carrier acquired", tone: "complete" },
  { time: "14:22:19", label: "Frame lock", tone: "complete" },
  { time: "14:23:02", label: "Telemetry flowing", tone: "live" },
  { time: "14:31:40", label: "Command window", tone: "future" },
] as const;
</script>

<template>
  <main class="operations-specimen">
    <aside class="mission-rail" aria-label="Mission navigation">
      <div class="mission-mark" aria-label="Cadence">
        <span>CAD</span>
        <i></i>
      </div>
      <nav aria-label="Primary">
        <button class="rail-item rail-item--active" aria-current="page">
          <span>01</span>Overview
        </button>
        <button class="rail-item"><span>02</span>Telemetry</button>
        <button class="rail-item"><span>03</span>Commands</button>
        <button class="rail-item"><span>04</span>Timeline</button>
      </nav>
      <div class="rail-foot">
        <span>MISSION CLOCK</span>
        <strong>184:14:23:02</strong>
        <small>UTC · DOY 235</small>
      </div>
    </aside>

    <section class="workspace">
      <header class="workspace-header">
        <div>
          <p class="breadcrumb">Artemis relay / Earth–Moon L2 / pass 042</p>
          <h1>Lunar relay</h1>
        </div>
        <div class="workspace-header__actions">
          <CTooltip content="Open the pass handover note for the next shift" side="bottom">
            <CButton variant="secondary">Handover note</CButton>
          </CTooltip>
          <CButton variant="primary">Open console</CButton>
        </div>
      </header>

      <MissionMonitoringRail :scenario="activeMonitoringScenario" />

      <div class="working-grid">
        <article class="panel pass-panel">
          <header class="panel-heading">
            <div>
              <p>Current pass</p>
              <h2>Goldstone · DSS-24</h2>
            </div>
            <span class="panel-index">P042 / LIVE</span>
          </header>

          <div class="pass-body">
            <div class="countdown">
              <span>Time to command window</span>
              <strong>08:38</strong>
              <p>Opens at 14:31:40 UTC</p>
            </div>

            <figure class="orbit-plot">
              <svg viewBox="0 0 360 220" role="img" aria-labelledby="orbit-title orbit-description">
                <title id="orbit-title">Spacecraft tracking geometry</title>
                <desc id="orbit-description">
                  A stylized orbital track showing the relay approaching the command window.
                </desc>
                <circle class="orbit-plot__earth" cx="180" cy="110" r="38" />
                <ellipse
                  class="orbit-plot__track orbit-plot__track--outer"
                  cx="180"
                  cy="110"
                  rx="138"
                  ry="70"
                />
                <ellipse class="orbit-plot__track" cx="180" cy="110" rx="112" ry="54" />
                <path class="orbit-plot__arc" d="M64 139 C105 187 242 187 302 127" />
                <circle class="orbit-plot__craft" cx="276" cy="158" r="6" />
                <line class="orbit-plot__registration" x1="276" y1="158" x2="322" y2="184" />
                <text x="326" y="188">LR-02</text>
              </svg>
              <figcaption>
                <span>LOS −38.4°</span>
                <span>AZ 214.8°</span>
                <span>EL 43.1°</span>
              </figcaption>
            </figure>
          </div>
        </article>

        <section class="metric-stack" aria-label="Live pass metrics">
          <article v-for="metric in metrics" :key="metric.label" class="metric-card">
            <div>
              <span>{{ metric.label }}</span
              ><small>{{ metric.delta }}</small>
            </div>
            <p>
              {{ metric.value }} <em>{{ metric.unit }}</em>
            </p>
          </article>
        </section>

        <article class="panel signal-panel">
          <header class="panel-heading">
            <div>
              <p>Downlink quality</p>
              <h2>Carrier-to-noise density</h2>
            </div>
            <strong class="signal-value">48.2 <small>dB-Hz</small></strong>
          </header>
          <div class="signal-chart">
            <div class="signal-chart__labels" aria-hidden="true">
              <span>50</span><span>45</span><span>40</span>
            </div>
            <svg viewBox="0 0 720 180" role="img" aria-labelledby="signal-title signal-description">
              <title id="signal-title">Carrier-to-noise density over the current pass</title>
              <desc id="signal-description">The signal is stable and trending upward.</desc>
              <g class="signal-chart__grid">
                <line x1="0" x2="720" y1="24" y2="24" />
                <line x1="0" x2="720" y1="90" y2="90" />
                <line x1="0" x2="720" y1="156" y2="156" />
              </g>
              <path
                class="signal-chart__area"
                d="M0 148 C48 140 68 128 112 132 S184 111 230 116 S308 94 350 99 S430 68 478 79 S552 55 600 61 S673 38 720 44 L720 180 L0 180 Z"
              />
              <path
                class="signal-chart__line"
                d="M0 148 C48 140 68 128 112 132 S184 111 230 116 S308 94 350 99 S430 68 478 79 S552 55 600 61 S673 38 720 44"
              />
              <circle class="signal-chart__current" cx="720" cy="44" r="5" />
            </svg>
            <div class="signal-chart__times" aria-hidden="true">
              <span>14:22</span><span>14:25</span><span>14:28</span><span>Now</span>
            </div>
          </div>
        </article>

        <article class="panel event-panel">
          <header class="panel-heading">
            <div>
              <p>Pass sequence</p>
              <h2>Acquisition events</h2>
            </div>
            <span class="panel-index">03 / 04</span>
          </header>
          <ol class="event-list">
            <li v-for="event in events" :key="event.time" :data-tone="event.tone">
              <time>{{ event.time }}</time>
              <i aria-hidden="true"></i>
              <span>{{ event.label }}</span>
            </li>
          </ol>
        </article>

        <article class="panel command-panel">
          <header class="panel-heading">
            <div>
              <p>Prepared command</p>
              <h2>Update beacon cadence</h2>
            </div>
            <span class="authority-state">Authority / Awaiting approval</span>
          </header>
          <div class="command-code">
            <span>CMD</span>
            <strong>SET_BCN_RATE</strong>
            <code>RATE=4HZ · DURATION=PASS</code>
          </div>
          <CCheckbox id="command-readiness" v-model="commandReady">
            I verified the command parameters against procedure OPS-214.
          </CCheckbox>
          <div class="command-panel__actions">
            <CButton variant="quiet">View procedure</CButton>
            <CButton variant="primary" :disabled="!commandReady">Request approval</CButton>
          </div>
        </article>
      </div>
    </section>
  </main>
</template>

<style scoped>
.operations-specimen {
  display: grid;
  grid-template-columns: 196px minmax(0, 1fr);
  min-height: 100vh;
  color: var(--cadence-color-text);
  background: var(--cadence-color-canvas);
}

.mission-rail {
  position: sticky;
  top: 0;
  display: flex;
  height: 100vh;
  flex-direction: column;
  border-right: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-shell);
}

.mission-mark {
  position: relative;
  display: grid;
  height: 78px;
  padding: 0 var(--cadence-space-4);
  border-bottom: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.18em;
  place-items: center start;
}

.mission-mark i {
  position: absolute;
  right: var(--cadence-space-4);
  width: 8px;
  height: 8px;
  background: var(--cadence-color-signal);
}

.mission-rail nav {
  display: grid;
}

.rail-item {
  display: grid;
  grid-template-columns: 32px 1fr;
  align-items: center;
  min-height: 48px;
  padding: 0 var(--cadence-space-4);
  border: 0;
  border-bottom: 1px solid var(--cadence-color-border-subtle);
  color: var(--cadence-color-text-secondary);
  background: transparent;
  font-size: var(--cadence-type-body-sm);
  text-align: left;
  cursor: pointer;
}

.rail-item span {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 0.58rem;
}

.rail-item:hover {
  color: var(--cadence-color-text-strong);
  background: var(--cadence-color-surface-inset);
}

.rail-item--active {
  padding-left: 13px;
  border-left: 3px solid var(--cadence-color-signal);
  color: var(--cadence-color-text-strong);
  background: var(--cadence-color-surface-inset);
  font-weight: 620;
}

.rail-foot {
  display: grid;
  gap: 6px;
  margin-top: auto;
  padding: var(--cadence-space-4);
  border-top: 1px solid var(--cadence-color-border);
}

.rail-foot span,
.rail-foot small,
.breadcrumb,
.panel-heading p,
.panel-index,
.metric-card span,
.metric-card small {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 0.58rem;
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.rail-foot strong {
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: 0.7rem;
  font-weight: 500;
}

.workspace {
  min-width: 0;
  padding: clamp(20px, 3vw, 48px);
}

.workspace-header {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: var(--cadence-space-8);
  margin-bottom: var(--cadence-space-6);
  padding-bottom: var(--cadence-space-5);
  border-bottom: 1px solid var(--cadence-color-border);
}

.breadcrumb {
  margin: 0 0 var(--cadence-space-3);
}

.workspace-header h1 {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-size: clamp(2rem, 4vw, 3.5rem);
  font-weight: 680;
  letter-spacing: -0.045em;
  line-height: 0.9;
  text-transform: uppercase;
}

.workspace-header__actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: var(--cadence-space-2);
}

.working-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.6fr) minmax(260px, 0.65fr);
  gap: 1px;
  padding: 1px;
  background: var(--cadence-color-border);
}

.panel,
.metric-card {
  background: var(--cadence-color-surface);
}

.panel {
  min-width: 0;
  padding: clamp(18px, 2.5vw, 28px);
}

.panel-heading {
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: var(--cadence-space-6);
}

.panel-heading p {
  margin: 0 0 7px;
}

.panel-heading h2 {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-body-lg);
  font-weight: 630;
  letter-spacing: -0.02em;
  text-transform: uppercase;
}

.panel-index {
  white-space: nowrap;
}

.authority-state {
  padding-left: var(--cadence-space-3);
  border-left: 1px solid var(--cadence-color-signal);
  color: var(--cadence-color-text-secondary);
  font-family: var(--cadence-font-mono);
  font-size: 0.62rem;
  letter-spacing: var(--cadence-tracking-label);
  line-height: 1.5;
  text-align: right;
  text-transform: uppercase;
}

.pass-body {
  display: grid;
  grid-template-columns: minmax(220px, 0.75fr) minmax(300px, 1.25fr);
  align-items: center;
  gap: var(--cadence-space-8);
  min-height: 330px;
}

.countdown > span {
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
}

.countdown strong {
  display: block;
  margin: var(--cadence-space-3) 0 var(--cadence-space-1);
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: clamp(4rem, 8vw, 7.5rem);
  font-weight: 430;
  letter-spacing: -0.09em;
  line-height: 0.86;
}

.countdown p {
  margin: var(--cadence-space-4) 0 0;
  color: var(--cadence-color-text-secondary);
  font-family: var(--cadence-font-mono);
  font-size: 0.65rem;
}

.orbit-plot {
  min-width: 0;
  margin: 0;
}

.orbit-plot svg {
  display: block;
  width: 100%;
  max-height: 240px;
  overflow: visible;
}

.orbit-plot__earth {
  fill: var(--cadence-color-text-strong);
}

.orbit-plot__track {
  fill: none;
  stroke: var(--cadence-color-border);
  stroke-dasharray: 4 5;
  stroke-width: 1;
}

.orbit-plot__track--outer {
  stroke: var(--cadence-color-border-subtle);
}

.orbit-plot__arc {
  fill: none;
  stroke: var(--cadence-color-signal);
  stroke-width: 2;
}

.orbit-plot__craft {
  fill: var(--cadence-color-signal);
  stroke: var(--cadence-color-surface);
  stroke-width: 4;
}

.orbit-plot__registration {
  stroke: var(--cadence-color-text-muted);
  stroke-width: 1;
}

.orbit-plot text {
  fill: var(--cadence-color-text-secondary);
  font-family: var(--cadence-font-mono);
  font-size: 9px;
}

.orbit-plot figcaption,
.signal-chart__times {
  display: flex;
  justify-content: space-between;
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 0.58rem;
}

.metric-stack {
  display: grid;
  gap: 1px;
  background: var(--cadence-color-border);
}

.metric-card {
  display: flex;
  min-height: 108px;
  padding: var(--cadence-space-5);
  flex-direction: column;
  justify-content: space-between;
}

.metric-card > div {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-3);
}

.metric-card p {
  margin: var(--cadence-space-4) 0 0;
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: clamp(1.4rem, 2.5vw, 2.2rem);
  letter-spacing: -0.045em;
  line-height: 1;
}

.metric-card em {
  color: var(--cadence-color-text-muted);
  font-size: 0.68rem;
  font-style: normal;
  letter-spacing: 0;
}

.signal-panel {
  grid-column: 1;
}

.signal-value {
  color: var(--cadence-color-signal);
  font-family: var(--cadence-font-mono);
  font-size: 1.15rem;
  font-weight: 520;
}

.signal-value small {
  color: var(--cadence-color-text-muted);
  font-size: 0.58rem;
}

.signal-chart {
  position: relative;
  margin-top: var(--cadence-space-8);
  padding-left: 28px;
}

.signal-chart svg {
  display: block;
  width: 100%;
  height: 180px;
  overflow: visible;
}

.signal-chart__grid line {
  stroke: var(--cadence-color-border-subtle);
  stroke-width: 1;
}

.signal-chart__area {
  fill: color-mix(in srgb, var(--cadence-color-signal) 12%, transparent);
}

.signal-chart__line {
  fill: none;
  stroke: var(--cadence-color-signal);
  stroke-width: 2;
}

.signal-chart__current {
  fill: var(--cadence-color-signal);
  stroke: var(--cadence-color-surface);
  stroke-width: 3;
}

.signal-chart__labels {
  position: absolute;
  top: 10px;
  bottom: 22px;
  left: 0;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 0.55rem;
}

.event-list {
  display: grid;
  margin: var(--cadence-space-6) 0 0;
  padding: 0;
  list-style: none;
}

.event-list li {
  display: grid;
  grid-template-columns: 70px 18px 1fr;
  align-items: center;
  min-height: 47px;
  border-top: 1px solid var(--cadence-color-border-subtle);
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
}

.event-list time {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 0.6rem;
}

.event-list i {
  width: 7px;
  height: 7px;
  border: 1px solid var(--cadence-color-border-strong);
}

.event-list li[data-tone="complete"] i {
  border-color: var(--cadence-color-success);
  background: var(--cadence-color-success);
}

.event-list li[data-tone="live"] {
  color: var(--cadence-color-text-strong);
  font-weight: 620;
}

.event-list li[data-tone="live"] i {
  border-color: var(--cadence-color-signal);
  background: var(--cadence-color-signal);
}

.command-panel {
  grid-column: 1 / -1;
}

.command-code {
  display: grid;
  grid-template-columns: 50px minmax(160px, 0.45fr) 1fr;
  align-items: center;
  gap: var(--cadence-space-4);
  margin: var(--cadence-space-6) 0;
  padding: var(--cadence-space-4);
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface-inset);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-body-sm);
}

.command-code span,
.command-code code {
  color: var(--cadence-color-text-secondary);
}

.command-code strong {
  color: var(--cadence-color-text-strong);
}

.command-panel__actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--cadence-space-2);
  margin-top: var(--cadence-space-6);
  padding-top: var(--cadence-space-5);
  border-top: 1px solid var(--cadence-color-border-subtle);
}

@media (width <= 1100px) {
  .operations-specimen {
    grid-template-columns: 70px minmax(0, 1fr);
  }

  .mission-mark {
    justify-items: center;
    padding-inline: 0;
    font-size: 0.6rem;
  }

  .mission-mark i {
    display: none;
  }

  .rail-item {
    width: 100%;
    grid-template-columns: 1fr;
    padding: 0;
    font-size: 0;
    place-items: center;
  }

  .rail-item--active {
    padding-left: 0;
  }

  .rail-item span {
    font-size: 0.58rem;
  }

  .rail-foot {
    display: none;
  }

  .working-grid,
  .pass-body {
    grid-template-columns: 1fr;
  }

  .signal-panel,
  .command-panel {
    grid-column: auto;
  }

  .metric-stack {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

@media (width <= 760px) {
  .operations-specimen {
    display: block;
  }

  .mission-rail {
    display: none;
  }

  .workspace {
    padding: var(--cadence-space-4);
  }

  .workspace-header {
    align-items: start;
    flex-direction: column;
  }

  .workspace-header__actions {
    width: 100%;
    justify-content: flex-start;
  }

  .orbit-plot,
  .orbit-plot svg {
    overflow: hidden;
  }

  .metric-stack {
    grid-template-columns: 1fr;
  }

  .command-code {
    grid-template-columns: 1fr;
  }
}
</style>
