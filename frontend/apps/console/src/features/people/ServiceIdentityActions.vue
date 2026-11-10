<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { ApButton, ApCallout, ApPanel } from "@/ui";
import TokenOnce from "./TokenOnce.vue";
import { revokeServiceIdentity, rotateServiceIdentity, serviceFailure } from "./services.ts";

/** U3 detail · Rotate key / Revoke (O6), both two-step. A rotated token is shown once. */
const props = defineProps<{ orgId: string; id: string; name: string }>();
const emit = defineEmits<{ changed: [] }>();
const router = useRouter();
const confirm = ref<"rotate" | "revoke" | null>(null);
const busy = ref(false);
const token = ref<string | null>(null);
const failure = ref<string | null>(null);

async function rotate() {
  busy.value = true;
  failure.value = null;
  try {
    const r = await rotateServiceIdentity(props.orgId, props.id);
    if (r.ok) token.value = r.value.api_token;
    else failure.value = serviceFailure(r.error).text;
    confirm.value = null;
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
      <p v-if="confirm === 'rotate'" class="m-0 text-md text-text-2">
        The current token stops working immediately. Anything using it fails until it has the new
        one.
      </p>
      <p v-if="confirm === 'revoke'" class="m-0 text-md text-text-2">
        {{ name }} is disabled and its token stops working. This can't be undone.
      </p>
      <ApCallout v-if="failure" tone="caution">{{ failure }}</ApCallout>
      <div class="flex flex-wrap items-center gap-3">
        <template v-if="confirm === null">
          <ApButton @click="confirm = 'rotate'">Rotate key…</ApButton>
          <ApButton variant="ghost" @click="confirm = 'revoke'">Revoke…</ApButton>
        </template>
        <template v-else>
          <ApButton
            :variant="confirm === 'revoke' ? 'danger' : 'primary'"
            :disabled="busy"
            disabled-reason="Working…"
            @click="confirm === 'revoke' ? revoke() : rotate()"
            >{{
              confirm === "revoke" ? `Revoke ${name}` : "Rotate and show the new token"
            }}</ApButton
          >
          <ApButton variant="ghost" @click="confirm = null">Cancel</ApButton>
        </template>
      </div>
    </div>
  </ApPanel>
</template>
