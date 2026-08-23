<script setup lang="ts">
import type { FederatedApplicationProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel, CStatus } from "@cadence/ui";
import { onMounted, ref } from "vue";

interface ProbeSnapshot {
  queryVersion: 1;
  hostContract: string;
  catalogMode: "development" | "production";
  checks: Array<{
    id: string;
    label: string;
    status: "nominal";
  }>;
}

const props = defineProps<FederatedApplicationProps>();
const snapshot = ref<ProbeSnapshot>();
const loading = ref(true);
const error = ref<string>();

onMounted(loadSnapshot);

async function loadSnapshot(): Promise<void> {
  loading.value = true;
  error.value = undefined;

  try {
    snapshot.value = await props.bridge.query<ProbeSnapshot>({
      queryId: "cadence.contract_probe.snapshot",
      version: 1,
      context: props.context,
    });
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : "The contract snapshot failed.";
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="probe-app">
    <CStatePanel
      v-if="loading"
      title="Interrogating host contracts"
      description="The second independent remote is requesting a scoped host snapshot."
      tone="loading"
    />
    <CStatePanel v-else-if="!snapshot" title="Contract snapshot unavailable" tone="error">
      <p>{{ error }}</p>
      <template #action>
        <CButton id="retry-contract-probe" size="sm" @click="loadSnapshot">Retry query</CButton>
      </template>
    </CStatePanel>
    <template v-else>
      <section class="probe-hero">
        <div>
          <p>DEVELOPMENT FIXTURE / INDEPENDENT REMOTE</p>
          <h2>One host. Two release trains.</h2>
          <span>
            Contract Probe is intentionally small: its job is to prove that discovery, mounting,
            context, queries, tokens, and shared components are not hard-coded to Telemetry Decom.
          </span>
        </div>
        <strong>02</strong>
      </section>

      <section class="probe-grid" aria-label="Runtime contract checks">
        <article v-for="(check, index) in snapshot.checks" :key="check.id">
          <span>0{{ index + 1 }}</span>
          <CStatus tone="nominal" pulse>{{ check.label }}</CStatus>
          <small>VERIFIED BY HOST QUERY</small>
        </article>
      </section>

      <footer class="probe-evidence">
        <div>
          <span>HOST CONTRACT</span>
          <strong>{{ snapshot.hostContract }}</strong>
        </div>
        <div>
          <span>ARTIFACT MODE</span>
          <strong>{{ snapshot.catalogMode }}</strong>
        </div>
        <div>
          <span>SERVER SCOPE</span>
          <strong>{{ context.spacecraftName }}</strong>
        </div>
      </footer>
    </template>
  </div>
</template>

<style scoped>
.probe-app {
  min-height: 467px;
  padding: 34px;
  color: var(--cadence-color-text);
  background:
    linear-gradient(120deg, rgb(70 217 208 / 4%), transparent 42%),
    var(--cadence-color-surface-inset);
}

.probe-hero {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 40px;
  align-items: start;
  padding-bottom: 34px;
  border-bottom: 1px solid var(--cadence-color-border);
}

.probe-hero p,
.probe-evidence span,
.probe-grid small {
  margin: 0;
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 9px;
  font-weight: 620;
  letter-spacing: 0.1em;
}

.probe-hero p {
  color: var(--cadence-color-signal);
}

.probe-hero h2 {
  margin: 10px 0 13px;
  color: var(--cadence-color-text-strong);
  font-size: clamp(28px, 5vw, 46px);
  font-weight: 590;
  letter-spacing: -0.045em;
}

.probe-hero div > span {
  display: block;
  max-width: 700px;
  color: var(--cadence-color-text-secondary);
  font-size: 13px;
  line-height: 1.6;
}

.probe-hero > strong {
  color: rgb(70 217 208 / 20%);
  font-family: var(--cadence-font-mono);
  font-size: 76px;
  font-weight: 400;
  line-height: 0.9;
}

.probe-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  margin-top: 28px;
  border: 1px solid var(--cadence-color-border);
}

.probe-grid article {
  display: grid;
  min-height: 126px;
  padding: 18px;
  background: rgb(255 255 255 / 1.5%);
}

.probe-grid article + article {
  border-left: 1px solid var(--cadence-color-border);
}

.probe-grid article > span {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 10px;
}

.probe-grid .cui-status {
  align-self: end;
  color: var(--cadence-color-text);
  font-size: 12px;
}

.probe-grid small {
  align-self: end;
}

.probe-evidence {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
  margin-top: 24px;
}

.probe-evidence div {
  display: grid;
  gap: 7px;
  padding-left: 12px;
  border-left: 2px solid var(--cadence-color-signal);
}

.probe-evidence strong {
  overflow: hidden;
  color: var(--cadence-color-text-secondary);
  font-family: var(--cadence-font-mono);
  font-size: 10px;
  font-weight: 520;
  text-overflow: ellipsis;
  text-transform: uppercase;
}

@media (max-width: 760px) {
  .probe-grid,
  .probe-evidence {
    grid-template-columns: 1fr;
  }

  .probe-grid article + article {
    border-top: 1px solid var(--cadence-color-border);
    border-left: 0;
  }

  .probe-hero > strong {
    display: none;
  }
}
</style>
