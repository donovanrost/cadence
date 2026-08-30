<script setup lang="ts">
import { CButton, CTextField } from "@cadence/ui";
import { ref } from "vue";
import type { SignInCredentials } from "./auth-client";

defineProps<{
  error?: string;
  loading?: boolean;
}>();

const emit = defineEmits<{
  submit: [credentials: SignInCredentials];
}>();

const email = ref("");
const password = ref("");

function submit(): void {
  emit("submit", { email: email.value, password: password.value });
}
</script>

<template>
  <main id="sign-in-view" class="sign-in-view">
    <section class="sign-in-brief" aria-labelledby="sign-in-title">
      <a class="product-mark" href="/sign-in" aria-label="Cadence sign in">
        <span class="product-mark__index">CD / 01</span>
        <strong>CADENCE</strong>
      </a>

      <div class="sign-in-brief__message">
        <p class="kicker">CONTROL PLANE ACCESS</p>
        <h1 id="sign-in-title">Identity is part of the command chain.</h1>
        <p>
          Enter the environment administrator credentials to establish an explicit authority
          boundary before opening Cadence.
        </p>
      </div>

      <div class="access-sequence" aria-label="Access sequence">
        <div><span>01</span><strong>VERIFY IDENTITY</strong></div>
        <div><span>02</span><strong>ESTABLISH AUTHORITY</strong></div>
        <div><span>03</span><strong>ENTER CONTROL PLANE</strong></div>
      </div>
    </section>

    <section class="sign-in-panel" aria-label="Administrator sign in form">
      <header class="sign-in-panel__head">
        <div>
          <span class="evidence-label">ENVIRONMENT</span>
          <strong>LOCAL DEVELOPMENT</strong>
        </div>
        <div>
          <span class="evidence-label">AUTHORITY</span>
          <strong>PLATFORM ADMIN</strong>
        </div>
      </header>

      <form id="sign-in-form" class="sign-in-form" @submit.prevent="submit">
        <div class="sign-in-form__intro">
          <p class="kicker">AUTHENTICATION / 001</p>
          <h2>Sign in</h2>
          <p>Use the administrator configured through <code>CADENCE_ADMIN_*</code>.</p>
        </div>

        <div v-if="error" id="sign-in-error" class="sign-in-error" role="alert">
          <span aria-hidden="true">!</span>
          <p>{{ error }}</p>
        </div>

        <div class="sign-in-form__fields">
          <CTextField
            id="admin-email"
            v-model="email"
            label="Administrator email"
            type="email"
            autocomplete="username"
            placeholder="admin@example.com"
            required
          />
          <CTextField
            id="admin-password"
            v-model="password"
            label="Password"
            type="password"
            autocomplete="current-password"
            placeholder="Enter your password"
            required
          />
        </div>

        <CButton
          id="sign-in-submit"
          class="sign-in-form__submit"
          variant="primary"
          type="submit"
          :loading="loading"
        >
          Establish admin session
        </CButton>
      </form>

      <footer class="sign-in-panel__foot">
        <span>REGISTRATION DISABLED</span>
        <span>SESSION / HTTP-ONLY</span>
      </footer>
    </section>
  </main>
</template>

<style scoped>
.sign-in-view {
  min-height: 100vh;
  display: grid;
  grid-template-columns: minmax(0, 1.12fr) minmax(420px, 0.88fr);
  color: var(--cadence-color-text);
  background: var(--cadence-color-canvas);
}

.sign-in-brief,
.sign-in-panel {
  min-height: 100vh;
}

.sign-in-brief {
  display: grid;
  grid-template-rows: auto 1fr auto;
  padding: var(--cadence-space-8);
  border-right: 1px solid var(--cadence-color-border);
}

.product-mark {
  display: inline-flex;
  align-items: center;
  gap: var(--cadence-space-4);
  width: max-content;
  color: var(--cadence-color-text-strong);
  text-decoration: none;
}

.product-mark__index,
.evidence-label,
.kicker,
.access-sequence span,
.sign-in-panel__foot {
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.product-mark__index {
  padding-right: var(--cadence-space-4);
  border-right: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text-muted);
}

.product-mark strong {
  font-size: 0.875rem;
  letter-spacing: 0.18em;
}

.sign-in-brief__message {
  align-self: center;
  max-width: 760px;
  padding: var(--cadence-space-16) 0;
}

