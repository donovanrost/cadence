defmodule Cadence.Applications.Spacecraft.ActionProvider do
  @moduledoc "Application-owned action adapter for Spacecraft identity and profile surfaces."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.ActionContractLedger
  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext, TelemetryDecom}
  alias Cadence.Auth.Scope
  alias Cadence.Missions
  alias Cadence.Spacecraft, as: SpacecraftAsset
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType, as: SpacecraftProfile
  alias Cadence.SpacecraftTypeStore

  @surface_action_bindings [
    {"new", 1, "validate"},
    {"new", 1, "save"},
    {"profile_new", 1, "validate"},
    {"profile_new", 1, "save"},
    {"edit", 1, "validate"},
    {"edit", 1, "save"},
    {"applications", 1, "install"},
    {"applications", 1, "disable"},
    {"applications", 1, "uninstall"},
    {"telemetry_decom", 1, "save_configuration"},
    {"telemetry_decom", 1, "request_activation"},
    {"telemetry_decom", 1, "disable"}
  ]

  @impl true
  def application_key, do: "spacecraft"

  @doc "Returns the frozen provider-owned surface/action binding ledger."
  @spec surface_action_bindings() :: [{binary(), pos_integer(), binary()}]
  def surface_action_bindings, do: @surface_action_bindings

  @doc "Validates that every binding row is unique and well formed."
  @spec validate_bindings(list()) :: :ok | {:error, atom()}
  def validate_bindings(bindings) when is_list(bindings) do
    valid? =
      Enum.all?(bindings, fn
        {surface_id, surface_version, action_id} ->
          is_binary(surface_id) and surface_id != "" and
            is_integer(surface_version) and surface_version > 0 and
            is_binary(action_id) and action_id != ""

        _other ->
          false
      end)

    cond do
      not valid? -> {:error, :invalid_action_bindings}
      length(bindings) != length(Enum.uniq(bindings)) -> {:error, :duplicate_action_bindings}
      true -> :ok
    end
  end

  def validate_bindings(_bindings), do: {:error, :invalid_action_bindings}

  @impl true
  def execute(%Scope{} = scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    with :ok <- ensure_surface_binding(request) do
      execute_action(scope, host_context, request)
    end
  end

  defp execute_action(
         %Scope{organization_id: organization_id},
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{action_id: "validate", params: params}
       ) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         :ok <- validate_form(params) do
      {:ok, %{"valid" => true}}
    end
  end

  defp execute_action(
         %Scope{organization_id: organization_id},
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{action_id: "validate", params: params}
       ) do
    with {:ok, _spacecraft} <-
           SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id),
         :ok <- validate_form(params) do
      {:ok, %{"valid" => true}}
    end
  end

  defp execute_action(
         %Scope{organization_id: organization_id},
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{action_id: "save", params: params}
       ) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      save_mission_form(organization_id, mission_id, params)
    end
  end

  defp execute_action(
         %Scope{organization_id: organization_id},
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{action_id: "save", params: params}
       ) do
    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id),
         {:ok, updated} <-
           update_spacecraft(organization_id, spacecraft, nested(params, "spacecraft")) do
      {:ok, %{"spacecraftId" => updated.spacecraft_id, "displayName" => updated.display_name}}
    end
  end

  defp execute_action(
         %Scope{organization_id: organization_id},
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{action_id: "save_configuration", params: params}
       ) do
    TelemetryDecom.configure(
      organization_id,
      mission_id,
      spacecraft_id,
      nested_or_self(params, "telemetry_decom")
    )
  end

  defp execute_action(
         %Scope{} = scope,
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{action_id: "request_activation"}
       ) do
    TelemetryDecom.request_mission_apply(scope, mission_id, spacecraft_id)
  end

  defp execute_action(
         %Scope{organization_id: organization_id},
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{action_id: "disable", params: params}
       ) do
    case Map.get(params, "key") || Map.get(params, :key) do
      key when is_binary(key) and key != "" ->
        {:error, {:local_application_lifecycle_boundary, key}}

      _other ->
        TelemetryDecom.disable(organization_id, mission_id, spacecraft_id)
    end
  end

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{action_id: action_id})
       when action_id in ["install", "uninstall"],
       do: {:error, :local_application_lifecycle_boundary}

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :application_action_scope_required}

  defp ensure_surface_binding(%ActionRequest{} = request),
    do: ActionContractLedger.admit(request, __MODULE__)

  @impl true
  def result(%SpacecraftAsset{} = spacecraft),
    do: %{"spacecraftId" => spacecraft.spacecraft_id, "displayName" => spacecraft.display_name}

  def result(%SpacecraftProfile{} = profile),
    do: %{"profileId" => profile.spacecraft_type_id, "version" => profile.version}

  def result(value) when is_map(value), do: value
  def result(_value), do: nil

  defp save_mission_form(organization_id, mission_id, params) do
    cond do
      is_map(Map.get(params, "spacecraft")) ->
        with {:ok, spacecraft} <- build_spacecraft(mission_id, Map.fetch!(params, "spacecraft")),
             {:ok, version} <-
               profile_version(organization_id, mission_id, spacecraft.spacecraft_type_id),
             spacecraft <- %SpacecraftAsset{spacecraft | spacecraft_type_version: version},
             {:ok, saved} <- SpacecraftStore.persist_spacecraft(organization_id, spacecraft) do
          {:ok, %{"spacecraftId" => saved.spacecraft_id, "displayName" => saved.display_name}}
        end

      is_map(Map.get(params, "spacecraft_type")) ->
        with {:ok, profile} <- build_profile(mission_id, Map.fetch!(params, "spacecraft_type")),
             {:ok, saved} <- SpacecraftTypeStore.persist_spacecraft_type(organization_id, profile) do
          {:ok, %{"profileId" => saved.spacecraft_type_id, "version" => saved.version}}
        end

      true ->
        {:error, invalid_form("spacecraft")}
    end
  end

  defp update_spacecraft(organization_id, %SpacecraftAsset{} = spacecraft, attrs) do
    with {:ok, display_name} <- required_text(attrs, "display_name", "Display Name"),
         {:ok, scid} <- parse_scid(attrs),
         {:ok, type_id} <- optional_text(attrs, "spacecraft_type_id"),
         {:ok, version} <- profile_version(organization_id, spacecraft.mission_id, type_id) do
      SpacecraftStore.update_spacecraft(organization_id, %SpacecraftAsset{
        spacecraft
        | display_name: display_name,
          scid: scid,
          spacecraft_type_id: type_id,
          spacecraft_type_version: version
      })
    end
  end

  defp build_spacecraft(mission_id, attrs) do
    with {:ok, display_name} <- required_text(attrs, "display_name", "Display Name"),
         {:ok, scid} <- parse_scid(attrs),
         {:ok, type_id} <- optional_text(attrs, "spacecraft_type_id") do
      {:ok,
       SpacecraftAsset.new(%{
         mission_id: mission_id,
         display_name: display_name,
         scid: scid,
         spacecraft_type_id: type_id
       })}
    end
  end

  defp build_profile(mission_id, attrs) do
    with {:ok, display_name} <- required_text(attrs, "display_name", "Display Name"),
         {:ok, downlink} <- required_enum(attrs, "downlink_protocol", ["tm", "aos", "uslp"]),
         {:ok, uplink} <- required_enum(attrs, "uplink_protocol", ["tc", "uslp"]),
         {:ok, frame_size} <- required_integer(attrs, "frame_size", "Transfer Frame Size") do
      {:ok,
       SpacecraftProfile.new(%{
         mission_id: mission_id,
         display_name: display_name,
         downlink_protocol: downlink,
         uplink_protocol: uplink,
         frame_parameters: Map.put(frame_parameters(attrs), "frame_size", frame_size),
         applications: Map.get(attrs, "applications", %{})
       })}
    end
  end

  defp profile_version(_organization_id, _mission_id, nil), do: {:ok, nil}

  defp profile_version(organization_id, mission_id, type_id) do
    case SpacecraftTypeStore.fetch_spacecraft_type(organization_id, mission_id, type_id) do
      {:ok, profile} -> {:ok, profile.version}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_form(params) do
    case nested(params, "spacecraft") do
      attrs when is_map(attrs) -> validate_display_name(attrs)
      _other -> validate_profile_form(params)
    end
  end

  defp validate_profile_form(params) do
    case nested(params, "spacecraft_type") do
      attrs when is_map(attrs) -> validate_display_name(attrs)
      _other -> {:error, invalid_form("spacecraft")}
    end
  end

  defp validate_display_name(attrs) do
    with {:ok, _name} <- required_text(attrs, "display_name", "Display Name"), do: :ok
  end

  defp frame_parameters(attrs) do
    %{
      "frame_size" => integer_or_zero(attrs, "frame_size"),
      "secondary_header_length" => integer_or_zero(attrs, "secondary_header_length"),
      "insert_zone_length" => integer_or_zero(attrs, "insert_zone_length"),
      "truncated_primary_header" =>
        Map.get(attrs, "truncated_primary_header", "false") in [true, "true"],
      "ocf_length" => integer_or_zero(attrs, "ocf_length")
    }
  end

  defp parse_scid(attrs) do
    case Map.get(attrs, "scid", Map.get(attrs, :scid)) do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _other -> {:error, invalid_form("scid")}
        end

      _other ->
        {:error, invalid_form("scid")}
    end
  end

  defp required_integer(attrs, key, label) do
    case Integer.parse(to_string(Map.get(attrs, key, ""))) do
      {value, ""} when value > 0 -> {:ok, value}
      _other -> {:error, invalid_form(label)}
    end
  end

  defp integer_or_zero(attrs, key) do
    case Integer.parse(to_string(Map.get(attrs, key, "0"))) do
      {value, ""} when value >= 0 -> value
      _other -> 0
    end
  end

  defp required_enum(attrs, key, allowed) do
    value = Map.get(attrs, key)
    if value in allowed, do: {:ok, value}, else: {:error, invalid_form(key)}
  end

  defp required_text(attrs, key, label) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, invalid_form(label)},
          else: {:ok, String.trim(value)}

      _other ->
        {:error, invalid_form(label)}
    end
  end

  defp optional_text(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      _other -> {:error, invalid_form(key)}
    end
  end

  defp nested(params, key) when is_map(params), do: Map.get(params, key, %{})
  defp nested(_params, _key), do: %{}

  defp nested_or_self(params, key) do
    case nested(params, key) do
      %{} = value when map_size(value) > 0 -> value
      _other -> params
    end
  end

  defp invalid_form(field),
    do: %ActionFailure{
      code: "invalid_field",
      message: "#{field} is invalid.",
      field: to_string(field)
    }

  @impl true
  def configuration_reference(_request, _result), do: nil
end
