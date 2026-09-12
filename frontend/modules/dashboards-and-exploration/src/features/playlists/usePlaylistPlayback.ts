import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import type { SettledOpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import type { Presentation } from "./contracts";
export function usePlaylistPlayback(props: {
  model: Presentation;
  port: SettledOpsPageNavigationPort;
}) {
  const playing = ref(props.model.playing),
    advancing = ref(false);
  const notice = ref("");
  let active = true,
    generation = 0;
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
  async function step(delta: number) {
    if (advancing.value) return;
    clear();
    if (props.model.total === 1) {
      arm();
      return;
    }
    const current = ++generation;
    advancing.value = true;
    notice.value = "";
    try {
      const result = await props.port.navigate(
        href((props.model.index + delta + props.model.total) % props.model.total),
      );
      if (active && generation === current && result !== "completed") {
        playing.value = false;
        notice.value = "The entry did not change. Playback is paused; use Next or Play to retry.";
      }
    } catch {
      if (active && generation === current) {
        playing.value = false;
        notice.value = "The next entry could not be loaded. Use Next or Play to retry.";
      }
    } finally {
      if (active && generation === current) {
        advancing.value = false;
        arm();
      }
    }
  }
  function arm() {
    clear();
    if (playing.value && !advancing.value && document.visibilityState !== "hidden")
      timer = setTimeout(() => {
        void step(1);
      }, props.model.playlist.dwell_seconds * 1000);
  }
  function toggle() {
    playing.value = !playing.value;
    notice.value = "";
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
      generation++;
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
    active = false;
    generation++;
    clear();
    document.removeEventListener("visibilitychange", visibility);
  });
  function navigate(e: MouseEvent, path: string) {
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    void props.port.navigate(path).catch(() => {
      if (active) notice.value = "Navigation failed. Please try again.";
    });
  }
  return { playing, advancing, notice, base, step, toggle, navigate };
}
