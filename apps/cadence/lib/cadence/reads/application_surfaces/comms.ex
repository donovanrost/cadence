defmodule Cadence.Reads.ApplicationSurfaces.Comms do
  @moduledoc "Trusted, read-only mission Comms surfaces for the application host."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{GroundStationStore, RoutingRuleStore, TransportStore}

  @application_key "comms"
  @application_version 1
  @surface_version 1
  @page_size 50
  @max_text_length 240
  @max_findings 20

  @query_ids %{
    "overview" => "cadence.comms.overview",
    "validation" => "cadence.comms.validation",
    "transports" => "cadence.comms.transports",
    "transport" => "cadence.comms.transport",
    "routing" => "cadence.comms.routing",
    "routing_detail" => "cadence.comms.routing_detail",
    "ground_stations" => "cadence.comms.ground_stations",
    "ground_station" => "cadence.comms.ground_station"
  }

  @list_surfaces ["transports", "routing", "ground_stations"]
  @detail_params %{
    "transport" => "transport_id",
    "routing_detail" => "routing_rule_id",
    "ground_station" => "ground_station_id"
  }

  @impl true
  def load(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        %SurfaceQueryRequest{} = request
      ) do
    guarded(fn -> load_surface(current_scope, host_context, request) end)
  end

  defp load_surface(
         %Scope{organization_id: organization_id, mission_id: scope_mission_id} = current_scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         %SurfaceQueryRequest{
           application_key: @application_key,
           application_version: @application_version,
           surface_id: surface_id,
           surface_version: @surface_version,
           query_id: query_id,
           query_version: 1,
           params: params
         }
       )
       when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
              mission_id != "" and is_map(params) and
              (is_nil(scope_mission_id) or scope_mission_id == mission_id) do
    with :ok <- validate_query_identity(surface_id, query_id),
         :ok <- validate_params(surface_id, params),
         {:ok, mission} <- fetch_mission(organization_id, mission_id),
         :ok <- ensure_mission_scope(mission, organization_id, mission_id),
         {:ok, resources} <- read_resources(organization_id, mission_id) do
      dispatch_surface(current_scope, mission, resources, surface_id, params)
    end
  end

  defp load_surface(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp dispatch_surface(current_scope, mission, resources, "overview", _params) do
    {:ok,
     trusted_payload(
       "overview",
       mission.mission_id,
       nil,
       overview_data(current_scope, mission, resources)
     )}
  end

  defp dispatch_surface(current_scope, mission, resources, "validation", _params) do
    with {:ok, findings} <- validation_findings(current_scope, mission.mission_id, resources) do
      {:ok,
       trusted_payload(
         "validation",
         mission.mission_id,
         nil,
         validation_data(findings, mission.mission_id)
       )}
    end
  end

  defp dispatch_surface(_current_scope, mission, resources, "transports", params) do
    with {:ok, list} <- list_options(params, "display_name") do
      transports = filter_and_sort(resources.transports, list, &transport_search_values/1)

      {:ok,
       trusted_payload(
         "transports",
         mission.mission_id,
         nil,
         collection_data("Transports", transports, list, &transport_row(&1, mission.mission_id))
       )}
    end
  end

  defp dispatch_surface(_current_scope, mission, resources, "routing", params) do
    with {:ok, list} <- list_options(params, "display_name") do
      spacecraft_by_id = Map.new(resources.spacecraft, &{&1.spacecraft_id, &1})
      transports_by_id = Map.new(resources.transports, &{&1.transport_id, &1})

      routing_rules =
        filter_and_sort(resources.routing_rules, list, fn rule ->
          [
            rule.display_name,
            rule.purpose_label,
            Map.get(spacecraft_by_id, rule.spacecraft_id, %{}) |> Map.get(:display_name),
            Map.get(transports_by_id, rule.transport_id, %{}) |> Map.get(:display_name)
          ]
        end)

      {:ok,
       trusted_payload(
         "routing",
         mission.mission_id,
         nil,
         collection_data(
           "Routing",
           routing_rules,
           list,
           &routing_row(&1, mission.mission_id, spacecraft_by_id, transports_by_id)
         )
       )}
    end
  end

  defp dispatch_surface(_current_scope, mission, resources, "ground_stations", params) do
    with {:ok, list} <- list_options(params, "display_name") do
      ground_stations =
        filter_and_sort(resources.ground_stations, list, &ground_station_search_values/1)

      {:ok,
       trusted_payload(
         "ground_stations",
         mission.mission_id,
         nil,
         collection_data(
           "Ground Stations",
           ground_stations,
           list,
           &ground_station_row(&1, mission.mission_id)
         )
       )}
    end
  end

  defp dispatch_surface(_current_scope, mission, resources, "transport", params) do
    with {:ok, transport_id} <- subject_id(params, "transport_id"),
         {:ok, transport} <- fetch_scoped_transport(resources, transport_id) do
      {:ok,
       trusted_payload(
         "transport",
         mission.mission_id,
         transport_id,
         transport_data(transport, mission.mission_id)
       )}
    end
  end

  defp dispatch_surface(_current_scope, mission, resources, "routing_detail", params) do
    with {:ok, routing_rule_id} <- subject_id(params, "routing_rule_id"),
         {:ok, routing_rule} <- fetch_scoped_routing_rule(resources, routing_rule_id) do
      spacecraft =
        Enum.find(resources.spacecraft, &(&1.spacecraft_id == routing_rule.spacecraft_id))

      transport = Enum.find(resources.transports, &(&1.transport_id == routing_rule.transport_id))

      {:ok,
       trusted_payload(
         "routing_detail",
         mission.mission_id,
         routing_rule_id,
         routing_detail_data(routing_rule, spacecraft, transport, mission.mission_id)
       )}
    end
  end

  defp dispatch_surface(_current_scope, mission, resources, "ground_station", params) do
    with {:ok, ground_station_id} <- subject_id(params, "ground_station_id"),
         {:ok, ground_station} <- fetch_scoped_ground_station(resources, ground_station_id) do
      {:ok,
       trusted_payload(
         "ground_station",
         mission.mission_id,
         ground_station_id,
         ground_station_data(ground_station, mission.mission_id)
       )}
    end
  end

  defp dispatch_surface(_current_scope, _mission, _resources, _surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp validate_query_identity(surface_id, query_id) do
    case Map.fetch(@query_ids, surface_id) do
      {:ok, ^query_id} -> :ok
      _invalid -> {:error, :unsupported_application_surface_query}
    end
  end

  defp validate_params(surface_id, params) do
    allowed_keys =
      cond do
        surface_id in @list_surfaces ->
          MapSet.new(~w(q sort dir page))

        Map.has_key?(@detail_params, surface_id) ->
          MapSet.new([Map.fetch!(@detail_params, surface_id)])

        surface_id in ["overview", "validation"] ->
          MapSet.new()

        true ->
          MapSet.new()
      end

    keys = Map.keys(params)

    if Enum.all?(keys, &is_binary/1) and MapSet.subset?(MapSet.new(keys), allowed_keys),
      do: :ok,
      else: {:error, :unsupported_application_surface_query}
  end

  defp subject_id(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" and byte_size(value) <= 120 -> {:ok, value}
      _invalid -> {:error, :invalid_application_request}
    end
  end

  defp list_options(params, default_sort) do
    with {:ok, query} <- optional_query(params),
         {:ok, sort} <- option(params, "sort", default_sort, [default_sort]),
         {:ok, direction} <- option(params, "dir", "asc", ~w(asc desc)),
         {:ok, page} <- optional_page(params) do
      {:ok, %{q: query, sort: sort, dir: parse_direction(direction), page: page}}
    end
  end

  defp optional_query(params) do
    case Map.get(params, "q") do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value when is_binary(value) and byte_size(value) <= 120 -> {:ok, value}
      _invalid -> {:error, :invalid_application_request}
    end
  end

  defp option(params, key, default, allowed) do
    case Map.get(params, key, default) do
      value when is_binary(value) ->
        if value in allowed, do: {:ok, value}, else: {:error, :invalid_application_request}

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp optional_page(params) do
    case Map.get(params, "page") do
      nil -> {:ok, 1}
      value when is_integer(value) and value > 0 -> {:ok, value}
      value when is_binary(value) -> positive_integer(value)
      _invalid -> {:error, :invalid_application_request}
    end
  end

  defp positive_integer(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _invalid -> {:error, :invalid_application_request}
    end
  end

  defp parse_direction("asc"), do: :asc
  defp parse_direction("desc"), do: :desc

  defp filter_and_sort(items, %{q: query, dir: direction}, search_values) do
    items
    |> Enum.filter(&matches_query?(&1, query, search_values))
    |> Enum.sort_by(&sort_key/1, direction)
  end

  defp matches_query?(_item, nil, _search_values), do: true

  defp matches_query?(item, query, search_values) do
    downcased_query = String.downcase(query)

    Enum.any?(search_values.(item), fn value ->
      is_binary(value) and String.contains?(String.downcase(value), downcased_query)
    end)
  end

  defp sort_key(%{display_name: display_name} = item) do
    {String.downcase(safe_text(display_name, "")), stable_id(item)}
  end

  defp stable_id(%{transport_id: id}), do: id
  defp stable_id(%{routing_rule_id: id}), do: id
  defp stable_id(%{ground_station_id: id}), do: id

  defp collection_data(title, items, list, row_fun) do
    total_count = length(items)
    page_count = max(ceil(total_count / @page_size), 1)
    page = min(list.page, page_count)
    page_items = Enum.slice(items, (page - 1) * @page_size, @page_size)

    %{
      "title" => title,
      "items" => Enum.map(page_items, row_fun),
      "page" => page,
      "page_size" => @page_size,
      "page_count" => page_count,
      "total_count" => total_count,
      "query" => list.q,
      "sort" => list.sort,
      "dir" => Atom.to_string(list.dir)
    }
  end

  defp transport_row(transport, mission_id) do
    %{
      "id" => transport.transport_id,
      "display_name" => safe_text(transport.display_name),
      "origin" => Atom.to_string(transport.origin),
      "transport_kind" => Atom.to_string(transport.transport_kind),
      "direction_capability" => Atom.to_string(transport.direction_capability),
      "version" => transport.version,
      "href" => fallback_href(mission_id, "transport", transport.transport_id)
    }
  end

  defp routing_row(rule, mission_id, spacecraft_by_id, transports_by_id) do
    %{
      "id" => rule.routing_rule_id,
      "display_name" => safe_text(rule.display_name),
      "spacecraft_id" => rule.spacecraft_id,
      "spacecraft_name" =>
        safe_text(
          Map.get(spacecraft_by_id, rule.spacecraft_id, %{})
          |> Map.get(:display_name, rule.spacecraft_id)
        ),
      "purpose_label" => safe_text(rule.purpose_label),
      "direction" => Atom.to_string(rule.direction),
      "transport_id" => rule.transport_id,
      "transport_name" =>
        safe_text(
          Map.get(transports_by_id, rule.transport_id, %{})
          |> Map.get(:display_name, rule.transport_id)
        ),
      "role" => Atom.to_string(rule.role),
      "enabled" => rule.enabled?,
      "href" => fallback_href(mission_id, "routing_detail", rule.routing_rule_id)
    }
  end

  defp ground_station_row(ground_station, mission_id) do
    %{
      "id" => ground_station.ground_station_id,
      "display_name" => safe_text(ground_station.display_name),
      "provider" => safe_text(ground_station.provider, "Unspecified"),
      "region" => safe_text(ground_station.region, "Unspecified"),
      "href" => fallback_href(mission_id, "ground_station", ground_station.ground_station_id)
    }
  end

  defp transport_data(transport, mission_id) do
    %{
      "id" => transport.transport_id,
      "display_name" => safe_text(transport.display_name),
      "version" => transport.version,
      "lifecycle_state" => Atom.to_string(transport.lifecycle_state),
      "origin" => Atom.to_string(transport.origin),
      "transport_kind" => Atom.to_string(transport.transport_kind),
      "direction_capability" => Atom.to_string(transport.direction_capability),
      "provider_managed" => transport.origin == :provider_managed,
      "href" => fallback_href(mission_id, "transport", transport.transport_id),
      "list_href" => fallback_href(mission_id, "transports")
    }
  end

  defp routing_detail_data(rule, spacecraft, transport, mission_id) do
    %{
      "id" => rule.routing_rule_id,
      "display_name" => safe_text(rule.display_name),
      "enabled" => rule.enabled?,
      "lifecycle_state" => Atom.to_string(rule.lifecycle_state),
      "spacecraft_id" => rule.spacecraft_id,
      "spacecraft_name" => resource_display_name(spacecraft, rule.spacecraft_id),
      "purpose_label" => safe_text(rule.purpose_label),
      "direction" => Atom.to_string(rule.direction),
      "transport_id" => rule.transport_id,
      "transport_name" => resource_display_name(transport, rule.transport_id),
      "transport_version" => rule.transport_version,
      "role" => Atom.to_string(rule.role),
      "href" => fallback_href(mission_id, "routing_detail", rule.routing_rule_id),
      "list_href" => fallback_href(mission_id, "routing")
    }
  end

  defp ground_station_data(ground_station, mission_id) do
    %{
      "id" => ground_station.ground_station_id,
      "display_name" => safe_text(ground_station.display_name),
      "lifecycle_state" => Atom.to_string(ground_station.lifecycle_state),
      "provider" => safe_text(ground_station.provider, "Unspecified"),
      "region" => safe_text(ground_station.region, "Unspecified"),
      "href" => fallback_href(mission_id, "ground_station", ground_station.ground_station_id),
      "list_href" => fallback_href(mission_id, "ground_stations"),
      "edit_href" =>
        fallback_href(mission_id, "ground_station", ground_station.ground_station_id) <> "/edit"
    }
  end

  defp overview_data(current_scope, mission, resources) do
    presenter = Module.concat([CadenceWeb, CommsOverviewPresenter])

    if Code.ensure_loaded?(presenter) and function_exported?(presenter, :build, 2) do
      presenter
      |> Function.capture(:build, 2)
      |> then(& &1.(current_scope, mission))
      |> json_safe()
    else
      %{
        "overview" => %{
          "transport" => %{
            "count" => length(resources.transports),
            "rows" =>
              Enum.map(Enum.take(resources.transports, 6), &transport_row(&1, mission.mission_id)),
            "manage_href" => fallback_href(mission.mission_id, "transports")
          }
        }
      }
    end
  end

  defp validation_data(findings, mission_id) do
    findings = Enum.take(findings, @max_findings)

    %{
      "id" => "comms-validation-page",
      "title" => "Validation",
      "finding_count" => length(findings),
      "empty" => findings == [],
      "href" => fallback_href(mission_id, "validation"),
      "findings" => Enum.with_index(findings) |> Enum.map(&finding_data(&1, mission_id)),
      "finding_groups" => validation_groups(findings, mission_id),
      "status" => if(findings == [], do: "ready", else: "attention")
    }
  end

  defp validation_groups(findings, mission_id) do
    validation = Module.concat([CadenceWeb, CommsValidation])

    groups =
      if Code.ensure_loaded?(validation) and function_exported?(validation, :finding_groups, 1) do
        Function.capture(validation, :finding_groups, 1).(findings)
      else
        [%{id: "comms-validation", title: "Comms Validation", findings: findings}]
      end

    groups
    |> Enum.take(@max_findings)
    |> Enum.with_index()
    |> Enum.map(fn {group, index} -> finding_group_data(group, index, mission_id) end)
  end

  defp finding_group_data(group, index, mission_id) when is_map(group) do
    group_findings = Map.get(group, :findings, [])

    %{
      "id" => safe_text(Map.get(group, :id), "finding-group-#{index + 1}"),
      "title" => safe_text(Map.get(group, :title), "Comms findings"),
      "findings" =>
        group_findings
        |> Enum.take(@max_findings)
        |> Enum.with_index()
        |> Enum.map(&finding_data(&1, mission_id))
    }
  end

  defp finding_group_data(_group, index, _mission_id),
    do: %{"id" => "finding-group-#{index + 1}", "title" => "Comms findings", "findings" => []}

  defp finding_data({finding, index}, mission_id) when is_map(finding) do
    action_href = Map.get(finding, :action_navigate)

    %{
      "id" => safe_text(Map.get(finding, :id), "finding-#{index + 1}"),
      "title" => safe_text(Map.get(finding, :title), "Comms finding"),
      "body" => safe_text(Map.get(finding, :body), "Review the saved Comms configuration."),
      "severity" => severity_text(Map.get(finding, :severity)),
      "action_label" => safe_text(Map.get(finding, :action_label), "Review"),
      "action_href" => safe_action_href(action_href, mission_id)
    }
  end

  defp validation_findings(current_scope, mission_id, resources) do
    validation = Module.concat([CadenceWeb, CommsValidation])

    if Code.ensure_loaded?(validation) and
         function_exported?(validation, :findings_for_resources, 3) do
      case Function.capture(validation, :findings_for_resources, 3).(
             current_scope,
             mission_id,
             resources
           ) do
        findings when is_list(findings) -> {:ok, findings}
        _invalid -> {:error, :unsupported_application_surface_query}
      end
    else
      {:ok, fallback_findings(resources)}
    end
  end

  defp fallback_findings(resources) do
    []
    |> add_finding(resources.transports == [], "No Transports configured")
    |> add_finding(resources.routing_rules == [], "No Routing Rules configured")
  end

  defp add_finding(findings, true, title),
    do:
      findings ++
        [
          %{
            id: String.downcase(String.replace(title, " ", "-")),
            severity: :attention,
            title: title,
            body: "Review the saved mission Comms configuration.",
            owner: :transport_setup
          }
        ]

  defp add_finding(findings, false, _title), do: findings

  defp safe_action_href(href, mission_id) when is_binary(href) do
    prefix = "/missions/" <> URI.encode(mission_id) <> "/"

    if String.starts_with?(href, prefix), do: href, else: nil
  end

  defp safe_action_href(_href, _mission_id), do: nil

  defp severity_text(value) when is_atom(value), do: safe_text(Atom.to_string(value), "attention")
  defp severity_text(value), do: safe_text(value, "attention")

  defp resource_display_name(%{display_name: display_name}, fallback),
    do: safe_text(display_name, fallback)

  defp resource_display_name(_resource, fallback), do: safe_text(fallback, fallback)

  defp read_resources(organization_id, mission_id) do
    with {:ok, spacecraft} <-
           scoped_list(
             fn -> Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id) end,
             organization_id,
             mission_id
           ),
         {:ok, source_endpoints} <-
           scoped_list(
             fn -> Cadence.SourceEndpoints.list_source_endpoints(organization_id, mission_id) end,
             organization_id,
             mission_id
           ),
         {:ok, path_templates} <-
           scoped_list(
             fn -> Cadence.Contacts.list_path_templates(organization_id, mission_id) end,
             organization_id,
             mission_id
           ),
         {:ok, provider_profiles} <-
           scoped_list(
             fn -> Cadence.Contacts.list_provider_profiles(organization_id, mission_id) end,
             organization_id,
             mission_id
           ),
         {:ok, transport_profiles} <-
           scoped_list(
             fn -> Cadence.Contacts.list_transport_profiles(organization_id, mission_id) end,
             organization_id,
             mission_id
           ),
         {:ok, transports} <-
           scoped_list(
             fn -> TransportStore.list_transports(organization_id, mission_id) end,
             organization_id,
             mission_id
           ),
         {:ok, routing_rules} <-
           scoped_list(
             fn -> RoutingRuleStore.list_routing_rules(organization_id, mission_id) end,
             organization_id,
             mission_id
           ),
         {:ok, ground_stations} <-
           scoped_list(
             fn -> GroundStationStore.list_ground_stations(organization_id, mission_id) end,
             organization_id,
             mission_id
           ) do
      {:ok,
       %{
         spacecraft: spacecraft,
         source_endpoints: source_endpoints,
         path_templates: path_templates,
         provider_profiles: provider_profiles,
         transport_profiles: transport_profiles,
         transports: transports,
         routing_rules: routing_rules,
         ground_stations: ground_stations
       }}
    end
  end

  defp scoped_list(reader, organization_id, mission_id) do
    case reader.() do
      resources when is_list(resources) ->
        if Enum.all?(resources, &same_scope?(&1, organization_id, mission_id)),
          do: {:ok, resources},
          else: {:error, :unsupported_application_surface_query}

      _invalid ->
        {:error, :unsupported_application_surface_query}
    end
  end

  defp same_scope?(resource, organization_id, mission_id) when is_map(resource) do
    Map.get(resource, :organization_id) == organization_id and
      Map.get(resource, :mission_id) == mission_id
  end

  defp same_scope?(_resource, _organization_id, _mission_id), do: false

  defp fetch_mission(organization_id, mission_id) do
    case Cadence.Missions.fetch_mission(organization_id, mission_id) do
      {:ok, mission} -> {:ok, mission}
      _invalid -> {:error, :unsupported_application_surface_query}
    end
  end

  defp ensure_mission_scope(
         %{organization_id: organization_id, mission_id: mission_id},
         organization_id,
         mission_id
       ),
       do: :ok

  defp ensure_mission_scope(_mission, _organization_id, _mission_id),
    do: {:error, :unsupported_application_surface_query}

  defp fetch_scoped_transport(resources, transport_id) do
    case Enum.find(resources.transports, &(&1.transport_id == transport_id)) do
      nil -> {:error, :unsupported_application_surface_query}
      transport -> {:ok, transport}
    end
  end

  defp fetch_scoped_routing_rule(resources, routing_rule_id) do
    case Enum.find(resources.routing_rules, &(&1.routing_rule_id == routing_rule_id)) do
      nil -> {:error, :unsupported_application_surface_query}
      routing_rule -> {:ok, routing_rule}
    end
  end

  defp fetch_scoped_ground_station(resources, ground_station_id) do
    case Enum.find(resources.ground_stations, &(&1.ground_station_id == ground_station_id)) do
      nil -> {:error, :unsupported_application_surface_query}
      ground_station -> {:ok, ground_station}
    end
  end

  defp transport_search_values(transport), do: [transport.display_name, transport.transport_id]

  defp ground_station_search_values(ground_station),
    do: [
      ground_station.display_name,
      ground_station.ground_station_id,
      ground_station.provider,
      ground_station.region
    ]

  defp trusted_payload(surface_id, mission_id, subject_id, data) do
    %{
      "navigation" => navigation(surface_id, mission_id, subject_id),
      "data" => json_safe(data)
    }
  end

  defp navigation(surface_id, mission_id, subject_id) do
    href = fallback_href(mission_id, surface_id, subject_id)

    %{
      "fallback_href" => href,
      "breadcrumbs" => breadcrumbs(surface_id, mission_id, subject_id)
    }
  end

  defp breadcrumbs(surface_id, mission_id, subject_id) do
    mission_href = "/missions/" <> URI.encode(mission_id)
    comms_href = fallback_href(mission_id, "overview")
    current_href = fallback_href(mission_id, surface_id, subject_id)

    items =
      [
        %{"label" => "Mission", "href" => mission_href},
        %{"label" => "Comms", "href" => comms_href},
        %{"label" => surface_label(surface_id), "href" => current_href}
      ]

    case subject_id do
      nil -> items
      _id -> List.update_at(items, -1, &Map.put(&1, "href", nil))
    end
  end

  defp surface_label("overview"), do: "Overview"
  defp surface_label("validation"), do: "Validation"
  defp surface_label("transports"), do: "Transports"
  defp surface_label("transport"), do: "Transport"
  defp surface_label("routing"), do: "Routing"
  defp surface_label("routing_detail"), do: "Routing Rule"
  defp surface_label("ground_stations"), do: "Ground Stations"
  defp surface_label("ground_station"), do: "Ground Station"

  defp fallback_href(mission_id, surface_id),
    do: fallback_href(mission_id, surface_id, nil)

  defp fallback_href(mission_id, "overview", _subject_id),
    do: "/missions/" <> URI.encode(mission_id) <> "/comms"

  defp fallback_href(mission_id, "validation", _subject_id),
    do: "/missions/" <> URI.encode(mission_id) <> "/comms/validation"

  defp fallback_href(mission_id, "transports", _subject_id),
    do: "/missions/" <> URI.encode(mission_id) <> "/comms/transports"

  defp fallback_href(mission_id, "transport", subject_id) when is_binary(subject_id),
    do: "/missions/" <> URI.encode(mission_id) <> "/comms/transports/" <> URI.encode(subject_id)

  defp fallback_href(mission_id, "transport", _subject_id),
    do: fallback_href(mission_id, "transports")

  defp fallback_href(mission_id, "routing", _subject_id),
    do: "/missions/" <> URI.encode(mission_id) <> "/comms/routing"

  defp fallback_href(mission_id, "routing_detail", subject_id) when is_binary(subject_id),
    do: "/missions/" <> URI.encode(mission_id) <> "/comms/routing/" <> URI.encode(subject_id)

  defp fallback_href(mission_id, "routing_detail", _subject_id),
    do: fallback_href(mission_id, "routing")

  defp fallback_href(mission_id, "ground_stations", _subject_id),
    do: "/missions/" <> URI.encode(mission_id) <> "/comms/ground-stations"

  defp fallback_href(mission_id, "ground_station", subject_id) when is_binary(subject_id),
    do:
      "/missions/" <>
        URI.encode(mission_id) <> "/comms/ground-stations/" <> URI.encode(subject_id)

  defp fallback_href(mission_id, "ground_station", _subject_id),
    do: fallback_href(mission_id, "ground_stations")

  defp safe_text(value, fallback \\ "Unavailable") do
    if is_binary(value) and value != "" and String.valid?(value) do
      String.slice(value, 0, @max_text_length)
    else
      fallback
    end
  end

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value), do: safe_text(value)
  defp json_safe(value) when is_boolean(value) or is_number(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp json_safe(%_{}), do: nil

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {json_key(key), json_safe(item)} end)
  end

  defp json_safe(_value), do: nil

  defp json_key(key) when is_binary(key), do: safe_text(key, "invalid")
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_integer(key), do: Integer.to_string(key)
  defp json_key(_key), do: "invalid"

  defp guarded(fun) do
    fun.()
  rescue
    _exception -> {:error, :unsupported_application_surface_query}
  catch
    _kind, _value -> {:error, :unsupported_application_surface_query}
  end
end
