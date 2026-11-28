/**
 * #795: the size guard's default `max_targets` (commanding.md), the most targets one request can
 * carry. Lists that name every target (preflight's, a decision's exclusions) are bounded by it.
 */
export const MAX_TARGETS = 5_000;
