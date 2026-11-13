<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { decoders as d, detailsOf, fieldErrors, orNull } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApSheet } from "@/ui";
import { checkSlug, createOrganization } from "./api.ts";
import { createdText, slugOf } from "./present.ts";

/** Create organization (Admin.md): name, slug (filled from the name, live check), first admin email. */
const emit = defineEmits<{ created: [note: { tone: "nominal" | "caution"; text: string }] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const name = ref("");
const slug = ref("");
const slugEdited = ref(false);
const email = ref("");
const taken = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
watch(name, (n) => {
  if (!slugEdited.value) slug.value = slugOf(n);
});
let controller: AbortController | null = null;
watch(slug, async (s) => {
  taken.value = null;
  controller?.abort();
  if (!s) return;
  controller = new AbortController();
  const r = await checkSlug(s, controller.signal);
  if (r.ok && !r.value.available)
    taken.value = `${s} is taken${r.value.suggestion ? `; ${r.value.suggestion} is free` : ""}.`;
});
const blocked = computed(() =>
  !name.value.trim() || !slug.value || !email.value.includes("@")
    ? "Fill in all three."
    : taken.value
      ? "Choose another slug."
      : busy.value
        ? "Creating…"
        : null,
);
function open() {
  name.value = slug.value = email.value = "";
  slugEdited.value = false;
  failure.value = taken.value = null;
  sheet.value?.open();
}
async function submit() {
  if (blocked.value) return;
  busy.value = true;
  try {
    const r = await createOrganization({
      name: name.value.trim(),
      slug: slug.value,
      first_admin_email: email.value.trim(),
    });
    if (!r.ok) {
      // api-ops: a slug clash is 422 details.slug plus a free suggestion.
      const slugError = fieldErrors(r.error)["slug"];
      const hint = detailsOf(r.error, d.object({ suggestion: orNull(d.string) }))?.suggestion;
      if (slugError) return void (taken.value = hint ? `${slugError} ${hint} is free.` : slugError);
      return void (failure.value = failureOutcome(r.error, "changed").sentence);
    }
    sheet.value?.close();
    emit("created", createdText(r.value));
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Create organization" initial-focus="input">
    <form class="flex flex-col gap-3" @submit.prevent="submit">
      <ApField v-model="name" label="Name" required />
      <ApField
        :model-value="slug"
        label="Slug"
        mono
        :error="taken"
        @update:model-value="((slugEdited = true), (slug = $event))"
      />
      <ApField
        v-model="email"
        label="First admin email"
        type="email"
        hint="They're invited as org admin."
      />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="submit"
        >Create and invite</ApButton
      >
    </template>
  </ApSheet>
</template>
