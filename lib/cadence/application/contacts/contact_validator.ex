defmodule Cadence.Application.Contacts.ContactValidator do
  @moduledoc """
  Validates planned contacts for scheduling conflicts and hard resolvability issues.
  """

  alias Cadence.Application.Contacts.ContactQueries
  alias Cadence.Application.GroundStations.GroundStationProfileQueries
  alias Cadence.Transports

  @type conflict :: %{
          type: atom(),
          with: String.t(),
          resource: map(),
          window: map()
        }

  @type issue :: %{
          type: atom(),
          message: String.t(),
          details: map()
        }

  @spec validate(String.t(), String.t(), list() | nil) :: %{
          conflicts: map(),
          hard_errors: map()
        }
  def validate(organization_id, mission_id, contacts \\ nil) do
    contacts =
      contacts
      |> case do
        nil -> ContactQueries.list(organization_id, mission_id: mission_id, state: :planned)
        list -> List.wrap(list)
      end
      |> Enum.filter(&(&1.state == :planned))

    profiles = GroundStationProfileQueries.list_enabled_for_mission(mission_id)
    profiles_by_station = build_profiles_by_station(profiles)

    transports = Transports.list_interfaces(organization_id, mission_id)
    transports_by_id = Map.new(transports, fn transport -> {transport.id, transport} end)

    %{
      conflicts: detect_conflicts(contacts),
      hard_errors: detect_hard_errors(contacts, profiles_by_station, transports_by_id)
    }
  end

  defp detect_conflicts(contacts) do
    antenna_conflicts =
      contacts
      |> Enum.filter(&valid_window?/1)
      |> Enum.group_by(fn contact ->
        {contact.ground_station_target_id, contact.antenna_id}
      end)
      |> Enum.reduce(%{}, fn {{ground_station_id, antenna_id}, grouped}, acc ->
        resource = %{ground_station_target_id: ground_station_id, antenna_id: antenna_id}
        add_overlaps(acc, grouped, :antenna_conflict, resource)
      end)

    spacecraft_conflicts =
      contacts
      |> Enum.filter(&valid_window?/1)
      |> Enum.group_by(& &1.spacecraft_target_id)
      |> Enum.reduce(%{}, fn {spacecraft_id, grouped}, acc ->
        resource = %{spacecraft_target_id: spacecraft_id}
        add_overlaps(acc, grouped, :spacecraft_conflict, resource)
      end)

    merge_conflicts(antenna_conflicts, spacecraft_conflicts)
  end

  defp add_overlaps(conflicts, contacts, type, resource) do
    sorted = Enum.sort_by(contacts, & &1.start_time)

    build_overlap_conflicts(conflicts, sorted, type, resource)
  end

  defp build_overlap_conflicts(conflicts, [], _type, _resource), do: conflicts

  defp build_overlap_conflicts(conflicts, [contact | rest], type, resource) do
    conflicts =
      Enum.reduce(rest, conflicts, fn other, acc ->
        if overlaps?(contact, other) do
          acc
          |> record_conflict(contact, other, type, resource)
          |> record_conflict(other, contact, type, resource)
        else
          acc
        end
      end)

    build_overlap_conflicts(conflicts, rest, type, resource)
  end

  defp record_conflict(conflicts, contact, other, type, resource) do
    conflict = %{
      type: type,
      with: other.id,
      resource: resource,
      window: %{start_time: other.start_time, end_time: other.end_time}
    }

    Map.update(conflicts, contact.id, [conflict], fn list -> [conflict | list] end)
  end

  defp merge_conflicts(conflicts, other_conflicts) do
    Map.merge(conflicts, other_conflicts, fn _key, left, right -> left ++ right end)
  end

  defp overlaps?(contact, other) do
    DateTime.compare(contact.start_time, other.end_time) == :lt and
      DateTime.compare(other.start_time, contact.end_time) == :lt
  end

  defp valid_window?(contact) do
    not is_nil(contact.start_time) and not is_nil(contact.end_time)
  end

  defp detect_hard_errors(contacts, profiles_by_station, transports_by_id) do
    Enum.reduce(contacts, %{}, fn contact, acc ->
      case hard_errors_for_contact(contact, profiles_by_station, transports_by_id) do
        [] -> acc
        errors -> Map.put(acc, contact.id, errors)
      end
    end)
  end

  defp hard_errors_for_contact(contact, profiles_by_station, transports_by_id) do
    case resolve_transport_ids(contact, profiles_by_station) do
      {:ok, transport_ids} ->
        validate_transport_ids(transport_ids, transports_by_id)

      {:error, issue} ->
        [issue]
    end
  end

  defp resolve_transport_ids(contact, profiles_by_station) do
    profile = Map.get(profiles_by_station, contact.ground_station_target_id)

    with {:profile, %{} = profile} <- {:profile, profile},
         {:antenna, %{} = antenna} <- {:antenna, find_antenna(profile, contact.antenna_id)},
         {:transport_ids, transport_ids} <-
           {:transport_ids, transport_ids_for_direction(contact.direction, antenna)} do
      {:ok, transport_ids}
    else
      {:profile, nil} ->
        {:error, error(:profile_not_found, "No enabled ground station profile found", %{})}

      {:antenna, nil} ->
        {:error,
         error(:antenna_not_found, "No matching antenna in profile", %{
           antenna_id: contact.antenna_id
         })}

      {:transport_ids, {:error, code, details}} ->
        {:error, error(code, "Missing transport id", details)}
    end
  end

  defp validate_transport_ids(transport_ids, transports_by_id) do
    Enum.reduce(transport_ids, [], fn transport_id, errors ->
      case transport_issue_for_id(transport_id, transports_by_id) do
        nil -> errors
        issue -> [issue | errors]
      end
    end)
  end

  defp transport_issue_for_id(transport_id, transports_by_id) do
    case Map.get(transports_by_id, transport_id) do
      nil ->
        error(:transport_not_found, "Transport not found", %{id: transport_id})

      %{enabled: true} ->
        nil

      _transport ->
        error(:transport_disabled, "Transport disabled", %{id: transport_id})
    end
  end

  defp error(type, message, details), do: %{type: type, message: message, details: details}

  defp build_profiles_by_station(profiles) do
    profiles
    |> Enum.group_by(& &1.ground_station_target_id)
    |> Map.new(fn {ground_station_id, grouped} ->
      {ground_station_id, select_profile(grouped)}
    end)
  end

  defp select_profile([]), do: nil

  defp select_profile(profiles) do
    profiles
    |> Enum.sort_by(
      fn profile ->
        {profile.inserted_at || ~U[0001-01-01 00:00:00Z], profile.name || ""}
      end,
      fn {left_dt, left_name}, {right_dt, right_name} ->
        case DateTime.compare(left_dt, right_dt) do
          :gt -> true
          :lt -> false
          :eq -> left_name <= right_name
        end
      end
    )
    |> List.first()
  end

  defp find_antenna(profile, antenna_id) do
    profile
    |> Map.get(:resources, %{})
    |> get_key("antennas", [])
    |> Enum.find(fn item -> to_string(get_key(item, "id")) == to_string(antenna_id) end)
  end

  defp transport_ids_for_direction(direction, antenna) do
    activation = get_key(antenna, "activation", %{})

    case direction do
      :uplink ->
        fetch_transport_ids([get_key(activation, "uplink_transport_id")], "uplink_transport_id")

      :downlink ->
        fetch_transport_ids(
          [get_key(activation, "downlink_transport_id")],
          "downlink_transport_id"
        )

      :bidirectional ->
        fetch_transport_ids(
          [
            get_key(activation, "uplink_transport_id"),
            get_key(activation, "downlink_transport_id")
          ],
          "uplink_transport_id/downlink_transport_id"
        )

      _ ->
        {:error, :direction_invalid, %{direction: direction}}
    end
  end

  defp fetch_transport_ids(required_ids, missing_key) do
    transport_ids = Enum.reject(required_ids, &is_nil/1)

    if Enum.count(transport_ids) != Enum.count(required_ids) do
      {:error, :missing_transport_id, %{key: missing_key}}
    else
      transport_ids
    end
  end

  defp get_key(map, key, default \\ nil) do
    cond do
      is_map(map) and Map.has_key?(map, key) ->
        Map.get(map, key)

      (is_map(map) and is_binary(key) and atom_key_for(key)) &&
          Map.has_key?(map, atom_key_for(key)) ->
        Map.get(map, atom_key_for(key))

      true ->
        default
    end
  end

  defp atom_key_for("antennas"), do: :antennas
  defp atom_key_for("activation"), do: :activation
  defp atom_key_for("id"), do: :id
  defp atom_key_for("uplink_transport_id"), do: :uplink_transport_id
  defp atom_key_for("downlink_transport_id"), do: :downlink_transport_id
  defp atom_key_for(_), do: nil
end
