%{
  schema_version: 1,
  maintained_on: "2026-07-20",
  classifications: %{
    published_octets: "Octets printed verbatim by the cited Recommended Standard.",
    normative_table: "A row or constant printed verbatim in a normative table.",
    normative_derivation: "A reviewed byte encoding derived from the cited normative bit layout."
  },
  sources: %{
    ccsds_132_0_b_3: %{
      title: "TM Space Data Link Protocol",
      issue: "CCSDS 132.0-B-3",
      published: "October 2021",
      url:
        "https://ccsds.org/wp-content/uploads/gravity_forms/5-448e85c647331d9cbaf66c096458bdd5/2025/01//132x0b3.pdf",
      sha256: "be715bb3b1f92a4e5655719969277aee3b250dd706748b53dccd9971896603ad"
    },
    ccsds_133_0_b_2: %{
      title: "Space Packet Protocol",
      issue: "CCSDS 133.0-B-2 with errata 2",
      published: "June 2020",
      url:
        "https://ccsds.org/wp-content/uploads/gravity_forms/5-448e85c647331d9cbaf66c096458bdd5/2025/01//133x0b2e2.pdf",
      sha256: "a7d3acaa7d8af5f306917dff454b69de187855c45a51bb76ac4636fb5b23e34e"
    },
    ccsds_231_0_b_4: %{
      title: "TC Synchronization and Channel Coding",
      issue: "CCSDS 231.0-B-4 with errata 1 and corrigendum 1",
      published: "July 2021",
      url:
        "https://ccsds.org/wp-content/uploads/gravity_forms/5-448e85c647331d9cbaf66c096458bdd5/2026/07/231x0b4e1c1.pdf",
      sha256: "187811a1689a998d1806c7747a03d078ac5becb707e59ef3c35c1b1ec1e0b8d9"
    },
    ccsds_232_0_b_4: %{
      title: "TC Space Data Link Protocol",
      issue: "CCSDS 232.0-B-4 with errata 1 and corrigendum 1",
      published: "October 2021",
      url:
        "https://ccsds.org/wp-content/uploads/gravity_forms/5-448e85c647331d9cbaf66c096458bdd5/2025/01//232x0b4e1c1.pdf",
      sha256: "0892557c3f28373498c2e1a9f089cd8a63e46eddff2325c90ff1c39ea6c4d792"
    },
    ccsds_732_0_b_5: %{
      title: "AOS Space Data Link Protocol",
      issue: "CCSDS 732.0-B-5 with corrigendum 1",
      published: "October 2025",
      url:
        "https://ccsds.org/wp-content/uploads/gravity_forms/5-448e85c647331d9cbaf66c096458bdd5/2025/10/732x0b5ec1.pdf",
      sha256: "d9d22dd4e9b43128c9a634ae29e32a67b50c16dab52a916cc465999021cd0f91"
    },
    ccsds_732_1_b_3: %{
      title: "Unified Space Data Link Protocol",
      issue: "CCSDS 732.1-B-3",
      published: "June 2024",
      url:
        "https://ccsds.org/wp-content/uploads/gravity_forms/5-448e85c647331d9cbaf66c096458bdd5/2025/01//732x1b3e1.pdf",
      sha256: "3d931ae1b9ffb6a9282fedcc79e619356e61f67729d1e3f9bf433f8e719420ff"
    }
  },
  vectors: [
    %{
      id: "tm-oid-annex-d-prefix",
      classification: :published_octets,
      source: :ccsds_132_0_b_3,
      locator: "annex D, page D-1",
      subject: :tm_only_idle_data,
      parameters: %{octets: 20},
      expected_hex: "FFFFFFFF6DB6D861451F11F19716723CBE7E00B1"
    },
    %{
      id: "tm-primary-header-layout",
      classification: :normative_derivation,
      source: :ccsds_132_0_b_3,
      locator: "4.1.2, figure 4-2",
      subject: :tm_transfer_frame,
      parameters: %{
        scid: 1,
        vcid: 2,
        mcfc: 9,
        vcfc: 7,
        fhp: 0,
        payload_hex: "01020304"
      },
      expected_hex: "00140907180001020304"
    },
    %{
      id: "tm-secondary-header-layout",
      classification: :normative_derivation,
      source: :ccsds_132_0_b_3,
      locator: "4.1.2.6, figure 4-4",
      subject: :tm_secondary_header,
      parameters: %{data_hex: "010203"},
      expected_hex: "03010203"
    },
    %{
      id: "space-packet-primary-header-layout",
      classification: :normative_derivation,
      source: :ccsds_133_0_b_2,
      locator: "4.1.3, figure 4-2",
      subject: :space_packet,
      parameters: %{
        packet_type: :telemetry,
        secondary_header?: false,
        apid: 0x123,
        sequence_flag: :unsegmented,
        sequence_count: 0x42,
        data_hex: "AABBCC"
      },
      expected_hex: "0123C0420002AABBCC"
    },
    %{
      id: "tc-bch-zero-information-codeword",
      classification: :normative_derivation,
      source: :ccsds_231_0_b_4,
      locator: "3.2-3.3, figures 3-1 and 3-2",
      subject: :bch_codeword,
      parameters: %{information_hex: "00000000000000"},
      expected_hex: "00000000000000FE"
    },
    %{
      id: "tc-bch-sample-information-codeword",
      classification: :normative_derivation,
      source: :ccsds_231_0_b_4,
      locator: "3.2-3.3, figures 3-1 and 3-2",
      subject: :bch_codeword,
      parameters: %{information_hex: "01020304050607"},
      expected_hex: "0102030405060770"
    },
    %{
      id: "tc-ldpc-128-row-1",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-1, row 1",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_128_64, row: 1},
      expected_hex: "0E69166BEF4C0BC2"
    },
    %{
      id: "tc-ldpc-128-row-17",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-1, row 17",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_128_64, row: 17},
      expected_hex: "7766137EBB248418"
    },
    %{
      id: "tc-ldpc-128-row-33",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-1, row 33",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_128_64, row: 33},
      expected_hex: "C480FEB9CD53A713"
    },
    %{
      id: "tc-ldpc-128-row-49",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-1, row 49",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_128_64, row: 49},
      expected_hex: "4EAA22FA465EEA11"
    },
    %{
      id: "tc-ldpc-512-row-1",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-2, row 1",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_512_256, row: 1},
      expected_hex: "1D21794A22761FAE59945014257E130D74D60540037940142DADEB9CA25EF12E"
    },
    %{
      id: "tc-ldpc-512-row-65",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-2, row 65",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_512_256, row: 65},
      expected_hex: "60E0B6623C5CE5124D2C81ECC7F469AB20678DBFB7523ECE2B54B906A9DBE98C"
    },
    %{
      id: "tc-ldpc-512-row-129",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-2, row 129",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_512_256, row: 129},
      expected_hex: "F6739BCF54273E77167BDA120C6C47744C071EFF5E32A7593138670C095C39B5"
    },
    %{
      id: "tc-ldpc-512-row-193",
      classification: :normative_table,
      source: :ccsds_231_0_b_4,
      locator: "table 4-2, row 193",
      subject: :ldpc_generator_row,
      parameters: %{code: :ldpc_512_256, row: 193},
      expected_hex: "28706BD0453002582DAB85F05B9201D08DFDEE2D9D84CA88B371FAE63A4EB07E"
    },
    %{
      id: "tc-randomizer-first-40-bits",
      classification: :published_octets,
      source: :ccsds_231_0_b_4,
      locator: "6.2, page 6-1",
      subject: :tc_randomizer,
      parameters: %{octets: 5},
      expected_hex: "FF399E5A68"
    },
    %{
      id: "tc-bch-cltu-start",
      classification: :published_octets,
      source: :ccsds_231_0_b_4,
      locator: "5.2.2.2, page 5-2",
      subject: :cltu_constant,
      parameters: %{constant: :bch_start},
      expected_hex: "EB90"
    },
    %{
      id: "tc-ldpc-cltu-start",
      classification: :published_octets,
      source: :ccsds_231_0_b_4,
      locator: "5.2.2.3, page 5-2",
      subject: :cltu_constant,
      parameters: %{constant: :ldpc_start},
      expected_hex: "034776C7272895B0"
    },
    %{
      id: "tc-bch-cltu-tail",
      classification: :published_octets,
      source: :ccsds_231_0_b_4,
      locator: "5.2.4.1, page 5-2",
      subject: :cltu_constant,
      parameters: %{constant: :bch_tail},
      expected_hex: "C5C5C5C5C5C5C579"
    },
    %{
      id: "tc-ldpc-128-cltu-tail",
      classification: :published_octets,
      source: :ccsds_231_0_b_4,
      locator: "5.2.4.2, page 5-3, corrigendum 1",
      subject: :cltu_constant,
      parameters: %{constant: :ldpc_128_tail},
      expected_hex: "63A1ED72C6AC79E25555555555555555"
    },
    %{
      id: "tc-transfer-frame-primary-header-layout",
      classification: :normative_derivation,
      source: :ccsds_232_0_b_4,
      locator: "4.1.2, figure 4-2",
      subject: :tc_transfer_frame,
      parameters: %{
        bypass_flag: 1,
        control_command_flag: 0,
        scid: 42,
        vcid: 5,
        frame_seq: 77,
        payload_hex: "AABBCC"
      },
      expected_hex: "202A14074DAABBCC"
    },
    %{
      id: "tc-segment-header-layout",
      classification: :normative_derivation,
      source: :ccsds_232_0_b_4,
      locator: "4.1.3.2.2, figure 4-3",
      subject: :tc_segment_header,
      parameters: %{sequence_flag: :last, map_id: 42},
      expected_hex: "AA"
    },
    %{
      id: "tc-unlock-control-command",
      classification: :published_octets,
      source: :ccsds_232_0_b_4,
      locator: "4.1.3.3.2, page 4-9",
      subject: :cop1_control_command,
      parameters: %{command: :unlock},
      expected_hex: "00"
    },
    %{
      id: "tc-set-vr-control-command",
      classification: :published_octets,
      source: :ccsds_232_0_b_4,
      locator: "4.1.3.3.3, page 4-9",
      subject: :cop1_control_command,
      parameters: %{command: {:set_vr, 219}},
      expected_hex: "8200DB"
    },
    %{
      id: "tc-fecf-derived-check",
      classification: :normative_derivation,
      source: :ccsds_232_0_b_4,
      locator: "4.1.4.2, figure 4-4",
      subject: :frame_error_control,
      parameters: %{input_hex: "01020304"},
      expected_hex: "89C3"
    },
    %{
      id: "tc-clcw-layout",
      classification: :normative_derivation,
      source: :ccsds_232_0_b_4,
      locator: "4.2.1, figure 4-6",
      subject: :clcw,
      parameters: %{
        status: 5,
        cop_in_effect: 1,
        vcid: 17,
        no_rf_available: 1,
        no_bit_lock: 0,
        lockout: 1,
        wait: 0,
        retransmit: 1,
        farm_b_counter: 2,
        report_value: 99
      },
      expected_hex: "1544AC63"
    },
    %{
      id: "aos-issue-5-primary-header-layout",
      classification: :normative_derivation,
      source: :ccsds_732_0_b_5,
      locator: "4.1.2, figures 4-1 and 4-2",
      subject: :aos_transfer_frame,
      parameters: %{
        scid: 0x321,
        vcid: 5,
        vcfc: 0xA0B0C0,
        replay_flag: 1,
        cycle_use_flag: 1,
        cycle: 9,
        payload_hex: "AABB"
      },
      expected_hex: "4845A0B0C0F9AABB"
    },
    %{
      id: "aos-frame-header-error-control",
      classification: :normative_derivation,
      source: :ccsds_732_0_b_5,
      locator: "4.1.2.6 and annex C",
      subject: :aos_frame_header_error_control,
      parameters: %{protected_header: 0x1234, signaling: 0x56},
      expected_hex: "94DC"
    },
    %{
      id: "aos-mpdu-layout",
      classification: :normative_derivation,
      source: :ccsds_732_0_b_5,
      locator: "4.1.4.2, figure 4-3",
      subject: :aos_mpdu,
      parameters: %{first_header_pointer: 2, packet_zone_hex: "AABBCC"},
      expected_hex: "0002AABBCC"
    },
    %{
      id: "aos-bpdu-layout",
      classification: :normative_derivation,
      source: :ccsds_732_0_b_5,
      locator: "4.1.4.3, figure 4-4",
      subject: :aos_bpdu,
      parameters: %{bitstream_data_pointer: 9, data_zone_hex: "AABBCC"},
      expected_hex: "0009AABBCC"
    },
    %{
      id: "aos-oid-annex-d-prefix",
      classification: :normative_derivation,
      source: :ccsds_732_0_b_5,
      locator: "4.1.4.1.5 and annex D",
      subject: :aos_only_idle_data,
      parameters: %{octets: 20},
      expected_hex: "FFFFFFFF6DB6D861451F11F19716723CBE7E00B1"
    },
    %{
      id: "uslp-version-4-frame-layout",
      classification: :normative_derivation,
      source: :ccsds_732_1_b_3,
      locator: "4.1.1-4.1.4, figures 4-1 through 4-4",
      subject: :uslp_transfer_frame,
      parameters: %{
        scid: 0x1234,
        source_destination: :destination,
        vcid: 0x15,
        map_id: 0xA,
        qos: :sequence_controlled,
        count_octets: 2,
        count: 0xBEEF,
        construction_rule: :unsegmented,
        upid: 5,
        payload_hex: "AABB"
      },
      expected_hex: "C1234AB4000B02BEEFE5AABB"
    },
    %{
      id: "uslp-truncated-frame-layout",
      classification: :normative_derivation,
      source: :ccsds_732_1_b_3,
      locator: "annex D, figures D-1 and D-2",
      subject: :uslp_truncated_transfer_frame,
      parameters: %{
        scid: 0x1234,
        vcid: 5,
        map_id: 6,
        payload_hex: "010203"
      },
      expected_hex: "C12340ADE5010203"
    },
    %{
      id: "uslp-oid-annex-h-prefix",
      classification: :published_octets,
      source: :ccsds_732_1_b_3,
      locator: "annex H, page H-1",
      subject: :uslp_only_idle_data,
      parameters: %{octets: 20},
      expected_hex: "FFFFFFFF6DB6D861451F11F19716723CBE7E00B1"
    }
  ]
}
