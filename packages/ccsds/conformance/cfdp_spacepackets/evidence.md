# CFDP PDU interoperability evidence

The maintained differential run targets CCSDS 727.0-B-5 at the PDU boundary.
It compares this library with the independently implemented Python `spacepackets`
package:

- package: `spacepackets==0.32.0`;
- package artifact: `spacepackets-0.32.0-py3-none-any.whl`;
- artifact SHA-256: `8a4d8791b50a4aebbcdb2f60c10aa188cfa5ca8368a843f16d6fb141cc1dcf01`;
- maintained run date: 2026-07-21; and
- runtime used for the maintained run: Python 3.11.0.

The run passed 128 library-generated PDUs through the independent parser and
re-encoder. It then passed 11 independently constructed PDUs back through the
CCSDS decoder and exact re-encoder. The cases cover Metadata, File Data,
EOF, Finished, ACK, NAK, Prompt, and Keep Alive forms; acknowledged and
unacknowledged headers; small and large files; optional PDU CRCs; identifier
widths in the intersection supported by both libraries; and Message-to-User
and Flow Label options.

Maintained result:

```text
External CFDP PDU interoperability PASS
implementation=spacepackets
version=0.32.0
runtime=Python 3.11.0
ccsds_generated_cases=128
spacepackets_generated_cases=11
wire_bytes_sha256=415ff18cc9c13b970ba0b9bcf83a2d0717e4cf7482f128117c20e308fb5f8137
```

Run the opt-in check with:

```sh
bash conformance/cfdp_spacepackets/run.sh
```

`spacepackets` 0.32.0 accepts identifier widths of one, two, four, and eight
octets, while CCSDS 727.0-B-5 permits every width from one through eight. The
differential cases therefore use the common width set; the library-only seeded
properties cover all eight standard widths. The external run validates PDU
interoperability, not cross-implementation Class 1 or Class 2 transaction
behavior, filestore semantics, or flight qualification.
