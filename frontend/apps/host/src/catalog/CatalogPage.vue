<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import { catalogPages } from "./pages";
import { record } from "./shared/validation";
import CatalogUploadSession from "./features/databases/CatalogUploadSession.vue";
import {
  isCatalogUploadSession,
  type CatalogUploadCancel,
} from "./features/databases/upload-contract";

const props = defineProps<{
  page: string;
  snapshot: unknown;
  execute: (event: "reimport") => Promise<void>;
  refresh: () => Promise<void>;
  cancelUpload?: CatalogUploadCancel;
  navigate?: (href: string) => void;
}>();
const crashed = ref(false);
const busy = ref(false);
const actionError = ref(false);
watch(
  () => props.snapshot,
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => {
  const snapshot = props.snapshot;
  if (
    !Object.hasOwn(catalogPages, props.page) ||
    !record(snapshot) ||
    snapshot.page !== props.page ||
    snapshot.version !== 1 ||
    snapshot.status !== "ready" ||
    !record(snapshot.data)
  )
    return null;
  const registration = catalogPages[props.page]!;
  try {
    if (snapshot.upload_session !== undefined && !isCatalogUploadSession(snapshot.upload_session))
      return null;
    registration.validate(snapshot.data);
    return {
      component: registration.component,
      data: snapshot.data,
      uploadSession: isCatalogUploadSession(snapshot.upload_session)
        ? snapshot.upload_session
        : null,
    };
  } catch {
    return null;
  }
});
async function reimport() {
  if (busy.value || props.page !== "catalog_artifact_show") return;
  busy.value = true;
  actionError.value = false;
  try {
    await props.execute("reimport");
  } catch {
    actionError.value = true;
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section id="core-catalog-page" :aria-busy="busy">
    <div
      v-if="crashed || !admitted"
      id="core-catalog-error"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This Catalog page is unavailable.</p>
      <button id="core-catalog-retry" type="button" class="btn btn-sm mt-4" @click="refresh">
        Retry
      </button>
    </div>
    <template v-else>
      <p v-if="busy" id="core-catalog-action-pending" role="status">
        Requesting the Catalog import…
      </p>
      <p v-if="actionError" id="core-catalog-action-error" role="alert">
        The import could not be requested. Try again.
      </p>
      <CatalogUploadSession
        v-if="admitted.uploadSession && cancelUpload && navigate"
        :key="admitted.uploadSession.token"
        :session="admitted.uploadSession"
        :cancel="cancelUpload"
        :navigate="navigate"
      >
        <component :is="admitted.component" v-bind="admitted.data" />
      </CatalogUploadSession>
      <component v-else :is="admitted.component" v-bind="admitted.data" @reimport="reimport" />
    </template>
  </section>
</template>
