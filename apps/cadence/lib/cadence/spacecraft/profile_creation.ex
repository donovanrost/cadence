defmodule Cadence.Spacecraft.ProfileCreation do
  @moduledoc "Scoped profile creation independent of frontend release delivery."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.{ExtensionCatalog, Missions, SpacecraftType, SpacecraftTypeStore}

  def available_applications do
    ExtensionCatalog.available_applications_for_scope(:spacecraft)
    |> Enum.filter(&(&1.installation_policy == :optional))
  end

  def action(%Scope{mission_id: scoped} = scope, mission_id, event, input)
      when event in ["validate", "save"] and is_binary(mission_id) and
             (is_nil(scoped) or scoped == mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, attrs} <- fields(input) do
      complete(event, scope.organization_id, mission_id, attrs)
    end
  end

  def action(_scope, _mission_id, _event, _input), do: {:error, :invalid_profile_action}

  defp fields(%{"spacecraft_type" => attrs}) when is_map(attrs) do
    with {:ok, name} <- name(attrs["display_name"]),
         {:ok, downlink} <- choice(attrs, "downlink_protocol", ["tm", "aos", "uslp"]),
         {:ok, uplink} <- choice(attrs, "uplink_protocol", ["tc", "uslp"]),
         {:ok, size} <- integer(attrs, "frame_size", 1),
         {:ok, secondary} <- integer(attrs, "secondary_header_length", 0),
         {:ok, insert} <- integer(attrs, "insert_zone_length", 0),
         {:ok, truncated} <- choice(attrs, "truncated_primary_header", ["false", "true"]),
         {:ok, ocf} <- choice(attrs, "ocf_length", ["0", "4"]),
         {:ok, applications} <- applications(Map.get(attrs, "applications", %{})) do
      {:ok,
       %{
         display_name: name,
         downlink_protocol: downlink,
         uplink_protocol: uplink,
         frame_parameters: %{
           "frame_size" => size,
           "secondary_header_length" => secondary,
           "insert_zone_length" => insert,
           "truncated_primary_header" => truncated == "true",
           "ocf_length" => if(ocf == "4", do: 4, else: 0)
         },
         applications: applications
       }}
    end
  end

  defp fields(_input), do: invalid("display_name", "Enter valid profile details.")

  defp name(value) when is_binary(value) and byte_size(value) <= 800 do
    if String.valid?(value) and String.length(String.trim(value)) in 1..200,
      do: {:ok, String.trim(value)},
      else: invalid("display_name", "Enter a name within 200 characters.")
  end

  defp name(_value), do: invalid("display_name", "Enter a name within 200 characters.")

  defp integer(attrs, field, minimum) do
    value = Map.get(attrs, field, if(minimum == 0, do: "0", else: ""))
    value = if is_integer(value), do: Integer.to_string(value), else: value

    if is_binary(value) and byte_size(value) <= 10 do
      case Integer.parse(value) do
        {number, ""} when number >= minimum and number <= 2_147_483_647 -> {:ok, number}
        _ -> invalid(field, "Enter a whole number from #{minimum} to 2147483647.")
      end
    else
      invalid(field, "Enter a whole number from #{minimum} to 2147483647.")
    end
  end

  defp choice(attrs, field, allowed) do
    # Defaults retain the historical form's optional fields for older callers.
    default =
      case field do
        "truncated_primary_header" -> "false"
        "ocf_length" -> "0"
        _ -> nil
      end

    value = Map.get(attrs, field, default)
    if value in allowed, do: {:ok, value}, else: invalid(field, "Select an available value.")
  end

  defp applications(selected) when is_map(selected) and map_size(selected) <= 64 do
    allowed = MapSet.new(available_applications(), & &1.application_key)

    if Enum.all?(selected, fn {key, value} ->
         is_binary(key) and MapSet.member?(allowed, key) and value in ["1", true, %{}]
       end) do
      {:ok, Map.new(selected, fn {key, _} -> {key, %{}} end)}
    else
      invalid("applications", "Select only available optional applications.")
    end
  end

  defp applications(_value),
    do: invalid("applications", "Select only available optional applications.")

  defp complete("validate", _organization_id, _mission_id, _attrs), do: {:ok, %{"valid" => true}}

  defp complete("save", organization_id, mission_id, attrs) do
    with {:ok, profile} <-
           SpacecraftTypeStore.persist_spacecraft_type(
             organization_id,
             SpacecraftType.new(Map.put(attrs, :mission_id, mission_id))
           ) do
      {:ok,
       %{
         "profileId" => profile.spacecraft_type_id,
         "version" => profile.version,
         "href" => "/missions/#{mission_id}/spacecraft/profiles"
       }}
    end
  end

  defp invalid(field, message), do: {:error, %{field => [message]}}
end
