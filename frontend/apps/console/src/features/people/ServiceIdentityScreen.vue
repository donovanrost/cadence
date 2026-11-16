<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import {
  ApBreadcrumb,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApStatusMark,
  formatShort,
  useNow,
} from "@/ui";
import ServiceIdentityActions from "./ServiceIdentityActions.vue";
import { fetchServiceIdentities, keyAgeWarning } from "./api.ts";

/** U3 · Service identity detail (O3 read + O6 rotate / revoke). */
const scope = useConsoleScope();
const route = useRoute("org.people.service");
const now = useNow();
const org = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const id = computed(() => String(route.params.serviceId ?? ""));
const { state, refetch } = useRemoteQuery(() => org.value?.id ?? null, fetchServiceIdentities);
const identity = computed(() =>
  state.value.status === "ready"
    ? (state.value.value.service_identities.find((s) => s.id === id.value) ?? null)
    : null,
);
const warning = computed(() =>
  state.value.status === "ready" && identity.value
    ? keyAgeWarning(
        identity.value.key_created_at,
        state.value.value.rotation_policy_days,
        now.value,
      )
    : null,
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[900px] flex-col gap-4">
    <ApBreadcrumb
      :crumbs="[
        { label: 'People & access', to: { name: 'org.people', query: { tab: 'services' } } },
        { label: identity?.name ?? 'Service identity', literal: true },
      ]"
    />
    <ApRemote
      forbidden-text="Org admins see this."
      :state="state"
      loading-label="Loading service identity…"
      @retry="refetch"
    >
      <ApEmptyState
        v-if="!identity"
        state="off"
        headline="This service identity isn't active"
        sentence="It was revoked, or never existed here. Open People & access › Service identities for the list."
      />
      <template v-else>
        <ApPageHeader label="Service identity" :title="identity.name" size="reading" />
        <ApPanel index="U3.1" title="Access">
          <p class="m-0 text-md text-text-2">
            {{ identity.scope_summary }} · key created
            <span class="font-mono">{{
              identity.key_created_at ? formatShort(new Date(identity.key_created_at)) : "—"
            }}</span>
          </p>
          <!-- a11y B2: the caution mark, as the list has it, so the warning isn't colour alone. -->
          <p v-if="warning" class="m-0 mt-2 flex items-center gap-2 text-sm text-caution-text">
            <ApStatusMark state="caution" />{{ warning }}
          </p>
        </ApPanel>
        <ServiceIdentityActions
          v-if="org"
          :org-id="org.id"
          :id="identity.id"
          :name="identity.name"
          @changed="refetch"
        />
      </template>
    </ApRemote>
  </div>
</template>
