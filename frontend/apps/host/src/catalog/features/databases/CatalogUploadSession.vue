<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, provide, ref, watch } from "vue";
import {
  catalogUploadKey,
  type CatalogUploadCancel,
  type CatalogUploadSession,
} from "./upload-contract";
import { nativeUpload } from "./native-upload";

const props = defineProps<{
  session: CatalogUploadSession;
  cancel: CatalogUploadCancel;
  navigate: (href: string) => void;
}>();
const busy = ref(false);
const localError = ref<string | null>(null);
const error = computed(() => localError.value || props.session.error);
watch(
  () => props.session.attempt,
  () => {
    busy.value = false;
  },
);
function safely(action: () => void) {
  try {
    localError.value = null;
    action();
  } catch {
    busy.value = false;
    localError.value = "The upload connection changed. Reopen this page and try again.";
  }
}
provide(catalogUploadKey, {
  busy,
  error,
  validate(values) {
    if (busy.value) return;
    safely(() => {
      const { form } = nativeUpload(props.session, values);
      const field = form.elements.namedItem("catalog_upload[revision_label]") as HTMLInputElement;
      field.dispatchEvent(new Event("change", { bubbles: true }));
    });
  },
  select(files, values) {
    if (busy.value) return;
    safely(() => {
      const { file } = nativeUpload(props.session, values);
      const transfer = new DataTransfer();
      files.forEach((item) => transfer.items.add(item));
      file.files = transfer.files;
      file.dispatchEvent(new Event("change", { bubbles: true }));
    });
  },
  submit(values) {
    if (busy.value) return;
    safely(() => {
      const { form } = nativeUpload(props.session, values);
      busy.value = true;
      form.requestSubmit();
    });
  },
  cancel(ref) {
    safely(() => {
      props.cancel({
        catalog_upload: { path: props.session.path, token: props.session.token },
        ref,
      });
      busy.value = false;
    });
  },
});
function uploaded(event: Event) {
  const result = (event as CustomEvent).detail;
  if (
    result?.path === props.session.path &&
    result.token === props.session.token &&
    typeof result.href === "string" &&
    result.href.startsWith(`${props.session.path.split("/catalog")[0]}/catalog/imports/`)
  ) {
    busy.value = false;
    props.navigate(result.href);
  }
}
function disconnected() {
  if (!busy.value) return;
  busy.value = false;
  localError.value = "The connection was interrupted. Check the import history before retrying.";
}
onMounted(() => {
  window.addEventListener("phx:catalog:uploaded", uploaded);
  window.addEventListener("offline", disconnected);
  window.addEventListener("cadence:transport-reconnected", disconnected);
});
onBeforeUnmount(() => {
  window.removeEventListener("phx:catalog:uploaded", uploaded);
  window.removeEventListener("offline", disconnected);
  window.removeEventListener("cadence:transport-reconnected", disconnected);
});
</script>
<template><slot /></template>
