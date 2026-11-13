<script setup lang="ts">
import { computed, onMounted, ref, shallowRef } from "vue";
import { useRoute } from "vue-router";
import { decoders as d, decode, describeApiError, type ApiError } from "@/api";
import { ApButton, ApCallout, ApField } from "@/ui";
import {
  acceptInvitation,
  declineInvitation,
  fetchInvitation,
  goTo,
  optionalSession,
  signOutHere,
  unavailableReader,
  type AcceptBody,
  type Invitation,
} from "./api.ts";
import { retryAfterOf, useRetryAfter } from "./retry-after.ts";
import {
  invitationHeader,
  invitationView,
  UNKNOWN_INVITATION,
  WRONG_CREDENTIALS,
} from "./words.ts";

/**
 * Invitation link (ux Auth.md), signed out or in: the server's `case` picks the form (create an
 * account, sign in, join, or the right account's callout) or says why it can't be used. Accepting
 * follows the server's redirect_to with a full navigation.
 */
const route = useRoute("auth.invitation");
const token = computed(() => String(route.params.token ?? ""));
const invitation = shallowRef<Invitation | null>(null);
const unknown = ref(false);
const loadError = ref<string | null>(null);
const signedInAs = ref<string | null>(null);
const csrf = ref<string | null>(null);

const name = ref("");
const password = ref("");
const confirm = ref("");
const busy = ref(false);
const error = ref<{ tone: "crit" | "caution"; text: string } | null>(null);
const declining = ref(false);
const declined = ref(false);
const retry = useRetryAfter();

/** 422 invalid_params `details.name` / `details.password`: the server's sentences, joined. */
const paramsReader = d.object({
  name: d.optional(d.array(d.string, 10)),
  password: d.optional(d.array(d.string, 10)),
});
function paramsWords(details: unknown): string | null {
  const r = decode(paramsReader, details);
  if (!r.ok) return null;
  const all = [...(r.value.name ?? []), ...(r.value.password ?? [])];
  return all.length ? all.join(" ") : null;
}

/** `invitation_unavailable {case, …}`: the screen for why, from what the server says. */
function fromUnavailable(e: ApiError): Invitation | null {
  if (!("code" in e) || e.code !== "invitation_unavailable" || !("details" in e)) return null;
  const r = decode(unavailableReader, e.details);
  if (!r.ok) return null;
  const v = r.value;
  return {
    case: v.case,
    organization: v.organization ?? { id: "", name: "this organization" },
    role: v.role ?? null,
    invited_by: v.invited_by ?? null,
    invited_at: v.invited_at ?? null,
    email: v.email ?? "",
    expires_at: v.expires_at ?? null,
    withdrawn_by: v.withdrawn_by,
  };
}

async function load() {
  const [inv, session] = await Promise.all([fetchInvitation(token.value), optionalSession()]);
  if (session.ok && session.value) {
    signedInAs.value = session.value.user.email;
    csrf.value = session.value.csrf_token;
  }
  if (inv.ok) invitation.value = inv.value;
  else if (inv.error.kind === "not_found") unknown.value = true;
  else {
    const gone = fromUnavailable(inv.error);
    if (gone) invitation.value = gone;
    else loadError.value = describeApiError(inv.error);
  }
}
onMounted(() => void load());

const view = computed(() =>
  invitation.value ? invitationView(invitation.value, signedInAs.value) : null,
);
const formError = computed(() => {
  const i = invitation.value;
  if (i?.case !== "new_account") return null;
  if (!name.value.trim()) return "Enter your name.";
  if (password.value.length < 12) return "The password needs at least 12 characters.";
  if (password.value !== confirm.value) return "The passwords don't match.";
  return null;
});

