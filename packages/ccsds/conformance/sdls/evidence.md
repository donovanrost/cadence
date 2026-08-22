# Space Data Link Security evidence

The protocol boundary targets CCSDS 355.0-B-2, July 2022. The exact publication
URL and SHA-256 are recorded in `normative_vectors.exs`.

The maintained corpus derives the baseline TC authentication Security Header
from annex E2 and the baseline TM authenticated-encryption Security Header from
annex E1. Focused tests cover the common Security Association parameters,
header and trailer lengths, authentication masks, all three service types,
sequence-number and IV-based replay protection, padding, exact channel/SPI
selection, standard protocol service and channel-scope restrictions,
protocol-required mask bits, and portable verification failures.

Cryptographic algorithms and keys are deliberately outside the runtime library.
Tests use a deterministic callback only to prove orchestration and do not claim
cryptographic conformance. No independent implementation has been added to the
external differential harness, and this evidence is not flight qualification.
