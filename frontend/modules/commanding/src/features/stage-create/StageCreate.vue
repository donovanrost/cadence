<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, shallowRef } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import { createInput, readCreationPage, type CreationPage } from "./contracts";
import { readWriteResult, type Operation } from "../../shared/stages/operations";
import { stagesHref } from "../../shared/stages/links";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: CreationPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const creation = props.page.creation,
  context = { ...creation.context },
  actor = creation.actor_id,
  stageId = creation.stage_id;
const token = ref(props.page.write_token),
  operation = shallowRef<Operation | null>(props.page.operation),
  busy = ref(false),
  reading = ref(false),
  feedback = ref("");
const form = reactive({ name: "", description: "", visibility: "private" });
const locked = computed(
  () => busy.value || reading.value || token.value === null || operation.value !== null,
);
let disposed = false;
const unguard = props.port.guardNavigation?.(() => !busy.value && !reading.value);
onBeforeUnmount(() => {
  disposed = true;
  unguard?.();
});
function follow(event: MouseEvent, href: string) {
  if (!event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey && event.button === 0) {
    event.preventDefault();
    if (!busy.value && !reading.value) props.port.navigate(href);
  }
}
async function create() {
  if (locked.value || !token.value) return;
  let input;
  try {
    input = createInput(token.value, form.name, form.description, form.visibility);
  } catch (error) {
    feedback.value = String((error as Error).message);
    return;
  }
  const expected = token.value;
  busy.value = true;
  feedback.value = "";
  operation.value = { status: "unconfirmed", write_token: expected, event: "create" };
  try {
    const result = readWriteResult(
      await props.port.execute("create", input),
      actor,
      stageId,
      expected,
      "create",
    );
    if (disposed) return;
    if ("write_token" in result) operation.value = result;
    else {
      operation.value = null;
      feedback.value = result.feedback;
    }
  } catch {
    if (!disposed)
      feedback.value =
        "The reply was lost. Check the creation result before starting another stage.";
  } finally {
    if (!disposed) busy.value = false;
  }
}
async function refresh() {
  if (busy.value || reading.value) return;
  reading.value = true;
  feedback.value = "";
  try {
    const next = readCreationPage(await props.readPort.read(), context);
    if (next.creation.actor_id !== actor || next.creation.stage_id !== stageId) throw Error();
    if (
      operation.value &&
      (!next.operation || next.operation.write_token !== operation.value.write_token)
    )
      throw Error();
    if (!disposed) {
      operation.value = next.operation;
      token.value = next.write_token;
    }
  } catch {
    if (!disposed)
      feedback.value =
        "The creation result could not be confirmed. Inspect the stage directory before creating another stage.";
  } finally {
    if (!disposed) reading.value = false;
  }
}
useOpsHeader("/missions/:mission_id/ops/commands/stages/new", {
  description:
    "A stage holds editable command drafts. You will review and submit them as formal requests separately.",
});
</script>
<template>
  <CadenceOpsViewport id="stage-create">
    <CadenceOpsListBodyFrame>
      <p v-if="feedback" id="stage-create-feedback" role="alert" class="text-sm text-warning">
        {{ feedback }}
      </p>
      <form
        v-if="!operation"
        id="stage-create-form"
        class="max-w-2xl space-y-5"
        @submit.prevent="create"
      >
        <fieldset :disabled="locked" class="space-y-5">
          <label class="block space-y-2 text-sm"
            >Stage name<input
              id="stage-create-name"
              v-model="form.name"
              required
              maxlength="240"
              class="input input-bordered w-full"
              autocomplete="off"
          /></label>
          <label class="block space-y-2 text-sm"
            >Description<textarea
              id="stage-create-description"
              v-model="form.description"
              maxlength="4000"
              rows="4"
              class="textarea textarea-bordered w-full"
            />
          </label>
          <fieldset class="space-y-3">
            <legend class="mb-2 text-sm font-semibold">Who can see this stage?</legend>
            <label class="flex gap-3 border border-base-300 bg-base-100 p-4"
              ><input
                id="stage-create-private"
                name="stage-visibility"
                v-model="form.visibility"
                type="radio"
                value="private"
                class="radio radio-sm"
              /><span
                ><strong class="block text-sm">Private</strong
                ><span class="text-xs text-base-content/60"
                  >Only you can view and edit these drafts.</span
                ></span
              ></label
            ><label class="flex gap-3 border border-base-300 bg-base-100 p-4"
              ><input
                id="stage-create-shared"
                name="stage-visibility"
                v-model="form.visibility"
                type="radio"
                value="shared"
                class="radio radio-sm"
              /><span
                ><strong class="block text-sm">Shared</strong
                ><span class="text-xs text-base-content/60"
                  >Mission managers can edit and submit drafts. You retain control of the stage name
                  and visibility.</span
                ></span
              ></label
            >
          </fieldset>
          <button id="stage-create-submit" class="btn btn-primary" :disabled="locked">
            {{ busy ? "Creating…" : "Create stage" }}
          </button>
        </fieldset>
      </form>
      <section
        v-if="operation"
        id="stage-create-result"
        aria-live="polite"
        class="max-w-2xl border border-base-300 bg-base-100 p-5 space-y-3"
      >
        <template v-if="operation.status === 'completed'"
          ><h2 class="font-semibold">Command stage created</h2>
          <p class="text-sm">{{ operation.receipt.name }} · {{ operation.receipt.visibility }}</p>
          <a
            id="stage-create-open"
            :href="stagesHref(context.missionId, stageId)"
            class="btn btn-primary btn-sm"
            @click="follow($event, stagesHref(context.missionId, stageId))"
            >Open stage</a
          ></template
        ><template v-else-if="operation.status === 'rejected'"
          ><h2 class="font-semibold">Stage not created</h2>
          <p class="text-sm">{{ operation.feedback }}</p>
          <p class="text-xs text-base-content/60">
            Return to the directory to begin a new stage.
          </p></template
        ><template v-else
          ><h2 class="font-semibold">Creation result unconfirmed</h2>
          <p class="text-sm">Check the result without repeating the write.</p>
          <a
            :href="stagesHref(context.missionId, stageId)"
            class="text-sm underline"
            @click="follow($event, stagesHref(context.missionId, stageId))"
            >Inspect the reserved stage</a
          ></template
        >
        <p class="font-mono break-all text-xs text-base-content/60">{{ stageId }}</p>
      </section>
      <button
        id="stage-create-refresh"
        class="btn btn-ghost btn-sm"
        :disabled="busy || reading"
        @click="refresh"
      >
        {{ reading ? "Checking…" : "Check creation result" }}
      </button>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
