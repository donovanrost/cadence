<script setup lang="ts">
import { organizations } from "./admin-data";

const emit = defineEmits<{
  navigate: [path: string];
}>();

const metrics = [
  { label: "Organizations", value: organizations.length.toString(), detail: "ACTIVE TENANTS" },
  { label: "Administrators", value: "04", detail: "PLATFORM SCOPE" },
  { label: "Missions", value: "06", detail: "ACROSS ALL ORGS" },
  { label: "Applications", value: "02", detail: "POC CATALOG" },
] as const;

const surfaces = [
  {
    index: "01",
    title: "Organizations",
    description: "Inspect tenant boundaries, membership, and mission ownership.",
    path: "/admin/organizations",
  },
  {
    index: "02",
    title: "Runtime",
    description: "Verify the frontend session, authority window, and host contracts.",
    path: "/admin/runtime",
  },
  {
    index: "03",
    title: "Application host",
    description: "Continue into federated mission application surfaces.",
    path: "/applications",
  },
] as const;
</script>

<template>
  <section id="admin-overview" class="admin-page">
    <header class="admin-page__head">
      <h1>Control plane</h1>
      <p>
        Start with the system-wide boundaries that determine who can operate, what they can see, and
        where mission data belongs.
      </p>
    </header>

    <div id="admin-metrics" class="metric-grid">
      <article v-for="metric in metrics" :key="metric.label">
        <span>{{ metric.label }}</span>
        <strong>{{ metric.value }}</strong>
        <small>{{ metric.detail }}</small>
      </article>
    </div>

    <section class="control-surfaces" aria-labelledby="control-surfaces-title">
      <header>
        <p class="admin-kicker">PRIMARY ROUTES</p>
        <h2 id="control-surfaces-title">Control surfaces</h2>
      </header>
      <button
        v-for="surface in surfaces"
        :id="`open-${surface.index}`"
        :key="surface.path"
        type="button"
        @click="emit('navigate', surface.path)"
      >
        <span>{{ surface.index }}</span>
        <strong>{{ surface.title }}</strong>
        <p>{{ surface.description }}</p>
        <i aria-hidden="true">→</i>
      </button>
    </section>

    <footer class="admin-page__foot">
      <span>DATA SOURCE / FRONTEND POC FIXTURE</span>
      <span>ACCOUNT REGISTRATION / DEFERRED</span>
    </footer>
  </section>
</template>

<style scoped>
.admin-page {
  min-height: 100%;
  display: flex;
  flex-direction: column;
  padding: var(--cadence-space-10);
}

.admin-page__head {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(280px, 480px);
  gap: var(--cadence-space-10);
  align-items: end;
  padding-bottom: var(--cadence-space-10);
}

.admin-kicker {
  margin: 0 0 var(--cadence-space-3);
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.admin-page h1,
.admin-page h2 {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-weight: 580;
  letter-spacing: var(--cadence-tracking-display);
}

.admin-page h1 {
  font-size: var(--cadence-type-display-lg);
  line-height: var(--cadence-leading-tight);
}

.admin-page h2 {
  font-size: var(--cadence-type-title-lg);
}

.admin-page__head > p {
  margin: 0;
  color: var(--cadence-color-text-secondary);
  line-height: var(--cadence-leading-copy);
}

.metric-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  border: 1px solid var(--cadence-color-border);
}

.metric-grid article {
  display: grid;
  min-height: 172px;
  align-content: space-between;
  padding: var(--cadence-space-5);
  border-right: 1px solid var(--cadence-color-border);
}

.metric-grid article:last-child {
  border-right: 0;
}

.metric-grid span,
.metric-grid small,
.admin-page__foot {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.metric-grid strong {
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: 3.25rem;
  font-weight: 450;
  line-height: 1;
}

.control-surfaces {
  display: grid;
  grid-template-columns: minmax(220px, 0.8fr) repeat(3, minmax(0, 1fr));
  margin-top: var(--cadence-space-8);
  border: 1px solid var(--cadence-color-border);
}

.control-surfaces > header,
.control-surfaces > button {
  min-height: 220px;
  padding: var(--cadence-space-5);
  border: 0;
  border-right: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text);
  background: transparent;
  text-align: left;
}

.control-surfaces > header {
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}

.control-surfaces > button {
  display: grid;
  grid-template-rows: auto auto 1fr auto;
  gap: var(--cadence-space-4);
  cursor: pointer;
}

.control-surfaces > button:last-child {
  border-right: 0;
}

.control-surfaces > button:hover {
  color: var(--cadence-color-text-strong);
  background: var(--cadence-color-surface-inset);
}

.control-surfaces button span,
.control-surfaces button i {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  font-style: normal;
}

.control-surfaces button strong {
  font-size: var(--cadence-type-title-md);
  font-weight: 580;
}

.control-surfaces button p {
  margin: 0;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-md);
  line-height: var(--cadence-leading-copy);
}

.control-surfaces button i {
  justify-self: end;
  font-size: 1rem;
}

.control-surfaces button:hover i {
  color: var(--cadence-color-signal);
}

.admin-page__foot {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-6);
  margin-top: auto;
  padding-top: var(--cadence-space-10);
}

@media (max-width: 1180px) {
  .metric-grid {
    grid-template-columns: repeat(2, 1fr);
  }

  .metric-grid article:nth-child(2) {
    border-right: 0;
  }

  .metric-grid article:nth-child(-n + 2) {
    border-bottom: 1px solid var(--cadence-color-border);
  }

  .control-surfaces {
    grid-template-columns: 1fr;
  }

  .control-surfaces > header,
  .control-surfaces > button {
    min-height: 140px;
    border-right: 0;
    border-bottom: 1px solid var(--cadence-color-border);
  }

  .control-surfaces > button:last-child {
    border-bottom: 0;
  }
}

@media (max-width: 720px) {
  .admin-page {
    padding: var(--cadence-space-6) var(--cadence-space-4);
  }

  .admin-page__head {
    grid-template-columns: 1fr;
    gap: var(--cadence-space-5);
  }

  .metric-grid {
    grid-template-columns: 1fr;
  }

  .metric-grid article {
    min-height: 128px;
    border-right: 0;
    border-bottom: 1px solid var(--cadence-color-border);
  }

  .metric-grid article:last-child {
    border-bottom: 0;
  }

  .admin-page__foot {
    flex-direction: column;
  }
}
</style>
