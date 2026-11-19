defmodule Cadence.Reads.ConfigKindSchema do
  @moduledoc """
  Editable-field schemas for change-set kinds, in the same field shape as
  `Cadence.SpacecraftType.Schema` (`path, label, type, unit, enum, range,
  default, required, help, visible_when`), so console edit forms are generated.

  `ground_station` mirrors the kind's validation (name, code, provider,
  region), with provider options from the mission's ground-network providers, plus `metadata`
  (`type: :json`, an object, default `{}`; comms parity 4).
  `transport` adds the transport kind's own configuration fields (today
  `tcp_socket`) under `configuration.*`, addressing the stored, normalized
  configuration document (e.g. `configuration.framing.mode`).
  `spacecraft_profile` (fe-setup, New profile) is the name plus the profile sections of
  `Cadence.SpacecraftType.Schema` (framing, catalog), each field carrying its `section`; routing
  rules, applications and metadata have their own editors.
  `limit_definition` (#77 stage 2): `point_id` and `limit_set_name` (`create_only`), then
  `thresholds.{red_low, yellow_low, yellow_high, red_high}` (`type: :number`, each optional).
  `derived_telemetry` (#77): `point_id` (`create_only: true`), `point_name`, and `expression`
  (`type: :text`, multiline); `metadata` isn't in the form.
  `spacecraft` (L17/L22) is identity (`section: "identity"`) plus the commanding and telemetry
  switches (`section: "switches"`, help is ux's U40). Profile choices are the mission's shared
  profiles; a version left empty means the profile's latest (`Cadence.Control.SpacecraftOps`).
  `spacecraft_route` (DECISIONS #3, ux U79): spacecraft (`create_only`), station, optional
  transport, required `downlink` and `uplink` (`none` or a role; the kind maps them to legs),
  route name and purpose.
  """

  alias Cadence.Catalog
  alias Cadence.Comms.{GroundStationStore, TransportKind, TransportStore}
  alias Cadence.Reads.ProfileDetail
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType.Schema, as: ProfileSchema
  alias Cadence.SpacecraftTypeStore

  @synthetic_profile "spacecraft_configuration_profile_"

  @commanding_help "Lets operators request and release commands to this spacecraft. Turning " <>
                     "it off cancels commands still waiting to be sent when the change is " <>
                     "applied."

  @telemetry_help "Cadence decodes this spacecraft's telemetry into live values, alarms and " <>
                    "history. Turning it off means no new live values, alarms or history " <>
                    "until it's turned on again."

  # A profile can't be framed without both transfer frames.
  @profile_required ~w(downlink_protocol uplink_protocol)

  # Definition field names mapped to the paths of the stored (normalized)
  # configuration document, so prefill, staged changes and conflict checks all
  # address the same keys.
  @config_keys %{
    tcp_mode: "mode",
    framing_mode: "framing.mode",
    frame_size: "framing.fixed_message_bytes",
    reconnect_policy: "reconnect.policy",
    tls_enabled: "tls.enabled"
  }

  # Stored as a boolean even though the legacy form renders it as a select.
  @boolean_fields [:tls_enabled]

  @doc "Fields for `kind`; `ground_station`'s provider options come from the mission's providers."
  @spec fields(binary(), binary(), binary()) :: {:ok, [map()]} | {:error, :unknown_kind}
  def fields("ground_station", organization_id, mission_id) do
    providers =
      organization_id
      |> Cadence.GroundNetworks.list_providers(mission_id)
      |> Enum.map(&%{value: &1.display_name, label: &1.display_name})

    {:ok,
     [
       field("display_name", "Name", :string, required: true, range: %{min: 1, max: 200}),
       # ux U25: optional while none is stored (the console marks it required once set).
       field("code", "Code", :string,
         required: false,
         range: %{min: 2, max: 8},
         help: "2–8 capital letters or digits, unique in the mission (e.g. SVB)."
       )
       |> Map.put(:pattern, "^[A-Z0-9]{2,8}$"),
       if(providers == [],
         do: field("provider", "Provider", :string, range: %{max: 200}),
         else: field("provider", "Provider", :enum, enum: providers)
       ),
       field("region", "Region", :string, range: %{max: 200}),
       # Comms parity (4): legacy comms could edit station metadata. `:json` is an object only,
       # default {} (the console reads it as of 5040bd149; the kind already checks it's a map).
       field("metadata", "Metadata", :json, default: %{})
     ]}
  end

  def fields("spacecraft_profile", organization_id, mission_id) do
    choices =
      organization_id
      |> Catalog.list_revisions(mission_id)
      |> Enum.map(&%{value: &1.catalog_revision_id, label: ProfileDetail.catalog_label(&1)})

    name =
      "display_name"
      |> field("Name", :string, required: true, range: %{min: 1, max: 200})
      |> Map.put(:section, "profile")

    {:ok, [name | Enum.flat_map(ProfileSchema.sections(), &profile_section(&1, choices))]}
  end

  def fields("spacecraft", organization_id, mission_id) do
    profiles =
      organization_id
      |> SpacecraftTypeStore.list_spacecraft_types(mission_id)
      |> Enum.reject(&String.starts_with?(&1.spacecraft_type_id, @synthetic_profile))
      |> Enum.map(&%{value: &1.spacecraft_type_id, label: &1.display_name})

    identity = [
      field("display_name", "Name", :string, required: true, range: %{min: 1, max: 200}),
      field("scid", "SCID", :integer,
        range: %{min: 0, max: 1023},
        help: "The spacecraft ID its frames carry, unique in the mission."
      ),
      field("spacecraft_type_id", "Profile", :enum, enum: profiles),
      field("spacecraft_type_version", "Profile version", :integer,
        range: %{min: 1, max: 1_000_000},
        help: "Leave empty for the profile's latest version."
      )
    ]

    switches = [
      field("commanding_enabled", "Commanding", :boolean, help: @commanding_help),
      field("telemetry_enabled", "Telemetry", :boolean, help: @telemetry_help)
    ]

    {:ok,
     Enum.map(identity, &Map.put(&1, :section, "identity")) ++
       Enum.map(switches, &Map.put(&1, :section, "switches"))}
  end

  # A spacecraft's own extra route (DECISIONS #3; lead + ux U79, 11-16). downlink and uplink are
  # required so the create form opens on their defaults (primary / none); the kind maps them to
  # legs. Words are ux's.
  def fields("spacecraft_route", organization_id, mission_id) do
    stations = GroundStationStore.list_ground_stations(organization_id, mission_id)
    station_names = Map.new(stations, &{&1.ground_station_id, &1.display_name})

    roles =
      Enum.map(
        [{"none", "Not used"}, {"primary", "Primary"}] ++
          [{"candidate", "Candidate"}, {"contributing", "Contributing"}],
        fn {value, label} -> %{value: value, label: label} end
      )

    {:ok,
     [
       "spacecraft_id"
       |> field("Spacecraft", :enum,
         required: true,
         enum:
           organization_id
           |> SpacecraftStore.list_spacecraft(mission_id)
           |> Enum.map(&%{value: &1.spacecraft_id, label: &1.display_name})
       )
       |> Map.put(:create_only, true),
       field("ground_station_id", "Station", :enum,
         required: true,
         enum: Enum.map(stations, &%{value: &1.ground_station_id, label: station_label(&1)})
       ),
       field("transport_id", "Transport", :enum,
         enum:
           organization_id
           |> TransportStore.list_transports(mission_id)
           |> Enum.reject(&is_nil(&1.ground_station_id))
           |> Enum.map(
             &%{
               value: &1.transport_id,
               label: "#{&1.display_name} · #{station_names[&1.ground_station_id]}"
             }
           ),
         help: "Leave empty to use the station's transport for each direction."
       ),
       field("downlink", "Downlink", :enum, required: true, enum: roles, default: "primary"),
       field("uplink", "Uplink", :enum, required: true, enum: roles, default: "none"),
       field("display_name", "Route name", :string,
         range: %{max: 200},
         help:
           "Leave empty for “{station} · {spacecraft}”. You can use {station}, {spacecraft} " <>
             "and {scid}."
       ),
       field("purpose_label", "Purpose", :string,
         range: %{max: 200},
         help: "Shown with the route, e.g. Anomaly recovery."
       )
     ]}
  end

  def fields(kind, _organization_id, _mission_id), do: fields(kind)

  defp station_label(%{code: code, display_name: name}) when is_binary(code) and code != "",
    do: "#{name} · #{code}"

  defp station_label(station), do: station.display_name

  @spec fields(binary()) :: {:ok, [map()]} | {:error, :unknown_kind}
  def fields("transport") do
    {:ok,
     [
       field("display_name", "Name", :string, required: true, range: %{min: 1, max: 200}),
       field("transport_kind", "Kind", :enum,
         required: true,
         default: "tcp_socket",
         enum: Enum.map(TransportKind.all(), &%{value: &1.form_value, label: &1.label})
       )
     ] ++ configuration_fields()}
  end

  # #77 stage 1 (domain 5504322a8): one derived point. `point_id` is set on create only;
  # `metadata` isn't edited here (stored as is).
  def fields("derived_telemetry") do
    {:ok,
     [
       field("point_id", "Point ID", :string,
         required: true,
         range: %{min: 1, max: 240},
         help: "A qualified id such as DERIVED.SOC. It can't change after the point is added."
       )
       |> Map.put(:create_only, true),
       field("point_name", "Name", :string, range: %{min: 1, max: 240}),
       field("expression", "Expression", :text,
         required: true,
         range: %{min: 1, max: 8192},
         help: "Stateless, over qualified point ids (PACKET.field)."
       )
     ]}
  end

  # #77 stage 2 (domain c495f6d9f): one limit set for one point. The point and set are fixed
  # after create; thresholds are optional numbers, red low ≤ yellow low < yellow high ≤ red high.
  def fields("limit_definition") do
    point =
      "point_id"
      |> field("Point", :string,
        required: true,
        range: %{min: 1, max: 240},
        help: "A catalog point or a live derived point."
      )
      |> Map.put(:create_only, true)

    set =
      "limit_set_name"
      |> field("Limit set", :string,
        required: true,
        default: "DEFAULT",
        range: %{min: 1, max: 120}
      )
      |> Map.put(:create_only, true)

    thresholds =
      for {key, label} <- [
            {"red_low", "Red low"},
            {"yellow_low", "Yellow low"},
            {"yellow_high", "Yellow high"},
            {"red_high", "Red high"}
          ],
          do: field("thresholds." <> key, label, :number, [])

    {:ok, [point, set | thresholds]}
  end

  def fields(_kind), do: {:error, :unknown_kind}

  defp profile_section(section, catalog_choices) do
    Enum.map(section.fields, fn schema_field ->
      enum =
        if schema_field.path == "catalog_revision_id" and catalog_choices != [],
          do: catalog_choices,
          else: schema_field.enum

      schema_field.path
      |> field(schema_field.label, schema_field.type,
        unit: schema_field.unit,
        enum: enum,
        range: schema_field.range,
        default: schema_field.default,
        required: schema_field.path in @profile_required,
        help: schema_field.help
      )
      |> Map.put(:section, Atom.to_string(section.key))
    end)
  end

  defp configuration_fields do
    TransportKind.all()
    |> Enum.flat_map(fn definition ->
      definition.configuration.sections
      |> Enum.flat_map(& &1.fields)
      |> Enum.map(&configuration_field(&1, definition.form_value))
    end)
  end

  defp configuration_field(definition_field, transport_kind) do
    key = Map.get(@config_keys, definition_field.field, to_string(definition_field.field))

    boolean? = definition_field.field in @boolean_fields
    type = if boolean?, do: :boolean, else: type(definition_field.type)

    field("configuration." <> key, definition_field.label, type,
      required: definition_field.required,
      default:
        if(boolean?,
          do: definition_field.default == "true",
          else: blank_to_nil(definition_field.default)
        ),
      enum: if(boolean?, do: nil, else: enum(definition_field.options)),
      range: range(definition_field.min, definition_field.max),
      help: definition_field.help,
      visible_when: visible_when(definition_field.visible_when, transport_kind)
    )
  end

  defp visible_when(nil, transport_kind),
    do: %{path: "transport_kind", equals: transport_kind}

  defp visible_when(%{field: field, equals: value}, _transport_kind),
    do: %{path: "configuration." <> Map.get(@config_keys, field, to_string(field)), equals: value}

  defp type(:select), do: :enum
  defp type(:number), do: :integer
  defp type(:checkbox), do: :boolean
  defp type(_text), do: :string

  defp enum([]), do: nil

  defp enum(options),
    do: Enum.map(options, fn {label, value} -> %{value: value, label: label} end)

  defp range(nil, nil), do: nil
  defp range(min, max), do: %{min: min, max: max}

  defp field(path, label, type, opts) do
    %{
      path: path,
      label: label,
      type: type,
      unit: Keyword.get(opts, :unit),
      enum: Keyword.get(opts, :enum),
      range: Keyword.get(opts, :range),
      default: Keyword.get(opts, :default),
      required: Keyword.get(opts, :required, false),
      help: Keyword.get(opts, :help),
      visible_when: Keyword.get(opts, :visible_when)
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
