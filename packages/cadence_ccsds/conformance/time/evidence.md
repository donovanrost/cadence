# CUC and CDS time-code evidence

The time-code boundary targets CCSDS 301.0-B-4 with Editorial Change 1. The
exact publication URL and SHA-256 are recorded in `normative_vectors.exs`.

The maintained corpus derives one-octet and extended CUC P-fields and all
three CDS resolutions from the normative field layouts in sections 3.2 and
3.3. Focused tests cover explicit and implicit P-fields, maximum CUC counter
lengths, both epoch classes, CDS 16- and 24-bit day counters, normal and
leap-adjusted millisecond bounds, every incomplete streaming boundary, exact
fractional arithmetic, and explicit correlation/rounding evidence.

No leap-second table or mission clock correlation is embedded in the library.
CUC conversion requires a caller-supplied counter and `DateTime` anchor; CDS
leap-second instants that Elixir `DateTime` cannot represent are returned as an
explicit error. No independent implementation has been added to the external
differential harness, and this evidence is not flight qualification.
