# AOS independent implementation evidence

Maintained on 2026-07-20.

The AOS shortened Reed-Solomon Frame Header Error Control implementation was
checked against Yamcs commit
`425c8cbb35906b0aabfc94b0ec7627950ab08720` from
<https://github.com/yamcs/yamcs>:

- implementation:
  `yamcs-core/src/main/java/org/yamcs/tctm/ccsds/error/AosFrameHeaderErrorCorr.java`;
- vectors:
  `yamcs-core/src/test/java/org/yamcs/tctm/ccsds/error/AosFrameHeaderErrorCorrTest.java`.

The maintained library tests reproduce both encode vectors (`94DC`, `457C`),
the clean and one/two-symbol correction cases, and the published Yamcs
uncorrectable case. The codec orientation was also derived directly from CCSDS
732.0-B-5 annex C and is recorded in `normative_vectors.exs` against the exact
standard PDF hash.

This evidence covers the FHEC algorithm only. Yamcs currently models the older
AOS header addressing layout, so it is not used as an issue-5 10-bit SCID or
complete seven-service interoperability oracle.