async function accept() {
  const i = invitation.value;
  if (!i || busy.value || retry.blocked.value || formError.value) return;
  const body: AcceptBody =
    i.case === "new_account"
      ? { kind: "new_account", name: name.value.trim(), password: password.value }
      : i.case === "existing_account"
        ? { kind: "existing_account", password: password.value }
        : { kind: "signed_in_match" };
  busy.value = true;
  error.value = null;
  const r = await acceptInvitation(token.value, body);
  busy.value = false;
  if (r.ok) return goTo(r.value.redirect_to);
  const wait = retryAfterOf(r.error);
  if (wait !== null) return retry.block(wait);
  const e = r.error;
  if (e.kind === "invalid" && e.code === "credentials_incorrect")
    error.value = { tone: "crit", text: WRONG_CREDENTIALS };
  else if (e.kind === "invalid" && e.code === "invalid_params")
    error.value = { tone: "caution", text: paramsWords(e.details) ?? describeApiError(e) };
  else if (e.kind === "forbidden")
    error.value = {
      tone: "crit",
      text: "This account is disabled. Ask an organization admin for help.",
    };
  else if (
    "code" in e &&
    (e.code === "invitation_unavailable" ||
      e.code === "invitation_for_another_account" ||
      e.code === "invitation_case_changed")
  )
    // Someone signed in or out meanwhile, or it's gone: the server's case picks the form again.
    await load();
  else error.value = { tone: "caution", text: describeApiError(e) };
}
async function decline() {
  busy.value = true;
  const r = await declineInvitation(token.value);
  busy.value = false;
  if (r.ok) declined.value = true;
  else error.value = { tone: "caution", text: describeApiError(r.error) };
}
const run = (f: () => Promise<void>) => () => f().catch((e: unknown) => console.error(e));
const reason = computed(
  () => retry.text.value ?? formError.value ?? (busy.value ? "Working…" : null),
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <ApCallout v-if="loadError" tone="caution">{{ loadError }}</ApCallout>
    <template v-else-if="unknown">
      <ApCallout tone="off">{{ UNKNOWN_INVITATION }}</ApCallout>
      <ApButton variant="primary" class="w-full" :to="{ name: 'auth.sign-in' }">Sign in</ApButton>
    </template>
    <p v-else-if="!invitation" class="m-0 font-mono text-sm text-text-3" role="status">
      Reading the invitation…
    </p>
    <template v-else-if="declined">
      <h1 class="m-0 font-display text-[24px] font-semibold tracking-head uppercase">Declined</h1>
      <p class="m-0 text-text-2">
        You declined the invitation to {{ invitation.organization.name }}.
      </p>
      <ApButton variant="secondary" class="w-full" @click="goTo('/console/')"
        >Continue to Cadence</ApButton
      >
    </template>
    <template v-else-if="view">
      <h1 v-if="view.h1" class="m-0 font-display text-[24px] font-semibold tracking-head uppercase">
        {{ view.h1 }}
      </h1>
      <p class="m-0 text-text-2">{{ invitationHeader(invitation) }}</p>
      <ApCallout v-if="view.callout" :tone="view.callout.tone">{{ view.callout.text }}</ApCallout>
      <ApCallout v-if="retry.text.value" tone="caution">{{ retry.text.value }}</ApCallout>
      <ApCallout v-else-if="error" :tone="error.tone">{{ error.text }}</ApCallout>

      <form
        v-if="invitation.case === 'new_account' || invitation.case === 'existing_account'"
        class="flex flex-col gap-3"
        @submit.prevent="run(accept)()"
      >
        <ApField
          v-if="invitation.case === 'new_account'"
          v-model="name"
          label="Name"
          autocomplete="name"
          required
        />
        <ApField
          :model-value="invitation.email"
          label="Email"
          type="email"
          autocomplete="username"
          disabled
        />
        <ApField
          v-model="password"
          label="Password"
          type="password"
          :autocomplete="invitation.case === 'new_account' ? 'new-password' : 'current-password'"
          :hint="invitation.case === 'new_account' ? 'At least 12 characters.' : undefined"
          required
        />
        <ApField
          v-if="invitation.case === 'new_account'"
          v-model="confirm"
          label="Confirm password"
          type="password"
          autocomplete="new-password"
          required
        />
        <ApButton
          type="submit"
          variant="primary"
          class="w-full"
          :disabled="reason !== null"
          :disabled-reason="reason ?? undefined"
          >{{
            invitation.case === "new_account" ? "Create account and join" : "Sign in and join"
          }}</ApButton
        >
      </form>

      <template v-else-if="invitation.case === 'signed_in_match'">
        <ApButton
          variant="primary"
          class="w-full"
          :disabled="busy"
          disabled-reason="Working…"
          @click="run(accept)()"
          >Join</ApButton
        >
        <ApButton v-if="!declining" variant="secondary" class="w-full" @click="declining = true"
          >Decline</ApButton
        >
        <div v-else class="flex flex-col gap-2">
          <p class="m-0 text-text-2">
            Decline the invitation to {{ invitation.organization.name }}?
          </p>
          <ApButton variant="danger" class="w-full" :disabled="busy" @click="run(decline)()"
            >Decline the invitation</ApButton
          >
          <ApButton variant="ghost" class="w-full" @click="declining = false">Keep it</ApButton>
        </div>
      </template>

      <ApButton
        v-else-if="invitation.case === 'signed_in_other'"
        variant="primary"
        class="w-full"
        @click="run(() => signOutHere(csrf))()"
        >Sign out and continue</ApButton
      >
      <ApButton
        v-else-if="['accepted', 'used', 'unrecognized'].includes(invitation.case)"
        variant="primary"
        class="w-full"
        :to="{ name: 'auth.sign-in' }"
        >Sign in</ApButton
      >
    </template>
  </div>
</template>