.kicker {
  margin: 0 0 var(--cadence-space-4);
  color: var(--cadence-color-text-muted);
}

.sign-in-brief h1 {
  max-width: 12ch;
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-display-xl);
  font-weight: 580;
  letter-spacing: var(--cadence-tracking-display);
  line-height: var(--cadence-leading-tight);
}

.sign-in-brief__message > p:last-child {
  max-width: 54ch;
  margin: var(--cadence-space-8) 0 0;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-lg);
  line-height: var(--cadence-leading-copy);
}

.access-sequence {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  border-top: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
}

.access-sequence div {
  display: grid;
  min-height: 104px;
  align-content: space-between;
  padding: var(--cadence-space-4);
  border-right: 1px solid var(--cadence-color-border);
}

.access-sequence div:last-child {
  border-right: 0;
}

.access-sequence span {
  color: var(--cadence-color-text-muted);
}

.access-sequence strong {
  max-width: 14ch;
  font-size: 0.75rem;
  letter-spacing: 0.04em;
  line-height: 1.35;
}

.sign-in-panel {
  display: grid;
  grid-template-rows: auto 1fr auto;
  background: var(--cadence-color-surface);
}

.sign-in-panel__head,
.sign-in-panel__foot {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-6);
  padding: var(--cadence-space-5) var(--cadence-space-6);
  border-bottom: 1px solid var(--cadence-color-border);
}

.sign-in-panel__head > div {
  display: grid;
  gap: var(--cadence-space-1);
}

.sign-in-panel__head > div:last-child {
  text-align: right;
}

.evidence-label {
  color: var(--cadence-color-text-muted);
}

.sign-in-panel__head strong {
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-body-sm);
}

.sign-in-form {
  align-self: center;
  width: min(100%, 520px);
  margin: 0 auto;
  padding: var(--cadence-space-10) var(--cadence-space-8);
}

.sign-in-form__intro h2 {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-display-lg);
  font-weight: 580;
  letter-spacing: var(--cadence-tracking-display);
  line-height: 1;
}

.sign-in-form__intro > p:last-child {
  margin: var(--cadence-space-4) 0 0;
  color: var(--cadence-color-text-secondary);
  line-height: var(--cadence-leading-copy);
}

.sign-in-form code {
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: 0.78em;
}

.sign-in-form__fields {
  display: grid;
  gap: var(--cadence-space-5);
  margin-top: var(--cadence-space-8);
}

.sign-in-error {
  display: grid;
  grid-template-columns: 32px 1fr;
  margin-top: var(--cadence-space-6);
  border: 1px solid var(--cadence-color-danger);
  color: var(--cadence-color-danger);
}

.sign-in-error span {
  display: grid;
  place-items: center;
  border-right: 1px solid var(--cadence-color-danger);
  font-family: var(--cadence-font-mono);
  font-weight: 700;
}

.sign-in-error p {
  margin: 0;
  padding: var(--cadence-space-3);
  font-size: var(--cadence-type-body-sm);
  line-height: 1.4;
}

.sign-in-form__submit {
  width: 100%;
  margin-top: var(--cadence-space-6);
}

.sign-in-panel__foot {
  align-items: center;
  border-top: 1px solid var(--cadence-color-border);
  border-bottom: 0;
  color: var(--cadence-color-text-muted);
}

@media (max-width: 900px) {
  .sign-in-view {
    grid-template-columns: 1fr;
  }

  .sign-in-brief,
  .sign-in-panel {
    min-height: auto;
  }

  .sign-in-brief {
    gap: var(--cadence-space-12);
    border-right: 0;
    border-bottom: 1px solid var(--cadence-color-border);
  }

  .sign-in-panel {
    min-height: 640px;
  }
}

@media (max-width: 580px) {
  .sign-in-brief {
    padding: var(--cadence-space-5);
  }

  .sign-in-brief h1 {
    font-size: 2.75rem;
  }

  .access-sequence {
    grid-template-columns: 1fr;
  }

  .access-sequence div {
    min-height: 72px;
    border-right: 0;
    border-bottom: 1px solid var(--cadence-color-border);
  }

  .access-sequence div:last-child {
    border-bottom: 0;
  }

  .sign-in-form {
    padding: var(--cadence-space-10) var(--cadence-space-5);
  }
}
</style>
