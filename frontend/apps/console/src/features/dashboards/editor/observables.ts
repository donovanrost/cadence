import type { MissionId } from "@/api/index.ts";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api";
import type { WidgetFields } from "./contracts.ts";

/**
 * D8 binding picker search (api): `POST /dashboards/:id/observables {query, base_version, fields}`.
 * `fields` is the widget sheet's whole form (the domain search validates it against the staged
 * document); at most 50 results, `more` when there are others.
 */
const reply = d.object({
  observables: d.array(
    d.object({ id: d.token, label: d.nullable(d.string), description: d.nullable(d.string) }),
    50,
  ),
  more: d.boolean,
});
export type ObservableResults = Decoded<typeof reply>;

export function searchObservables(
  missionId: MissionId,
  dashboardId: string,
  input: Readonly<{ query: string; baseVersion: number; fields: WidgetFields }>,
  signal?: AbortSignal,
): Promise<ApiResult<ObservableResults>> {
  const path = `/missions/${encodeURIComponent(missionId)}/dashboards/${encodeURIComponent(dashboardId)}/observables`;
  const body = { query: input.query, base_version: input.baseVersion, fields: input.fields };
  return request(path, reply, signal ? { method: "POST", body, signal } : { method: "POST", body });
}
