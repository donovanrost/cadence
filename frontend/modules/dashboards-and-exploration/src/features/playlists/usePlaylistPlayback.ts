import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { Presentation } from "./contracts";
export function usePlaylistPlayback(props: { model: Presentation; port: OpsPagePort }) {
  const playing = ref(props.model.playing),
    advancing = ref(false);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const base = computed(
    () => `/missions/${encodeURIComponent(props.model.mission_id)}/ops/dashboards`,
  );
  function clear() {
    if (timer !== undefined) clearTimeout(timer);
    timer = undefined;
  }
  function href(index: number) {
    return `${base.value}/playlists/${encodeURIComponent(props.model.playlist.id)}/present?index=${index}&playing=${playing.value ? "1" : "0"}`;
  }
  function step(delta: number) {
    if (advancing.value) return;
    clear();
    advancing.value = true;
    props.port.navigate(href((props.model.index + delta + props.model.total) % props.model.total));
  }
  function arm() {
    clear();
    if (playing.value && !advancing.value && document.visibilityState !== "hidden")
      timer = setTimeout(() => step(1), props.model.playlist.dwell_seconds * 1000);
  }
  function toggle() {
    playing.value = !playing.value;
    arm();
  }
  function visibility() {
    if (document.visibilityState === "hidden") {
      playing.value = false;
      clear();
    }
  }
  watch(
    () => props.model,
    () => {
      advancing.value = false;
      arm();
    },
  );
  onMounted(() => {
    visibility();
    arm();
    document.addEventListener("visibilitychange", visibility);
  });
  onBeforeUnmount(() => {
    clear();
    document.removeEventListener("visibilitychange", visibility);
  });
  function navigate(e: MouseEvent, path: string) {
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    props.port.navigate(path);
  }
  return { playing, advancing, base, step, toggle, navigate };
}
