import { onScopeDispose, shallowRef, watch, type Ref } from "vue";
import { decode, decoders as d, type Decoded, pointId as pointIdReader } from "@/api/index.ts";
import { acquireChannel, onReconnect, type ChannelHandle } from "@/live/socket.ts";
import type { SeriesPoint } from "@/ui";

/**
 * M8 live tail (realtime.md 474f3350, 26d6623f): `spacecraft:<mission_id>:<spacecraft_id>` pushes `points {seq, samples}` for the
 * selected points, at most once a second, in commit order. The first push after a join is the
 * current value of each point; a reconnect refetches history (nothing is replayed). Selection is
 * set with `points:set {point_ids}` after every join.
 *
 * Off until api-ops' M8 lands: joining a topic the server doesn't know makes Phoenix retry the join.
 */
export const M8_LIVE = true;

const sample = d.object({
  point_id: pointIdReader,
  value_json: d.nullable(d.string),
  generation_time: d.timestamp,
  received_at: d.nullable(d.timestamp),
  /** Reads.SpacecraftLive: red → critical, yellow → caution, green/blue → nominal. */
  limit_state: d.nullable(d.known(["critical", "caution", "nominal"] as const)),
});
export const pointsPush = d.object({ seq: d.integer, samples: d.array(sample, 2_000) });
export type TailSample = Decoded<typeof sample>;

/** Most samples kept per point between history refetches. */
const KEEP = 600;

/** Merge a push into the per-point tails, sorted by generation_time (backfills land in place). */
export function mergeSamples(
  tails: ReadonlyMap<string, readonly TailSample[]>,
  samples: readonly TailSample[],
): Map<string, TailSample[]> {
  const next = new Map<string, TailSample[]>([...tails].map(([k, v]) => [k, [...v]]));
  for (const s of samples) {
    const list = next.get(s.point_id) ?? [];
    list.push(s);
    next.set(s.point_id, list);
  }
  for (const [k, list] of next) {
    list.sort((a, b) => Date.parse(a.generation_time) - Date.parse(b.generation_time));
    next.set(k, list.slice(-KEEP));
  }
  return next;
}

/** Numeric tail samples after the history's last bucket, as chart points. */
export function tailPoints(tail: readonly TailSample[], after: number): SeriesPoint[] {
  return tail.flatMap((s) => {
    const t = Date.parse(s.generation_time);
    const v = s.value_json === null ? NaN : Number(s.value_json);
    return t > after && Number.isFinite(v) ? [{ t, min: v, mean: v, max: v }] : [];
  });
}

export function useSpacecraftTail(
  missionId: Ref<string | null>,
  spacecraftId: Ref<string | null>,
  pointIds: Ref<readonly string[]>,
  onResync: () => void,
) {
  const tails = shallowRef(new Map<string, TailSample[]>());
  let current: { handle: ChannelHandle; stop: () => void } | null = null;
  const select = (h: ChannelHandle) => {
    if (h.joined()) h.channel.push("points:set", { point_ids: [...pointIds.value] });
  };

  const stopTopic = watch(
    () =>
      M8_LIVE && missionId.value && spacecraftId.value
        ? `spacecraft:${missionId.value}:${spacecraftId.value}`
        : null,
    (topic) => {
      current?.stop();
      current = null;
      tails.value = new Map();
      if (topic === null) return;
      const handle = acquireChannel(topic);
      const stopJoin = handle.onJoin(() => select(handle));
      select(handle);
      const ref = handle.channel.on("points", (payload: unknown) => {
        const r = decode(pointsPush, payload);
        if (r.ok) tails.value = mergeSamples(tails.value, r.value.samples);
      });
      const stopResync = onReconnect(() => {
        tails.value = new Map();
        onResync();
      });
      current = {
        handle,
        stop: () => {
          stopJoin();
          stopResync();
          handle.channel.off("points", ref);
          handle.release();
        },
      };
    },
    { immediate: true },
  );
  const stopPoints = watch(pointIds, () => current && select(current.handle));
  onScopeDispose(() => {
    stopTopic();
    stopPoints();
    current?.stop();
    current = null;
  });
  return { tails };
}
