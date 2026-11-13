import { decoders as d, request, type ApiResult, type Decoded } from "@/api";

/**
 * D8 binding picker search (`ObservableChoices` rows). api pastes the exact row fields with the
 * build; until then only `id` is required and the rest is read when present.
 */
const choice = d.object({
  id: d.token,
  label: d.optional(d.nullable(d.string)),
  unit: d.optional(d.nullable(d.string)),
  description: d.optional(d.nullable(d.string)),
});
const reply = d.object({ observables: d.array(choice, 100) });
export type ObservableChoice = Decoded<typeof choice>;

export function searchObservables(
  missionId: string,
  query: Readonly<{ q: string; source: string; spacecraftId: string }>,
  signal?: AbortSignal,
): Promise<ApiResult<Decoded<typeof reply>>> {
  const params = new URLSearchParams({ q: query.q, source: query.source, limit: "50" });
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  return request(
    `/missions/${encodeURIComponent(missionId)}/dashboards/observables?${params.toString()}`,
    reply,
    signal ? { signal } : {},
  );
}
