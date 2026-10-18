import { fail, id } from "./validation";
export function stagesHref(mission: string, stage?: string): string {
  if (!id(mission) || (stage !== undefined && !id(stage))) return fail();
  return `/missions/${encodeURIComponent(mission)}/ops/commands/stages${stage ? `/${encodeURIComponent(stage)}` : ""}`;
}
export function withQuery(path: string, query: Record<string, string>): string {
  const params = new URLSearchParams(Object.entries(query).filter(([, v]) => v !== ""));
  return path + (params.size ? `?${params}` : "");
}
