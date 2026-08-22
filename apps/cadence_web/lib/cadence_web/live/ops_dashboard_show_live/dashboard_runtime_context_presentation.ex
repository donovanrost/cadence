defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextPresentation do
  @moduledoc false

  @context_results 20

  def build(assigns) do
    mission = matching_mission(assigns.current_mission, assigns.query)
    spacecraft = matching_spacecraft(assigns.spacecraft, assigns.query)
    contacts = matching_contacts(assigns)
    source_endpoints = matching_source_endpoints(assigns)
    ground_stations = matching_ground_stations(assigns)
    transports = matching_transports(assigns)
    links = matching_links(assigns)

    %{
      selected_label: selected_context_label(assigns),
      selected_scope_kind: Map.get(assigns, :context_scope_kind),
      selected_scope_id: Map.get(assigns, :context_scope_id),
      selected_scope_ids: Map.get(assigns, :context_scope_ids, []),
      mission: mission,
      spacecraft: spacecraft,
      contacts: contacts,
      source_endpoints: source_endpoints,
      ground_stations: ground_stations,
      transports: transports,
      links: links,
      batch_actions:
        batch_actions(%{
          "spacecraft" => spacecraft,
          "contact" => contacts,
          "source_endpoint" => source_endpoints,
          "ground_station" => ground_stations,
          "transport" => transports,
          "link" => links
        }),
      no_matches?:
        no_matches?(
          mission,
          spacecraft,
          contacts,
          source_endpoints,
          ground_stations,
          transports,
          links
        )
    }
  end

  defp matching_mission(nil, _query), do: nil
  defp matching_mission(_mission, ""), do: nil

  defp matching_mission(mission, query) do
    if mission_matches?(mission, query) do
      %{id: Map.get(mission, :mission_id), label: mission_display_name(mission)}
    end
  end

  defp no_matches?(
         mission,
         spacecraft,
         contacts,
         source_endpoints,
         ground_stations,
         transports,
         links
       ) do
    is_nil(mission) and spacecraft == [] and contacts == [] and source_endpoints == [] and
      ground_stations == [] and transports == [] and links == []
  end

  defp batch_actions(result_groups) when is_map(result_groups) do
    result_groups
    |> Enum.flat_map(fn {scope_kind, results} ->
      ids =
        results
        |> Enum.map(&result_id(scope_kind, &1))
        |> Enum.filter(&present_text?/1)
        |> Enum.uniq()

      case ids do
        [_one] ->
          []

        ids when ids != [] ->
          [
            %{
              scope_kind: scope_kind,
              scope_ids: ids,
              scope_ids_text: Enum.join(ids, ","),
              count: length(ids),
              label: "#{length(ids)} #{scope_kind_plural_label(%{}, scope_kind)}"
            }
          ]

        [] ->
          []
      end
    end)
    |> Enum.sort_by(& &1.scope_kind)
  end

  defp result_id("spacecraft", result), do: Map.get(result, :spacecraft_id)
  defp result_id(_scope_kind, result), do: Map.get(result, :id)

  defp present_text?(value), do: not is_nil(present_text(value))

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil

  defp selected_context_label(
         %{context_scope_kind: scope_kind, context_scope_ids: scope_ids} = assigns
       )
       when is_binary(scope_kind) and is_list(scope_ids) and length(scope_ids) > 1 do
    "#{length(scope_ids)} #{scope_kind_plural_label(assigns, scope_kind)}"
  end

  defp selected_context_label(
         %{context_scope_kind: "mission", context_scope_id: scope_id} = assigns
       )
       when is_binary(scope_id) do
    case assigns.current_mission do
      %{mission_id: ^scope_id} = mission -> mission_display_name(mission)
      _mission -> scope_label("mission", scope_id)
    end
  end

  defp selected_context_label(
         %{context_scope_kind: "contact", context_scope_id: scope_id} = assigns
       )
       when is_binary(scope_id),
       do: contact_name(assigns, scope_id)

  defp selected_context_label(
         %{context_scope_kind: "spacecraft", context_scope_id: scope_id} = assigns
       )
       when is_binary(scope_id),
       do: spacecraft_name(assigns.spacecraft, scope_id)

  defp selected_context_label(
         %{context_scope_kind: "source_endpoint", context_scope_id: scope_id} = assigns
       )
       when is_binary(scope_id),
       do: source_endpoint_name(assigns.source_endpoints, scope_id)

  defp selected_context_label(
         %{context_scope_kind: "ground_station", context_scope_id: scope_id} = assigns
       )
       when is_binary(scope_id),
       do: ground_station_name(assigns, scope_id)

  defp selected_context_label(
         %{context_scope_kind: "transport", context_scope_id: scope_id} = assigns
       )
       when is_binary(scope_id),
       do: transport_name(assigns.transports, scope_id)

  defp selected_context_label(%{context_scope_kind: "link", context_scope_id: scope_id} = assigns)
       when is_binary(scope_id),
       do: link_name(assigns.link_assignments, scope_id)

  defp selected_context_label(%{context_spacecraft_id: spacecraft_id} = assigns)
       when is_binary(spacecraft_id),
       do: spacecraft_name(assigns.spacecraft, spacecraft_id)

  defp selected_context_label(%{context_scope_kind: scope_kind, context_scope_id: scope_id})
       when is_binary(scope_kind) and is_binary(scope_id),
       do: scope_label(scope_kind, scope_id)

  defp selected_context_label(_assigns), do: nil

  defp mission_matches?(_mission, ""), do: false

  defp mission_matches?(mission, query) do
    [mission_display_name(mission), Map.get(mission, :mission_id), Map.get(mission, :slug)]
    |> Enum.any?(&matches_query?(&1, query))
  end

  defp matches_query?(value, query) when is_binary(value) and is_binary(query) do
    String.contains?(String.downcase(value), String.downcase(query))
  end

  defp matches_query?(_value, _query), do: false

  defp mission_display_name(%{display_name: display_name}) when is_binary(display_name),
    do: display_name

  defp mission_display_name(%{mission_id: mission_id}) when is_binary(mission_id), do: mission_id
  defp mission_display_name(_mission), do: "Mission"

  defp scope_label(scope_kind, scope_id) do
    scope_kind
    |> String.replace("_", " ")
    |> then(&"#{&1}: #{scope_id}")
  end

  defp scope_kind_plural_label(_assigns, "spacecraft"), do: "spacecraft"
  defp scope_kind_plural_label(_assigns, "source_endpoint"), do: "source endpoints"
  defp scope_kind_plural_label(_assigns, "ground_station"), do: "ground stations"
  defp scope_kind_plural_label(_assigns, "transport"), do: "transports"
  defp scope_kind_plural_label(_assigns, "link"), do: "links"
  defp scope_kind_plural_label(_assigns, "contact"), do: "contacts"

  defp scope_kind_plural_label(_assigns, scope_kind),
    do: String.replace(scope_kind, "_", " ") <> "s"

  defp contact_name(assigns, contact_id) do
    assigns
    |> contact_results()
    |> Enum.find_value(scope_label("contact", contact_id), fn
      %{id: ^contact_id, label: label} -> label
      _contact -> nil
    end)
  end

  defp spacecraft_name(spacecraft, spacecraft_id) do
    case Enum.find(spacecraft, &(&1.spacecraft_id == spacecraft_id)) do
      nil -> spacecraft_id
      found -> found.display_name
    end
  end

  defp source_endpoint_name(source_endpoints, source_endpoint_id) do
    source_endpoints
    |> Enum.find(&(source_endpoint_value(&1, :source_endpoint_id) == source_endpoint_id))
    |> case do
      nil -> source_endpoint_id
      found -> source_endpoint_label(found)
    end
  end

  defp transport_name(transports, transport_id) do
    transports
    |> Enum.find(&(transport_value(&1, :transport_id) == transport_id))
    |> case do
      nil -> transport_id
      found -> transport_label(found)
    end
  end

  defp ground_station_name(assigns, ground_station_id) do
    assigns
    |> ground_station_results()
    |> Enum.find_value(ground_station_id, fn
      %{id: ^ground_station_id, label: label} -> label
      _ground_station -> nil
    end)
  end

  defp link_name(link_assignments, link_id) do
    link_assignments
    |> Enum.find(&(link_assignment_value(&1, :link_assignment_id) == link_id))
    |> case do
      nil -> link_id
      found -> link_label(found)
    end
  end

  defp matching_spacecraft(spacecraft, query) do
    downcased = String.downcase(query)

    spacecraft
    |> Enum.filter(fn sc ->
      String.contains?(String.downcase(sc.display_name), downcased) or
        (sc.scid != nil and String.contains?(to_string(sc.scid), downcased))
    end)
    |> Enum.take(@context_results)
  end

  defp matching_contacts(assigns) do
    query = present_text(assigns.query)

    if query do
      assigns
      |> contact_results()
      |> Enum.filter(&contact_matches?(&1, query))
      |> Enum.take(@context_results)
    else
      []
    end
  end

  defp matching_source_endpoints(assigns) do
    query = present_text(assigns.query)

    if query do
      assigns.source_endpoints
      |> Enum.map(&source_endpoint_result/1)
      |> Enum.reject(&is_nil(&1.id))
      |> Enum.filter(&resource_matches?(&1, query))
      |> Enum.take(@context_results)
    else
      []
    end
  end

  defp source_endpoint_result(source_endpoint) do
    id = source_endpoint_value(source_endpoint, :source_endpoint_id)
    source_ref = source_endpoint_value(source_endpoint, :source_ref)
    display_name = source_endpoint_value(source_endpoint, :display_name)
    spacecraft_id = source_endpoint_value(source_endpoint, :spacecraft_id)
    scid = source_endpoint_value(source_endpoint, :scid)

    %{
      id: id,
      label: source_endpoint_label(source_endpoint),
      search: [id, source_ref, display_name, spacecraft_id, scid && to_string(scid)]
    }
  end

  defp source_endpoint_label(source_endpoint) do
    id = source_endpoint_value(source_endpoint, :source_endpoint_id)
    display_name = source_endpoint_value(source_endpoint, :display_name)
    source_ref = source_endpoint_value(source_endpoint, :source_ref)

    cond do
      present_text?(display_name) and present_text?(source_ref) ->
        "#{display_name} / #{source_ref}"

      present_text?(display_name) ->
        display_name

      present_text?(source_ref) ->
        "#{source_ref} / #{id}"

      true ->
        id
    end
  end

  defp matching_ground_stations(assigns) do
    query = present_text(assigns.query)

    if query do
      assigns
      |> ground_station_results()
      |> Enum.filter(&resource_matches?(&1, query))
      |> Enum.take(@context_results)
    else
      []
    end
  end

  defp ground_station_results(assigns) do
    ground_station_results =
      Enum.map(assigns.ground_stations, &ground_station_result/1)

    source_endpoint_results =
      Enum.flat_map(assigns.source_endpoints, &source_endpoint_ground_station_results/1)

    transport_results =
      Enum.flat_map(assigns.transports, &transport_ground_station_results/1)

    (ground_station_results ++ source_endpoint_results ++ transport_results)
    |> Enum.reject(&is_nil(&1.id))
    |> Enum.uniq_by(& &1.id)
  end

  defp ground_station_result(ground_station) do
    id = ground_station_value(ground_station, :ground_station_id)
    display_name = ground_station_value(ground_station, :display_name)
    provider = ground_station_value(ground_station, :provider)
    region = ground_station_value(ground_station, :region)

    %{
      id: id,
      label: ground_station_label(ground_station),
      search: [id, display_name, provider, region]
    }
  end

  defp ground_station_label(ground_station) do
    id = ground_station_value(ground_station, :ground_station_id)
    display_name = ground_station_value(ground_station, :display_name)

    if present_text?(display_name), do: display_name, else: id
  end

  defp source_endpoint_ground_station_results(source_endpoint) do
    metadata = source_endpoint_value(source_endpoint, :metadata)

    ground_station_id =
      metadata_value(metadata, "ground_station_id") || metadata_value(metadata, "antenna_id")

    case present_text(ground_station_id) do
      nil ->
        []

      id ->
        [
          %{
            id: id,
            label: ground_station_label(id, source_endpoint_label(source_endpoint)),
            search: [
              id,
              source_endpoint_value(source_endpoint, :display_name),
              source_endpoint_value(source_endpoint, :source_endpoint_id),
              source_endpoint_value(source_endpoint, :source_ref)
            ]
          }
        ]
    end
  end

  defp transport_ground_station_results(transport) do
    metadata = transport_value(transport, :metadata)

    ground_station_id =
      metadata_value(metadata, "ground_station_id") ||
        metadata_value(metadata, "antenna_id") ||
        transport_configuration_value(transport, "ground_station_id") ||
        transport_configuration_value(transport, "antenna_id")

    case present_text(ground_station_id) do
      nil ->
        []

      id ->
        [
          %{
            id: id,
            label: ground_station_label(id, transport_label(transport)),
            search: [
              id,
              transport_value(transport, :display_name),
              transport_value(transport, :transport_id),
              transport_value(transport, :transport_kind) &&
                to_string(transport_value(transport, :transport_kind))
            ]
          }
        ]
    end
  end

  defp ground_station_label(id, source_label) do
    case present_text(source_label) do
      nil -> id
      label -> "#{id} / #{label}"
    end
  end

  defp matching_transports(assigns) do
    query = present_text(assigns.query)

    if query do
      assigns.transports
      |> Enum.map(&transport_result/1)
      |> Enum.reject(&is_nil(&1.id))
      |> Enum.filter(&resource_matches?(&1, query))
      |> Enum.take(@context_results)
    else
      []
    end
  end

  defp transport_result(transport) do
    id = transport_value(transport, :transport_id)
    display_name = transport_value(transport, :display_name)
    kind = transport_value(transport, :transport_kind)
    direction = transport_value(transport, :direction_capability)
    source_endpoint_id = transport_configuration_value(transport, "source_endpoint_id")

    %{
      id: id,
      label: transport_label(transport),
      search: [
        id,
        display_name,
        kind && to_string(kind),
        direction && to_string(direction),
        source_endpoint_id
      ]
    }
  end

  defp transport_label(transport) do
    id = transport_value(transport, :transport_id)
    display_name = transport_value(transport, :display_name)
    kind = transport_value(transport, :transport_kind)

    cond do
      present_text?(display_name) and not is_nil(kind) -> "#{display_name} / #{kind}"
      present_text?(display_name) -> display_name
      not is_nil(kind) -> "#{id} / #{kind}"
      true -> id
    end
  end

  defp matching_links(assigns) do
    query = present_text(assigns.query)

    if query do
      assigns.link_assignments
      |> Enum.map(&link_result/1)
      |> Enum.reject(&is_nil(&1.id))
      |> Enum.filter(&resource_matches?(&1, query))
      |> Enum.take(@context_results)
    else
      []
    end
  end

  defp link_result(link_assignment) do
    id = link_assignment_value(link_assignment, :link_assignment_id)
    spacecraft_id = link_assignment_value(link_assignment, :spacecraft_id)
    source_endpoint_ref = link_assignment_value(link_assignment, :source_endpoint_ref)
    path_template_id = link_assignment_value(link_assignment, :path_template_id)
    provider_path_ref = link_assignment_value(link_assignment, :provider_path_ref)
    direction = link_assignment_value(link_assignment, :direction)
    selection_role = link_assignment_value(link_assignment, :selection_role)

    %{
      id: id,
      label: link_label(link_assignment),
      search: [
        id,
        spacecraft_id,
        source_endpoint_ref,
        path_template_id,
        provider_path_ref,
        direction && to_string(direction),
        selection_role && to_string(selection_role)
      ]
    }
  end

  defp link_label(link_assignment) do
    id = link_assignment_value(link_assignment, :link_assignment_id)
    spacecraft_id = link_assignment_value(link_assignment, :spacecraft_id)
    source_endpoint_ref = link_assignment_value(link_assignment, :source_endpoint_ref)
    direction = link_assignment_value(link_assignment, :direction)

    [spacecraft_id, source_endpoint_ref, direction && to_string(direction)]
    |> Enum.filter(&present_text?/1)
    |> case do
      [] -> id
      parts -> Enum.join(parts, " / ")
    end
  end

  defp contact_results(assigns) do
    scheduled =
      assigns.scheduled_contacts
      |> Enum.map(&scheduled_contact_result/1)
      |> Enum.reject(&is_nil(&1.id))

    realized =
      assigns.realized_contacts
      |> Enum.map(&realized_contact_result/1)
      |> Enum.reject(&is_nil(&1.id))

    scheduled ++ realized
  end

  defp scheduled_contact_result(contact) do
    id = contact_value(contact, :scheduled_contact_id)
    source_endpoint_refs = contact_value(contact, :source_endpoint_refs) || []

    %{
      id: id,
      kind: "scheduled",
      label: contact_label("scheduled", id, source_endpoint_refs),
      search: [id, "scheduled" | source_endpoint_refs]
    }
  end

  defp realized_contact_result(contact) do
    id = contact_value(contact, :realized_contact_id)
    scheduled_id = contact_value(contact, :scheduled_contact_id)
    source_endpoint_refs = contact_value(contact, :source_endpoint_refs) || []

    %{
      id: id,
      kind: "realized",
      label: contact_label("realized", id, source_endpoint_refs),
      search: [id, scheduled_id, "realized" | source_endpoint_refs]
    }
  end

  defp contact_label(kind, id, source_endpoint_refs) do
    endpoint =
      source_endpoint_refs
      |> List.wrap()
      |> Enum.find(&present_text?/1)

    case endpoint do
      nil -> "#{kind} / #{id}"
      endpoint -> "#{kind} / #{id} / #{endpoint}"
    end
  end

  defp contact_matches?(%{search: search}, query) do
    Enum.any?(search, &matches_query?(&1, query))
  end

  defp resource_matches?(%{search: search}, query) do
    Enum.any?(search, &matches_query?(&1, query))
  end

  defp contact_value(contact, key) when is_map(contact),
    do: Map.get(contact, key, Map.get(contact, to_string(key)))

  defp contact_value(_contact, _key), do: nil

  defp source_endpoint_value(source_endpoint, key) when is_map(source_endpoint),
    do: Map.get(source_endpoint, key, Map.get(source_endpoint, to_string(key)))

  defp source_endpoint_value(_source_endpoint, _key), do: nil

  defp transport_value(transport, key) when is_map(transport),
    do: Map.get(transport, key, Map.get(transport, to_string(key)))

  defp transport_value(_transport, _key), do: nil

  defp transport_configuration_value(transport, key) when is_map(transport) do
    case transport_value(transport, :configuration) do
      config when is_map(config) -> metadata_value(config, key)
      _config -> nil
    end
  end

  defp transport_configuration_value(_transport, _key), do: nil

  defp ground_station_value(ground_station, key) when is_map(ground_station),
    do: Map.get(ground_station, key, Map.get(ground_station, to_string(key)))

  defp ground_station_value(_ground_station, _key), do: nil

  defp link_assignment_value(link_assignment, key) when is_map(link_assignment),
    do: Map.get(link_assignment, key, Map.get(link_assignment, to_string(key)))

  defp link_assignment_value(_link_assignment, _key), do: nil

  defp metadata_value(metadata, key) when is_map(metadata) and is_binary(key) do
    Map.get(metadata, key, Map.get(metadata, string_key_atom(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp string_key_atom("antenna_id"), do: :antenna_id
  defp string_key_atom("ground_station_id"), do: :ground_station_id
  defp string_key_atom("source_endpoint_id"), do: :source_endpoint_id
  defp string_key_atom(_key), do: nil
end
