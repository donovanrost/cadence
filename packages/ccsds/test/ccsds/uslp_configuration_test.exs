defmodule CCSDS.USLPConfigurationTest do
  use ExUnit.Case, async: true

  alias CCSDS.SDLP.USLP.Configuration

  test "accepts a variable-length MAP Packet service with independent QoS counters" do
    assert {:ok, configuration} =
             Configuration.new(
               physical_channel: "forward",
               frame_type: :variable,
               frame_size: 1_024,
               scid: 0xBEEF,
               vcid: 12,
               map_id: 3,
               sequence_count_octets: 3,
               expedited_count_octets: 1,
               maximum_frames_per_coding_unit: 8,
               maximum_repetitions: 4,
               sequence_repetitions: 2,
               protocol_control_repetitions: 4,
               maximum_tfdf_delay_ms: 50,
               maximum_frame_release_delay_ms: 100
             )

    assert configuration.valid_scids == [0xBEEF]
    assert configuration.valid_vcids == [12, 63]
    assert configuration.valid_map_ids == [3]
    assert Configuration.count_octets(configuration, :sequence_controlled) == 3
    assert Configuration.count_octets(configuration, :expedited) == 1
    assert configuration.maximum_frames_per_coding_unit == 8
    assert configuration.maximum_frame_release_delay_ms == 100
  end

  test "enforces variable-frame and reserved OID constraints" do
    assert {:error, :variable_length_uslp_forbids_insert_zone} =
             Configuration.new(
               frame_type: :variable,
               frame_size: 64,
               scid: 1,
               vcid: 2,
               insert_zone_length: 2
             )

    assert {:ok, oid} =
             Configuration.new(
               frame_type: :fixed,
               frame_size: 64,
               scid: 1,
               vcid: 63,
               map_id: 0,
               data_field_content: :idle_data
             )

    assert oid.upid == 31

    assert {:error, :idle_vcid_requires_fixed_only_idle_data} =
             Configuration.new(
               frame_type: :fixed,
               frame_size: 64,
               scid: 1,
               vcid: 63,
               map_id: 1,
               data_field_content: :idle_data
             )
  end

  test "truncated frames are a variable-length mission-specific MAP access option" do
    assert {:ok, configuration} =
             Configuration.new(
               frame_type: :variable,
               frame_size: 64,
               scid: 1,
               vcid: 2,
               map_id: 3,
               data_field_content: :mapa_sdu,
               truncated_frame_length: 12
             )

    assert configuration.upid == 5

    assert {:error, :invalid_truncated_uslp_configuration} =
             Configuration.new(
               frame_type: :fixed,
               frame_size: 64,
               scid: 1,
               vcid: 2,
               data_field_content: :mapa_sdu,
               truncated_frame_length: 12
             )
  end

  test "plan validation preserves MAP multiplexing and VC service exclusivity" do
    first =
      Configuration.new!(
        frame_type: :variable,
        frame_size: 256,
        scid: 10,
        vcid: 2,
        map_id: 1,
        valid_map_ids: [1, 2]
      )

    second = %{first | map_id: 2}
    assert :ok = Configuration.validate_plan([first, second])

    vc_packet = %{first | packet_service: :virtual_channel}

    assert {:error, {{"default", 10, 2}, :vc_packet_service_requires_exclusive_virtual_channel}} =
             Configuration.validate_plan([vc_packet, second])
  end

  test "managed repetition values cannot exceed the physical-channel maximum" do
    assert {:error, {:repetitions_exceed_physical_maximum, 2, 0, 1}} =
             Configuration.new(
               frame_type: :variable,
               frame_size: 64,
               scid: 1,
               vcid: 2,
               maximum_repetitions: 1,
               sequence_repetitions: 2
             )
  end
end
