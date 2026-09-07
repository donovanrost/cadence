<script setup lang="ts">
import type { FederatedApplicationProps } from "@cadence/plugin-sdk";
import { CadenceButton, CadenceStatePanel, CadenceStatus } from "@cadence/ui";
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
    <CadenceStatePanel
      v-if="loading"
      title="Interrogating host contracts"
      description="The second independent remote is requesting a scoped host snapshot."
      tone="loading"
    />
    <CadenceStatePanel v-else-if="!snapshot" title="Contract snapshot unavailable" tone="error">
      <p>{{ error }}</p>
      <template #action>
        <CadenceButton id="retry-contract-probe" size="sm" @click="loadSnapshot"
          >Retry query</CadenceButton
        >
      </template>
    </CadenceStatePanel>
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
          <CadenceStatus tone="nominal" pulse>{{ check.label }}</CadenceStatus>
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
  color: var(--color-base-content);
  background: linear-gradient(120deg, var(--surface-raised), transparent 42%), var(--surface-inset);
}

.probe-hero {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 40px;
  align-items: start;
  padding-bottom: 34px;
  border-bottom: 1px solid var(--border-default);
}

.probe-hero p,
.probe-evidence span,
.probe-grid small {
  margin: 0;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 9px;
  font-weight: 620;
  letter-spacing: 0.1em;
}

.probe-hero p {
  color: var(--color-action);
}

.probe-hero h2 {
  margin: 10px 0 13px;
  color: var(--text-bright);
  font-size: clamp(28px, 5vw, 46px);
  font-weight: 590;
  letter-spacing: -0.045em;
}

.probe-hero div > span {
  display: block;
  max-width: 700px;
  color: var(--text-subtle);
  font-size: 13px;
  line-height: 1.6;
}

.probe-hero > strong {
  color: var(--text-subtle);
  font-family: var(--font-mono);
  font-size: 76px;
  font-weight: 400;
  line-height: 0.9;
}

.probe-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  margin-top: 28px;
  border: 1px solid var(--border-default);
}

.probe-grid article {
  display: grid;
  min-height: 126px;
  padding: 18px;
  background: var(--surface-raised);
}

.probe-grid article + article {
  border-left: 1px solid var(--border-default);
}

.probe-grid article > span {
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

.probe-grid .cui-status {
  align-self: end;
  color: var(--color-base-content);
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
  border-left: 2px solid var(--color-action);
}

.probe-evidence strong {
  overflow: hidden;
  color: var(--text-subtle);
  font-family: var(--font-mono);
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
    border-top: 1px solid var(--border-default);
    border-left: 0;
  }

  .probe-hero > strong {
    display: none;
  }
}
</style>
