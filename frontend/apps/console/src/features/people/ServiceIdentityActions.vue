<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { ref } from "vue";
import { useRouter } from "vue-router";
import { ApButton, ApCallout, ApInlineConfirm, ApPanel } from "@/ui";
import TokenOnce from "./TokenOnce.vue";
import { revokeServiceIdentity, rotateServiceIdentity, serviceFailure } from "./services.ts";

/**
 * U3 detail · Rotate key / Revoke (O6), each confirmed in place with the kit's ApInlineConfirm
 * (design-language §7; one open at a time). A rotated token is shown once.
 */
const props = defineProps<{ orgId: OrganizationId; id: string; name: string }>();
const emit = defineEmits<{ changed: [] }>();
const router = useRouter();
const rotating = ref(false);
const revoking = ref(false);
const busy = ref(false);
const token = ref<string | null>(null);
const failure = ref<string | null>(null);

async function rotate() {
  busy.value = true;
  failure.value = null;
  try {
    const r = await rotateServiceIdentity(props.orgId, props.id);
    if (r.ok) {
      token.value = r.value.api_token;
      rotating.value = false;
    } else failure.value = serviceFailure(r.error).text;
    emit("changed");
  } finally {
    busy.value = false;
  }
}

async function revoke() {
  busy.value = true;
  failure.value = null;
  try {
    const r = await revokeServiceIdentity(props.orgId, props.id);
    if (r.ok) return void router.push({ name: "org.people", query: { tab: "services" } });
    failure.value = serviceFailure(r.error).text;
    emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="U3.2" title="Key">
    <div class="flex flex-col gap-4">
      <template v-if="token">
        <ApCallout tone="nominal">Rotated. The old token stopped working.</ApCallout>
        <TokenOnce :token="token" />
      </template>
      <div class="flex flex-wrap items-center gap-3">
        <ApInlineConfirm
          v-model:open="rotating"
          action="Rotate key"
          :danger="false"
          :busy="busy"
          busy-reason="Rotating…"
          :refusal="rotating ? failure : null"
          @confirm="rotate"
          @cancel="failure = null"
        >
          <template #trigger="{ attrs }"><ApButton v-bind="attrs">Rotate key…</ApButton></template>
          Rotate {{ name }}'s key? The current token stops working immediately; anything using it
          fails until it has the new one. The new token is shown once.
        </ApInlineConfirm>
        <ApInlineConfirm
          v-model:open="revoking"
          :action="`Revoke ${name}`"
          :busy="busy"
          busy-reason="Revoking…"
          :refusal="revoking ? failure : null"
          @confirm="revoke"
          @cancel="failure = null"
        >
          <template #trigger="{ attrs }">
            <ApButton variant="ghost" v-bind="attrs">Revoke…</ApButton>
          </template>
          Revoke {{ name }}? It's disabled and its token stops working. This can't be undone.
        </ApInlineConfirm>
      </div>
    </div>
  </ApPanel>
</template>
