import { readSurfaces as overview } from "./features/overview/read-surfaces";
import { readSurfaces as validation } from "./features/setup-validation/read-surfaces";
import { readSurfaces as transports } from "./features/transports/read-surfaces";
import { readSurfaces as routing } from "./features/routing/read-surfaces";
import { readSurfaces as stations } from "./features/ground-stations/read-surfaces";
import type { ReadContext } from "./shared/read-contracts";
export const readSurfaces = {
  ...overview,
  ...validation,
  ...transports,
  ...routing,
  ...stations,
} as const;
export function admitReadSurface(
  surfaceId: string,
  version: number,
  payload: unknown,
  context: ReadContext,
) {
  if (version !== 1 || !Object.hasOwn(readSurfaces, surfaceId))
    throw new Error("Unsupported Communications read surface.");
  const surface = readSurfaces[surfaceId as keyof typeof readSurfaces];
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  return { component: surface.component, props: surface.admit(payload, context) };
}
