import { decoders, type Decoded } from "@/api";

const { array, integer, object, oneOf, string, token } = decoders;

/** POST .../change-sets/:id/submit (docs/apogee/api/changes.md): applied, sent for review, or back. */
export const submitReader = decoders.variant("state", {
  applied: object({
    state: decoders.literal("applied"),
    change_set_id: token,
    revision: integer,
    staged_count: integer,
    runtime: oneOf(["not_applicable", "converging", "applied", "degraded"]),
    degraded_partitions: array(string, 1000),
    /**
     * U93 (api): false = no activation exists on the mission, so applying saved the changes and
     * started nothing. Not runtime health. Optional until api ships it.
     */
    has_active_configuration: decoders.optional(decoders.boolean),
  }),
  in_review: object({
    state: decoders.literal("in_review"),
    change_set_id: token,
    version: integer,
  }),
  open: object({ state: decoders.literal("open"), change_set_id: token, version: integer }),
});
export type SubmitResult = Decoded<typeof submitReader>;
