# USLP normative evidence

Maintained on 2026-07-20.

The USLP implementation is grounded in CCSDS 732.1-B-3, retrieved from the
CCSDS active publications catalog. The exact PDF URL and SHA-256 are recorded
in `normative_vectors.exs`.

The maintained corpus contains reviewed bit-layout derivations for a complete
Version-4 variable-length frame and the normative annex-D truncated frame. It
also reproduces the 20 published annex-H OID octets verbatim. Focused tests
encode and decode both frame layouts and verify continuity of the 32-cell OID
LFSR across frame boundaries.

No independent implementation has yet been identified that covers the full
Issue-3 USLP service set. The evidence therefore makes no interoperability
claim beyond the source-hashed normative derivations and property checks.
