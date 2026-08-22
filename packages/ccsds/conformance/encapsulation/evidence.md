# Encapsulation Packet Protocol evidence

The runtime implementation targets CCSDS 133.1-B-3, May 2020, with errata 1.
The exact source URL and SHA-256 are recorded in `normative_vectors.exs`.

The maintained corpus derives one packet for each normative primary-header
size from figures 4-2 through 4-5. Tests cover exact encoding and decoding of
the one-octet Idle Packet, two-octet LTP packet, four-octet extended-protocol
packet, and eight-octet private-use packet. Seeded checks exercise adaptive
header selection, split streaming input, exact re-encoding, and arbitrary
malformed input.

No independent implementation covering CCSDS 133.1-B-3 has been added to the
external differential harness. This evidence therefore establishes audited
source derivations and internal codec properties, not interoperability or
flight qualification.
