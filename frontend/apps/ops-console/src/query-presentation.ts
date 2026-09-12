import { record } from "@cadence/plugin-sdk/admission";

/** The remote query envelope is distinct from native page snapshots. Feature readers admit its payload. */
export function queryPresentation(
  value: unknown,
  component: string,
  prop: string,
  unavailable: string,
): unknown {
  const candidate = record(value) ? (value.trusted_surface ?? value) : value;
  if (
    !record(candidate) ||
    candidate.queryVersion !== 1 ||
    !record(candidate.presentation) ||
    candidate.presentation.component !== component
  )
    throw Error(unavailable);
  return record(candidate.presentation.props) ? candidate.presentation.props[prop] : undefined;
}
