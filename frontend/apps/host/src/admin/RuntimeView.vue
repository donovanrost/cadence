<script setup lang="ts">
import { CStatusSymbol } from "@cadence/ui";
import { computed } from "vue";
import type { FrontendSession } from "../auth/auth-client";

const props = defineProps<{
  session: FrontendSession;
}>();

const authorityExpiry = computed(() =>
  new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
    timeZoneName: "short",
  }).format(new Date(props.session.authority.adminModeExpiresAt)),
);

const contracts = [
  {
    name: "Frontend session",
    contract: "cadence.frontend-session.v1",
    owner: "VUE HOST",
  },
  {
    name: "Application catalog",
    contract: "cadence.first-party-frontend-catalog.v1",
    owner: "HOST BRIDGE",
  },
  {
    name: "Federated surface",
    contract: "cadence.application-surface.v1",
    owner: "APPLICATION HOST",
  },
] as const;
</script>

<template>
  <section id="runtime-view" class="runtime-page">
    <header class="runtime-page__head">
      <h1>Runtime</h1>
      <p>
        Evidence for the active frontend boundary. These values describe the PoC host process, not
        mission equipment state.
      </p>
    </header>

    <section class="authority-window" aria-labelledby="authority-window-title">
      <div class="authority-window__index">AUTH / 01</div>
      <div>
        <p>ACTIVE AUTHORITY</p>
        <h2 id="authority-window-title">Platform administrator</h2>
      </div>
      <dl>
        <div>
          <dt>IDENTITY</dt>
          <dd>{{ session.actor.email }}</dd>
        </div>
        <div>
          <dt>ENVIRONMENT</dt>
          <dd>{{ session.environment.name }}</dd>
        </div>
        <div>
          <dt>EXPIRES</dt>
          <dd>{{ authorityExpiry }}</dd>
        </div>
      </dl>
    </section>

    <section class="contract-register" aria-labelledby="contract-register-title">
      <header>
        <div>
          <p>BOUNDARY REGISTER</p>
          <h2 id="contract-register-title">Frontend contracts</h2>
        </div>
        <span>{{ contracts.length.toString().padStart(2, "0") }} DECLARED</span>
      </header>

      <article v-for="contract in contracts" :key="contract.contract">
        <CStatusSymbol status="normal" :label="`${contract.name} available`" :size="16" />
        <strong>{{ contract.name }}</strong>
        <code>{{ contract.contract }}</code>
        <span>{{ contract.owner }}</span>
      </article>
    </section>

    <footer>
      <span>SESSION TRANSPORT / SAME-ORIGIN HTTP-ONLY COOKIE</span>
      <span>AUTH PROVIDER / DEVELOPMENT HOST</span>
    </footer>
  </section>
</template>

<style scoped>
.runtime-page {
  min-height: 100%;
  padding: var(--cadence-space-10);
}

.runtime-page__head {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(280px, 480px);
  gap: var(--cadence-space-10);
  align-items: end;
  padding-bottom: var(--cadence-space-10);
}

.authority-window__index,
.authority-window p,
.authority-window dt,
.authority-window dd,
.contract-register p,
.contract-register header > span,
.contract-register code,
.contract-register article > span,
.runtime-page footer {
  font-family: var(--cadence-font-mono);
}

.authority-window p,
.contract-register p {
  margin: 0 0 var(--cadence-space-3);
  color: var(--cadence-color-text-muted);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.runtime-page h1,
.runtime-page h2 {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-weight: 580;
  letter-spacing: var(--cadence-tracking-display);
}

.runtime-page h1 {
  font-size: var(--cadence-type-display-lg);
  line-height: var(--cadence-leading-tight);
}

.runtime-page h2 {
  font-size: var(--cadence-type-title-lg);
}

.runtime-page__head > p {
  margin: 0;
  color: var(--cadence-color-text-secondary);
  line-height: var(--cadence-leading-copy);
}

.authority-window {
  display: grid;
  grid-template-columns: 120px minmax(240px, 0.8fr) minmax(360px, 1.2fr);
  min-height: 180px;
  border: 1px solid var(--cadence-color-border);
}

.authority-window > * {
  padding: var(--cadence-space-5);
  border-right: 1px solid var(--cadence-color-border);
}

.authority-window > *:last-child {
  border-right: 0;
}

.authority-window__index {
  color: var(--cadence-color-text-muted);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.authority-window > div:nth-child(2) {
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}

.authority-window dl {
  display: grid;
  align-content: center;
  gap: var(--cadence-space-4);
  margin: 0;
}

.authority-window dl div {
  display: grid;
  grid-template-columns: 120px 1fr;
  gap: var(--cadence-space-3);
}

.authority-window dt,
.authority-window dd {
  margin: 0;
  font-size: var(--cadence-type-body-sm);
}

.authority-window dt {
  color: var(--cadence-color-text-muted);
}

.authority-window dd {
  color: var(--cadence-color-text-strong);
  overflow-wrap: anywhere;
}

.contract-register {
  margin-top: var(--cadence-space-8);
  border: 1px solid var(--cadence-color-border);
}

.contract-register header,
.contract-register article {
  display: grid;
  align-items: center;
  border-bottom: 1px solid var(--cadence-color-border-subtle);
}

.contract-register header {
  grid-template-columns: 1fr auto;
  min-height: 96px;
  padding: var(--cadence-space-5);
}

.contract-register header > span,
.contract-register article > span {
  color: var(--cadence-color-text-muted);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.contract-register article {
  grid-template-columns: 32px minmax(180px, 0.8fr) minmax(280px, 1.2fr) 180px;
  min-height: 64px;
  padding: 0 var(--cadence-space-5);
}

.contract-register article:last-child {
  border-bottom: 0;
}

.contract-register article strong {
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-body-md);
}

.contract-register code {
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
}

.runtime-page footer {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-6);
  margin-top: var(--cadence-space-6);
  color: var(--cadence-color-text-muted);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

@media (max-width: 1000px) {
  .authority-window {
    grid-template-columns: 100px 1fr;
  }

  .authority-window dl {
    grid-column: 1 / -1;
    border-top: 1px solid var(--cadence-color-border);
    border-right: 0;
  }

  .contract-register article {
    grid-template-columns: 32px 1fr;
    gap: var(--cadence-space-2);
    padding: var(--cadence-space-4);
  }

  .contract-register article code,
  .contract-register article > span {
    grid-column: 2;
  }
}

@media (max-width: 720px) {
  .runtime-page {
    padding: var(--cadence-space-6) var(--cadence-space-4);
  }

  .runtime-page__head {
    grid-template-columns: 1fr;
    gap: var(--cadence-space-5);
  }

  .authority-window {
    grid-template-columns: 1fr;
  }

  .authority-window > * {
    border-right: 0;
    border-bottom: 1px solid var(--cadence-color-border);
  }

  .authority-window > *:last-child {
    border-bottom: 0;
  }

  .authority-window dl {
    grid-column: auto;
    border-top: 0;
  }

  .runtime-page footer {
    flex-direction: column;
  }
}
</style>
