import { request, type ApiResult } from "@/api";
import {
  configStateReader,
  revisionsReader,
  type ConfigState,
  type RevisionSummary,
} from "./shapes.ts";

const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/config`;

/** The staged bar, `CONFIG rN · N STAGED`, and the caller's config capabilities. */
export function fetchConfigState(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<ConfigState>> {
  return request(base(missionId), configStateReader, { signal });
}

export async function fetchRevisions(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly RevisionSummary[]>> {
  const result = await request(`${base(missionId)}/revisions?limit=50`, revisionsReader, {
    signal,
  });
  return result.ok ? { ok: true, value: result.value.revisions } : result;
}
