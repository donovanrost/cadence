defmodule Cadence.SpacecraftType.Schema do
  @moduledoc """
  Field schema for spacecraft profile sections, so UIs generate profile forms
  instead of hand-writing them (design: docs/apogee/domain/profile-routing.md
  §3). Only fields the profile model, `ConfigurationInput.from_profile` and the
  decoders actually consume are listed; spacecraft-id source, virtual
  channels, FEC, TC segment and randomizer have no model backing and are
  deliberately absent.

  Each field: `%{path, label, type, unit, enum, range, default, overridable,
  runtime_impact, help}` with `type` in `integer | boolean | enum | string |
  reference | list` and `runtime_impact` in `generation | routes | none`.
  """

  alias Cadence.SpacecraftType

  @protocol_labels %{
    "tm" => "CCSDS TM",
    "aos" => "CCSDS AOS",
    "uslp" => "CCSDS USLP",
    "tc" => "CCSDS TC",
    "space_packet" => "CCSDS Space Packet"
  }

  @spec sections() :: [%{key: atom(), label: binary(), fields: [map()]}]
  def sections do
    [
      %{key: :framing, label: "Framing", fields: framing_fields()},
      %{key: :catalog, label: "Catalog", fields: [catalog_field(), apids_field()]}
    ]
  end

  @doc "Reads a field's current value from a profile by its dotted path."
  @spec value(SpacecraftType.t(), binary()) :: term()
  def value(%SpacecraftType{} = profile, "frame_parameters." <> key),
    do: Map.get(profile.frame_parameters || %{}, key)

  def value(%SpacecraftType{} = profile, "downlink_protocol"),
    do: string(profile.downlink_protocol)

  def value(%SpacecraftType{} = profile, "uplink_protocol"), do: string(profile.uplink_protocol)
  def value(%SpacecraftType{} = profile, "packet_protocol"), do: string(profile.packet_protocol)

  def value(%SpacecraftType{} = profile, "catalog_revision_id"), do: profile.catalog_revision_id
  def value(%SpacecraftType{} = profile, "handled_apids"), do: profile.handled_apids

  def value(%SpacecraftType{}, _path), do: nil

  @doc "`[%{value, label}]` for a list of protocol enum values."
  @spec protocol_enum([atom()]) :: [map()]
  def protocol_enum(values) do
    Enum.map(values, fn value ->
      value = to_string(value)
      %{value: value, label: Map.get(@protocol_labels, value, value)}
    end)
  end

  defp framing_fields do
    [
      field("downlink_protocol", "TM transfer frame", :enum,
        enum: protocol_enum(SpacecraftType.downlink_protocols()),
        default: "tm",
        runtime_impact: :generation
      ),
      field("uplink_protocol", "TC transfer frame", :enum,
        enum: protocol_enum(SpacecraftType.uplink_protocols()),
        default: "tc",
        runtime_impact: :generation
      ),
      field("packet_protocol", "Packet protocol", :enum,
        enum: protocol_enum(SpacecraftType.packet_protocols()),
        default: "space_packet",
        overridable: false,
        runtime_impact: :generation
      ),
      field("frame_parameters.frame_size", "TM frame length", :integer,
        unit: "bytes",
        range: %{min: 1, max: 65_535},
        default: 1115,
        runtime_impact: :generation,
        help: "TM and AOS frames are at most 2048 bytes; validated per protocol."
      ),
      field("frame_parameters.secondary_header_length", "Secondary header", :integer,
        unit: "bytes",
        range: %{min: 0, max: 64},
        default: 0,
        runtime_impact: :generation
      ),
      field("frame_parameters.insert_zone_length", "Insert zone (AOS)", :integer,
        unit: "bytes",
        range: %{min: 0, max: 65_535},
        default: 0,
        runtime_impact: :generation,
        help: "Validated against the frame length."
      ),
      field("frame_parameters.ocf_length", "Operational control field", :enum,
        unit: "bytes",
        enum: [%{value: 0, label: "None"}, %{value: 4, label: "4 bytes"}],
        default: 0,
        runtime_impact: :generation
      ),
      field("frame_parameters.fecf", "Frame error control field", :boolean,
        default: false,
        runtime_impact: :generation,
        help: "Frames end with a 2-byte CRC (FECF)."
      ),
      field(
        "frame_parameters.truncated_primary_header",
        "Truncated primary header (USLP)",
        :boolean,
        default: false,
        runtime_impact: :generation
      )
    ]
  end

  defp catalog_field do
    field("catalog_revision_id", "Catalog revision", :reference,
      default: nil,
      runtime_impact: :generation,
      help: "The command and telemetry catalog revision this profile decodes with."
    )
  end

  # L22: null = all of the catalog's APIDs; a change in what a spacecraft decodes is a HOLD.
  defp apids_field do
    field("handled_apids", "Handled APIDs", :list,
      range: %{min: 0, max: 2047},
      default: nil,
      runtime_impact: :generation,
      help: "Which of the catalog's packets to decode. Empty means all of the catalog's APIDs."
    )
  end

  defp field(path, label, type, opts) do
    %{
      path: path,
      label: label,
      type: type,
      unit: Keyword.get(opts, :unit),
      enum: Keyword.get(opts, :enum),
      range: Keyword.get(opts, :range),
      default: Keyword.get(opts, :default),
      overridable: Keyword.get(opts, :overridable, true),
      runtime_impact: Keyword.get(opts, :runtime_impact, :none),
      help: Keyword.get(opts, :help)
    }
  end

  defp string(nil), do: nil
  defp string(value), do: to_string(value)
end
