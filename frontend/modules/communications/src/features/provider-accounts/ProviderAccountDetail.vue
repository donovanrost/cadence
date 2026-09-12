<script setup lang="ts">
import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import ProviderAccountShow from "./ProviderAccountShow.vue";
import {
  AccountActionFailure,
  type AccountDetailAction,
  type AccountDetailPort,
} from "./detail-port";
import {
  accountActionIdentity,
  grantReady,
  readAccountUpdate,
  readAccountPatch,
  readGrantValues,
  type AccountDetailModel,
} from "./detail.validation";
import type { GrantValues } from "./detail.contracts";
const props = defineProps<{
  model: AccountDetailModel;
  port: AccountDetailPort;
  initiallyLocked?: boolean;
}>();
const model = shallowRef(props.model);
const draft = ref<GrantValues>({ ...props.model.grant_form.values });
const pending = ref(false),
  locked = ref(props.initiallyLocked ?? false),
  message = ref<string | null>(null);
let generation = 0,
  disposed = false;
watch(
  () => [props.model, props.port],
  () => {
    ++generation;
    model.value = props.model;
    draft.value = { ...props.model.grant_form.values };
    pending.value = false;
    locked.value = props.initiallyLocked ?? false;
    message.value = null;
  },
  { flush: "sync" },
);
onBeforeUnmount(() => {
  disposed = true;
  ++generation;
});
const view = computed(() => {
  const { account: _account, ...view } = model.value;
  return {
    ...view,
    grant_form: { ...view.grant_form, values: { ...draft.value } },
    actions: {
      validate: {
        ...view.actions.validate,
        disabled: pending.value || locked.value || view.actions.validate.disabled,
      },
      rotate: {
        ...view.actions.rotate,
        disabled: pending.value || locked.value || view.actions.rotate.disabled,
      },
      revoke: view.actions.revoke
        ? {
            ...view.actions.revoke,
            disabled: pending.value || locked.value || view.actions.revoke.disabled,
          }
        : null,
    },
  };
});
function update(input: { grant: GrantValues }) {
  if (!pending.value && !locked.value) draft.value = readGrantValues(input.grant);
}
function allowed(action: AccountDetailAction, input: Record<string, unknown>) {
  if (action === "validate-account") return !model.value.actions.validate.disabled;
  if (action === "rotate-credential") return !model.value.actions.rotate.disabled;
  if (action === "revoke-credential")
    return model.value.actions.revoke && !model.value.actions.revoke.disabled;
  if (action === "grant-mission") return grantReady(model.value, readGrantValues(input.grant));
  return model.value.account_grants.some(
    (grant) => grant.id === input["grant-id"] && grant.revoke !== null,
  );
}
async function run(action: AccountDetailAction, input: Record<string, unknown> = {}) {
  if (disposed || pending.value || locked.value || !allowed(action, input)) return;
  const previous = model.value,
    current = ++generation;
  const grant =
    action === "revoke-grant"
      ? model.value.account_grants.find((grant) => grant.id === input["grant-id"])
      : undefined;
  const payload = {
    ...input,
    ...accountActionIdentity(previous.account),
    ...(grant ? { expected_grant_version: grant.version } : {}),
  };
  pending.value = true;
  message.value = null;
  try {
    const receipt = await props.port.execute(action, payload);
    if (disposed || generation !== current) return;
    const next = readAccountPatch(receipt, previous);
    if (
      action === "rotate-credential" &&
      next.account.credential_version <= previous.account.credential_version
    )
      throw new Error("Rotation not observed");
    if (
      action === "revoke-credential" &&
      (next.account.credential_status !== "revoked" ||
        next.account.credential_version <= previous.account.credential_version)
    )
      throw new Error("Revocation not observed");
    if (
      action === "grant-mission" &&
      !next.account_grants.some(
        (grant) =>
          grant.mission_id === readGrantValues(input.grant).mission_id &&
          grant.account_version === previous.account.version &&
          grant.lifecycle.status === "ready",
      )
    )
      throw new Error("Grant not observed");
    if (
      action === "revoke-grant" &&
      !next.account_grants.some(
        (item) =>
          grant &&
          item.id === grant.id &&
          item.version > grant.version &&
          item.lifecycle.status === "blocked",
      )
    )
      throw new Error("Grant revocation not observed");
    // Only the submitted grant draft is cleared. Unrelated account actions preserve it.
    if (action === "grant-mission") draft.value = { ...next.grant_form.values };
    model.value = next;
    message.value = "The account action completed.";
  } catch (reason) {
    if (disposed || generation !== current) return;
    const rejected = reason instanceof AccountActionFailure && reason.outcome === "rejected";
    locked.value = !rejected;
    message.value = rejected
      ? "The action was rejected. Your draft is still here. Refresh the account before trying again."
      : "The action outcome could not be confirmed. Refresh to inspect the account; the action will not be repeated.";
  } finally {
    if (!disposed && generation === current) pending.value = false;
  }
}
async function refresh() {
  if (disposed || pending.value) return;
  const current = ++generation,
    previous = model.value;
  pending.value = true;
  message.value = null;
  try {
    const response = await props.port.query();
    if (disposed || generation !== current) return;
    const next = readAccountUpdate(response, previous);
    model.value = next;
    message.value = locked.value
      ? "Account refreshed. Review the records before leaving this page; uncertain actions remain locked."
      : "Account refreshed.";
  } catch {
    if (!disposed && generation === current)
      message.value =
        "The account could not be refreshed. Your current page and draft remain available.";
  } finally {
    if (!disposed && generation === current) pending.value = false;
  }
}
</script>
<template>
  <div>
    <fieldset class="contents" :disabled="pending || locked">
      <ProviderAccountShow
        v-bind="view"
        :can-grant="!pending && !locked && grantReady(model, draft)"
        :actions-disabled="pending || locked"
        @draft-change="update"
        @validate-account="run('validate-account')"
        @rotate-credential="run('rotate-credential')"
        @revoke-credential="run('revoke-credential')"
        @grant-mission="run('grant-mission', $event)"
        @revoke-grant="run('revoke-grant', $event)"
      />
    </fieldset>
    <div id="provider-account-detail-feedback" class="mt-4 flex items-center gap-3">
      <p
        id="provider-account-detail-status"
        role="status"
        aria-live="polite"
        class="text-sm text-base-content/70"
      >
        {{ pending ? "Waiting for the account operation…" : message }}
      </p>
      <button
        id="refresh-provider-account"
        type="button"
        class="btn btn-sm btn-ghost"
        :disabled="pending"
        @click="refresh"
      >
        Refresh account
      </button>
      <a v-if="locked" id="provider-account-return" href="/provider-accounts" class="btn btn-sm"
        >Provider accounts</a
      >
    </div>
  </div>
</template>
