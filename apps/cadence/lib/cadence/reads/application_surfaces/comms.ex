defmodule Cadence.Reads.ApplicationSurfaces.Comms do
  @moduledoc "Bounded, core-owned trusted read models for the Comms application."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{Comms, HostContext, StatusPlacement, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{GroundStationStore, RoutingRuleStore, TransportStore}
  alias Cadence.Contacts.{LinkAssignmentStore, PathTemplateStore, ProfileStore}
  alias Cadence.ExtensionCatalog
  alias Cadence.Ids
  alias Cadence.Listing.Page
  alias Cadence.Reads.Applications.{Inventory, InventoryItem}
  alias Cadence.SpacecraftTypeStore

  @application_key "comms"
  @application_version 1
  @surface_version 1
  @max_page 10_000
  @default_page_size 50
  @max_page_size 100
  @validation_page_size 100
  @max_resource_items 100
  @max_findings 20
  @max_text_bytes 240
  @max_map_keys 64
  @max_list_items 100
  @max_json_depth 8
  @max_dto_bytes 65_536
  @max_json_integer 9_007_199_254_740_991
  @min_json_integer -9_007_199_254_740_991

  @list_surfaces ~w(transports routing ground_stations)
  @detail_params %{
    "transport" => "transport_id",
    "routing_detail" => "routing_rule_id",
    "ground_station" => "ground_station_id"
  }

  @impl true
  def load(%Scope{} = scope, %HostContext{} = host_context, %SurfaceQueryRequest{} = request) do
    guarded(fn -> load_surface(scope, host_context, request) end)
  end

  @doc "Builds the bounded source summary consumed by the legacy presenter."
  @spec overview(Scope.t(), binary()) :: {:ok, map()} | {:error, atom()}
  def overview(%Scope{} = scope, mission_id) when is_binary(mission_id) do
    with {:ok, resources} <- read_validation_resources(scope.organization_id, mission_id),
         :ok <- validate_resource_identifiers(resources, mission_id),
         {:ok, findings} <- validation_findings(scope, mission_id, resources),
         :ok <- validate_findings_bounds(findings) do
      {:ok,
       %{
         transports: Enum.take(resources.transports, 6),
         transport_count: length(resources.transports),
         findings: findings,
         finding_groups: finding_groups(findings)
       }}
    end
  end

  def overview(_scope, _mission_id), do: {:error, :invalid_application_request}

  @doc "Validates a term against the bounded trusted-payload contract."
  @spec validate_bounded_payload(term()) :: :ok | {:error, :application_surface_bounds_exceeded}
  def validate_bounded_payload(value) do
    case bounded_json(value) do
      {:ok, _safe} -> :ok
      {:error, _reason} -> {:error, :application_surface_bounds_exceeded}
    end
  end

  @doc "Builds the exact JSON-safe legacy overview presentation from the core model."
  @spec overview_presentation(Scope.t(), map()) :: {:ok, map()} | {:error, atom()}
  def overview_presentation(%Scope{} = scope, %{
        mission_id: mission_id,
        display_name: display_name
      }) do
    with {:ok, summary} <- overview(scope, mission_id) do
      {:ok,
       %{
         "root" => %{
           "attrs" => %{"class" => "space-y-6", "id" => "comms-overview-page"}
         },
         "header" => %{
           "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
           "body" => %{"attrs" => %{}},
           "content" => %{"attrs" => %{}},
           "eyebrow" => %{"attrs" => %{"class" => "hud-label"}, "text" => "Communications"},
           "title" => %{
             "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
             "text" => display_name
           },
           "title_suffix" => %{
             "attrs" => %{"class" => "ml-3 font-mono text-base text-base-content/60"},
             "text" => "· Mission Comms"
           }
         },
         "overview" => overview_dto(mission_id, summary)
       }}
    end
  end

  def overview_presentation(_scope, _mission), do: {:error, :invalid_application_request}

  @doc "Returns bounded findings for the dedicated legacy validation page."
  @spec validation(Scope.t(), binary()) :: {:ok, [map()]} | {:error, atom()}
  def validation(%Scope{} = scope, mission_id) when is_binary(mission_id) do
    with {:ok, resources} <- read_validation_resources(scope.organization_id, mission_id),
         :ok <- validate_resource_identifiers(resources, mission_id),
         {:ok, findings} <- validation_findings(scope, mission_id, resources),
         :ok <- validate_findings_bounds(findings) do
      {:ok, findings}
    end
  end

  def validation(_scope, _mission_id), do: {:error, :invalid_application_request}

  @doc "Returns core-owned validation groups for web presenters and providers."
  @spec finding_groups([map()]) :: [map()]
  def finding_groups(findings) when is_list(findings) do
    findings
    |> Enum.group_by(&Map.get(&1, :owner, :advanced_runtime_identity))
    |> Enum.flat_map(fn {owner, owner_findings} ->
      if owner_findings == [],
        do: [],
        else: [Map.put(finding_group(owner), :findings, owner_findings)]
    end)
    |> Enum.sort_by(& &1.order)
  end

  @spec finding_label(atom()) :: binary()
  def finding_label(:blocked), do: "Blocking"
  def finding_label(:attention), do: "Warning"

  def finding_label(other) when is_atom(other),
    do: other |> Atom.to_string() |> String.capitalize()

  def finding_label(_other), do: "Warning"

  defp load_surface(
         %Scope{organization_id: organization_id, mission_id: scope_mission_id} = scope,
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
         :ok <- validate_identifiers([mission.mission_id]) do
      dispatch_surface(scope, mission, surface_id, params)
    end
  end

  defp load_surface(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp dispatch_surface(scope, mission, "overview", _params) do
    with {:ok, data} <- overview_presentation(scope, mission) do
      trusted_payload("overview", mission.mission_id, nil, data)
    end
  end

  defp dispatch_surface(scope, mission, "validation", _params) do
    with {:ok, findings} <- validation(scope, mission.mission_id),
         {:ok, data} <- validation_data(findings, mission.mission_id) do
      trusted_payload("validation", mission.mission_id, nil, data)
    end
  end

  defp dispatch_surface(scope, mission, surface_id, params) when surface_id in @list_surfaces do
    with {:ok, list} <- list_options(params),
         {:ok, page} <-
           collection_page(surface_id, scope.organization_id, mission.mission_id, list),
         {:ok, data} <-
           collection_data(surface_id, scope.organization_id, mission.mission_id, page, list) do
      trusted_payload(surface_id, mission.mission_id, nil, data)
    end
  end

  defp dispatch_surface(_scope, mission, "transport", params) do
    with {:ok, transport_id} <- subject_id(params, "transport_id"),
         {:ok, transport} <-
           TransportStore.fetch_transport(
             mission.organization_id,
             mission.mission_id,
             transport_id
           ),
         {:ok, data} <- transport_data(transport, mission.mission_id),
         {:ok, payload} <- trusted_payload("transport", mission.mission_id, transport_id, data) do
      {:ok, payload}
    else
      {:error, :transport_not_found} -> {:error, :unsupported_application_surface_query}
      error -> error
    end
  end

  defp dispatch_surface(_scope, mission, "routing_detail", params) do
    with {:ok, rule_id} <- subject_id(params, "routing_rule_id"),
         {:ok, rule} <-
           RoutingRuleStore.fetch_routing_rule(
             mission.organization_id,
             mission.mission_id,
             rule_id
           ),
         {:ok, spacecraft} <-
           Cadence.SpacecraftStore.fetch_spacecraft(
             mission.organization_id,
             mission.mission_id,
             rule.spacecraft_id
           ),
         {:ok, transport} <-
           TransportStore.fetch_transport_version(
             mission.organization_id,
             mission.mission_id,
             rule.transport_id,
             rule.transport_version
           ),
         {:ok, data} <- routing_detail_data(rule, spacecraft, transport, mission.mission_id),
         {:ok, payload} <- trusted_payload("routing_detail", mission.mission_id, rule_id, data) do
      {:ok, payload}
    else
      {:error, reason}
      when reason in [:routing_rule_not_found, :spacecraft_not_found, :transport_not_found] ->
        {:error, :unsupported_application_surface_query}

      error ->
        error
    end
  end

  defp dispatch_surface(_scope, mission, "ground_station", params) do
    with {:ok, station_id} <- subject_id(params, "ground_station_id"),
         {:ok, station} <-
           GroundStationStore.fetch_ground_station(
             mission.organization_id,
             mission.mission_id,
             station_id
           ),
         {:ok, data} <- ground_station_data(station, mission.mission_id),
         {:ok, payload} <- trusted_payload("ground_station", mission.mission_id, station_id, data) do
      {:ok, payload}
    else
      {:error, :ground_station_not_found} -> {:error, :unsupported_application_surface_query}
      error -> error
    end
  end

  defp dispatch_surface(_scope, _mission, _surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp validate_query_identity(surface_id, query_id) do
    case Comms.query_id(surface_id) do
      {:ok, ^query_id} -> :ok
      _invalid -> {:error, :unsupported_application_surface_query}
    end
  end

  defp validate_params(surface_id, params) do
    allowed_keys =
      cond do
        surface_id in @list_surfaces ->
          MapSet.new(~w(q sort dir page pageSize))

        Map.has_key?(@detail_params, surface_id) ->
          MapSet.new([Map.fetch!(@detail_params, surface_id)])

        surface_id in Comms.surface_ids() ->
          MapSet.new()

        true ->
          MapSet.new()
      end

    keys = Map.keys(params)

    cond do
      length(keys) > @max_map_keys -> {:error, :application_surface_bounds_exceeded}
      not Enum.all?(keys, &is_binary/1) -> {:error, :invalid_application_request}
      MapSet.subset?(MapSet.new(keys), allowed_keys) -> :ok
      true -> {:error, :invalid_application_request}
    end
  end

  defp subject_id(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case Cadence.Ids.path_segment(value) do
          {:ok, value} -> {:ok, value}
          {:error, :invalid_identifier} -> {:error, :invalid_application_request}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp list_options(params) do
    with {:ok, query} <- optional_query(params),
         {:ok, sort} <- option(params, "sort", "display_name", ["display_name"]),
         {:ok, direction} <- option(params, "dir", "asc", ~w(asc desc)),
         {:ok, page} <- page_param(params, "page", 1),
         {:ok, page_size} <- page_param(params, "pageSize", @default_page_size, @max_page_size) do
      {:ok,
       %{q: query, sort: sort, dir: parse_direction(direction), page: page, page_size: page_size}}
    end
  end

  defp optional_query(params) do
    case Map.get(params, "q") do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      value when is_binary(value) and byte_size(value) <= @max_text_bytes ->
        if String.valid?(value), do: {:ok, value}, else: {:error, :invalid_application_request}

      value when is_binary(value) ->
        {:error, :application_surface_bounds_exceeded}

      _invalid ->
        {:error, :invalid_application_request}
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

  defp page_param(params, key, default, max \\ @max_page) do
    case Map.get(params, key) do
      nil ->
        {:ok, default}

      value when is_integer(value) and value > 0 and value <= max ->
        {:ok, value}

      value when is_binary(value) ->
        bounded_page_string(value, max)

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp bounded_page_string(value, _max) when byte_size(value) > 6,
    do: {:error, :application_surface_bounds_exceeded}

  defp bounded_page_string(value, max) do
    if Regex.match?(~r/\A[0-9]+\z/, value),
      do: bounded_page_number(String.to_integer(value), max),
      else: {:error, :application_surface_bounds_exceeded}
  end

  defp bounded_page_number(number, max) when number > 0 and number <= max, do: {:ok, number}
  defp bounded_page_number(_number, _max), do: {:error, :application_surface_bounds_exceeded}

  defp parse_direction("asc"), do: :asc
  defp parse_direction("desc"), do: :desc

  defp collection_page("transports", organization_id, mission_id, list),
    do: {:ok, TransportStore.list_transports_page(organization_id, mission_id, page_opts(list))}

  defp collection_page("routing", organization_id, mission_id, list),
    do:
      {:ok,
       RoutingRuleStore.list_routing_rules_page(organization_id, mission_id, page_opts(list))}

  defp collection_page("ground_stations", organization_id, mission_id, list),
    do:
      {:ok,
       GroundStationStore.list_ground_stations_page(organization_id, mission_id, page_opts(list))}

  defp page_opts(list), do: [page: list.page, page_size: list.page_size, search: list.q]

  defp collection_data(surface_id, organization_id, mission_id, %Page{} = page, list) do
    with :ok <- validate_page_bound(page),
         :ok <- validate_collection_identifiers(surface_id, page.items, mission_id),
         {:ok, rows} <- collection_rows(surface_id, page.items, organization_id, mission_id) do
      {:ok,
       %{
         "title" => collection_title(surface_id),
         "items" => rows,
         "page" => normalized_page(page.total_count, list.page, page.page_size),
         "page_size" => page.page_size,
         "page_count" => max(ceil(page.total_count / page.page_size), 1),
         "total_count" => page.total_count,
         "query" => list.q,
         "sort" => list.sort,
         "dir" => Atom.to_string(list.dir)
       }}
    end
  end

  defp collection_rows("transports", transports, _organization_id, mission_id),
    do: {:ok, Enum.map(transports, &transport_row(&1, mission_id))}

  defp collection_rows("ground_stations", stations, _organization_id, mission_id),
    do: {:ok, Enum.map(stations, &ground_station_row(&1, mission_id))}

  defp collection_rows("routing", rules, organization_id, mission_id) do
    with {:ok, spacecraft_names} <- fetch_spacecraft_names(rules, organization_id, mission_id),
         {:ok, transport_names} <- fetch_transport_names(rules, organization_id, mission_id) do
      {:ok, Enum.map(rules, &routing_row(&1, mission_id, spacecraft_names, transport_names))}
    end
  end

  defp fetch_spacecraft_names(rules, organization_id, mission_id) do
    Enum.reduce_while(Enum.uniq(Enum.map(rules, & &1.spacecraft_id)), {:ok, %{}}, fn id,
                                                                                     {:ok, acc} ->
      case Cadence.SpacecraftStore.fetch_spacecraft(organization_id, mission_id, id) do
        {:ok, spacecraft} ->
          {:cont, {:ok, Map.put(acc, id, display_text(spacecraft.display_name, id))}}

        _missing ->
          {:cont, {:ok, Map.put(acc, id, id)}}
      end
    end)
  end

  defp fetch_transport_names(rules, organization_id, mission_id) do
    Enum.reduce_while(Enum.uniq(Enum.map(rules, & &1.transport_id)), {:ok, %{}}, fn id,
                                                                                    {:ok, acc} ->
      case TransportStore.fetch_transport(organization_id, mission_id, id) do
        {:ok, transport} ->
          {:cont, {:ok, Map.put(acc, id, display_text(transport.display_name, id))}}

        _missing ->
          {:cont, {:ok, Map.put(acc, id, id)}}
      end
    end)
  end

  defp validate_page_bound(%Page{items: items}) when length(items) <= @max_page_size, do: :ok
  defp validate_page_bound(_page), do: {:error, :application_surface_bounds_exceeded}

  defp normalized_page(0, _page, _page_size), do: 1
  defp normalized_page(total, page, page_size), do: min(page, max(ceil(total / page_size), 1))
  defp collection_title("transports"), do: "Transports"
  defp collection_title("routing"), do: "Routing"
  defp collection_title("ground_stations"), do: "Ground Stations"

  defp read_validation_resources(organization_id, mission_id) do
    readers = [
      {:spacecraft,
       fn ->
         Cadence.SpacecraftStore.list_spacecraft_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end},
      {:source_endpoints,
       fn ->
         Cadence.SourceEndpoints.list_source_endpoints_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end},
      {:path_templates,
       fn ->
         PathTemplateStore.list_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end},
      {:provider_profiles,
       fn ->
         ProfileStore.list_provider_profiles_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end},
      {:transport_profiles,
       fn ->
         ProfileStore.list_transport_profiles_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end},
      {:transports,
       fn ->
         TransportStore.list_transports_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end},
      {:routing_rules,
       fn ->
         RoutingRuleStore.list_routing_rules_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end},
      {:link_assignments,
       fn ->
         LinkAssignmentStore.list_page(organization_id, mission_id,
           page: 1,
           page_size: @validation_page_size
         )
       end}
    ]

    Enum.reduce_while(readers, %{}, fn {key, reader}, acc ->
      case reader.() do
        %Page{items: items, total_count: total}
        when total <= @max_resource_items and length(items) <= @max_resource_items ->
          {:cont, Map.put(acc, key, items)}

        %Page{} ->
          {:halt, {:error, :application_surface_bounds_exceeded}}

        _invalid ->
          {:halt, {:error, :unsupported_application_surface_query}}
      end
    end)
    |> case do
      {:error, _reason} = error ->
        error

      resources ->
        if valid_resource_bounds?(resources),
          do: {:ok, resources},
          else: {:error, :application_surface_bounds_exceeded}
    end
  end

  defp validation_findings(%Scope{} = scope, mission_id, resources) do
    provider_profiles = Map.new(resources.provider_profiles, &{&1.provider_profile_id, &1})
    transport_profiles = Map.new(resources.transport_profiles, &{&1.transport_profile_id, &1})
    source_ids = MapSet.new(resources.source_endpoints, & &1.source_endpoint_id)

    findings =
      []
      |> add_if(resources.source_endpoints == [], %{
        owner: :advanced_runtime_identity,
        severity: :blocked,
        title: "No internal telemetry identities configured",
        body:
          "Internal runtime diagnostics need telemetry identities so ingress can resolve ownership."
      })
      |> add_if(resources.path_templates == [], %{
        owner: :advanced_runtime_identity,
        severity: :blocked,
        title: "No internal routing artifacts configured",
        body:
          "Create Routing Rules to materialize internal runtime artifacts used during execution."
      })
      |> Kernel.++(
        path_findings(
          resources.path_templates,
          source_ids,
          provider_profiles,
          transport_profiles,
          mission_id
        )
      )
      |> Kernel.++(
        profile_presence_findings(resources.provider_profiles, resources.transport_profiles)
      )
      |> Kernel.++(transport_findings(resources.transports, mission_id))
      |> Kernel.++(
        routing_findings(
          resources.spacecraft,
          resources.transports,
          resources.routing_rules,
          mission_id
        )
      )
      |> Kernel.++(selected_path_findings(resources.link_assignments, resources.source_endpoints))
      |> Kernel.++(spacecraft_findings(resources.spacecraft, mission_id))
      |> Kernel.++(
        Enum.flat_map(resources.spacecraft, &application_status_findings(scope, &1, mission_id))
      )

    if length(findings) <= @max_findings,
      do: {:ok, findings},
      else: {:error, :application_surface_bounds_exceeded}
  end

  defp path_findings(templates, source_ids, provider_profiles, transport_profiles, mission_id) do
    Enum.flat_map(templates, fn template ->
      name = display_text(template.path_id, "Path")

      []
      |> add_if(
        is_binary(template.source_endpoint_ref) and
          not MapSet.member?(source_ids, template.source_endpoint_ref),
        %{
          owner: :advanced_runtime_identity,
          severity: :blocked,
          title: "#{name} references a missing internal telemetry identity",
          body:
            "Update the Routing Rule artifact or restore internal telemetry identity #{display_text(template.source_endpoint_ref, "identity")}."
        }
      )
      |> add_if(template.provider_profile_refs == [], %{
        owner: :advanced_runtime_identity,
        severity: :blocked,
        title: "#{name} has no transport provider artifact",
        body:
          "The internal runtime artifact cannot connect to or receive from an external stream without a provider record."
      })
      |> add_if(template.transport_profile_refs == [], %{
        owner: :advanced_runtime_identity,
        severity: :attention,
        title: "#{name} has no advanced protocol behavior",
        body:
          "Advanced protocol behavior is optional unless this runtime integration needs a transport extension."
      })
      |> Kernel.++(
        profile_reference_findings(
          template.provider_profile_refs,
          provider_profiles,
          template,
          "provider",
          mission_id
        )
      )
      |> Kernel.++(
        profile_reference_findings(
          template.transport_profile_refs,
          transport_profiles,
          template,
          "protocol behavior",
          mission_id
        )
      )
    end)
  end

  defp profile_reference_findings(refs, profiles, template, label, mission_id) do
    Enum.flat_map(refs, fn ref ->
      id = Map.get(ref, "provider_profile_id") || Map.get(ref, "transport_profile_id")
      version = ref_version(ref)

      case Map.get(profiles, id) do
        nil ->
          [
            path_finding(
              template,
              mission_id,
              :blocked,
              "#{display_text(template.path_id, "Path")} references a missing #{label}",
              "Refresh the Routing Rule artifact or restore #{label} #{display_text(id, "profile")}"
            )
          ]

        %{lifecycle_state: :deleted} ->
          [
            path_finding(
              template,
              mission_id,
              :blocked,
              "#{display_text(template.path_id, "Path")} references an archived #{label}",
              "Refresh the Routing Rule artifact with an active #{label}."
            )
          ]

        %{version: latest} when is_integer(latest) and version < latest ->
          [
            path_finding(
              template,
              mission_id,
              :attention,
              "#{display_text(template.path_id, "Path")} uses stale #{label}",
              "The referenced version is stale; refresh the Routing Rule artifact."
            )
          ]

        _profile ->
          []
      end
    end)
  end

  defp path_finding(template, mission_id, severity, title, body),
    do: %{
      owner: :advanced_runtime_identity,
      severity: severity,
      title: title,
      body: body,
      action_label: "Review",
      action_navigate: fallback_href(mission_id, "routing_detail", template.path_template_id)
    }

  defp profile_presence_findings(provider_profiles, transport_profiles) do
    []
    |> add_if(provider_profiles == [], %{
      owner: :advanced_runtime_identity,
      severity: :attention,
      title: "No transport compatibility providers configured",
      body: "Transports materialize provider records for existing runtime integrations."
    })
    |> add_if(transport_profiles == [], %{
      owner: :advanced_runtime_identity,
      severity: :attention,
      title: "No advanced protocol behaviors configured",
      body:
        "Advanced protocol behaviors are optional runtime-local extensions such as uplink gateways and heartbeat monitors."
    })
  end

  defp transport_findings(transports, mission_id) do
    []
    |> add_if(transports == [], %{
      owner: :transport_setup,
      severity: :blocked,
      title: "No Transports configured",
      body: "Add a Transport to describe a durable byte-moving capability for this mission.",
      action_label: "Add Transport",
      action_navigate: fallback_href(mission_id, "transports") <> "/new"
    })
    |> Kernel.++(
      Enum.flat_map(transports, fn transport ->
        if is_nil(transport.materialized_provider_profile_id),
          do: [
            %{
              owner: :advanced_runtime_identity,
              severity: :attention,
              title:
                "#{display_text(transport.display_name, "Transport")} has no runtime provider artifact",
              body:
                "This Transport is saved, but the existing runtime compatibility provider record was not materialized.",
              action_label: "Review Transport",
              action_navigate: fallback_href(mission_id, "transport", transport.transport_id)
            }
          ],
          else: []
      end)
    )
  end

  defp routing_findings(spacecraft, transports, rules, mission_id) do
    transport_ids = MapSet.new(transports, & &1.transport_id)

    []
    |> add_if(spacecraft != [] and transports != [] and rules == [], %{
      owner: :routing_setup,
      severity: :blocked,
      title: "No Routing Rules configured",
      body: "Create Routing Rules to declare how spacecraft use mission Transports.",
      action_label: "Create Routing Rule",
      action_navigate: fallback_href(mission_id, "routing") <> "/new"
    })
    |> Kernel.++(
      Enum.flat_map(spacecraft, fn vehicle ->
        if transports != [] and not Enum.any?(rules, &(&1.spacecraft_id == vehicle.spacecraft_id)),
          do: [
            %{
              owner: :routing_setup,
              severity: :attention,
              title: "#{display_text(vehicle.display_name, "Spacecraft")} has no Routing Rule",
              body: "Add a Routing Rule when this spacecraft should use a mission Transport.",
              action_label: "Review Routing",
              action_navigate:
                "/missions/" <>
                  validated_segment(mission_id) <>
                  "/spacecraft/" <> validated_segment(vehicle.spacecraft_id) <> "/routing"
            }
          ],
          else: []
      end)
    )
    |> Kernel.++(
      Enum.flat_map(rules, fn rule ->
        []
        |> add_if(not rule.enabled?, %{
          owner: :routing_setup,
          severity: :attention,
          title: "#{display_text(rule.display_name, "Routing Rule")} is disabled",
          body: "Enable or archive this Routing Rule so the intended transport use is clear.",
          action_label: "Review Routing Rule",
          action_navigate: fallback_href(mission_id, "routing_detail", rule.routing_rule_id)
        })
        |> add_if(not MapSet.member?(transport_ids, rule.transport_id), %{
          owner: :routing_setup,
          severity: :blocked,
          title:
            "#{display_text(rule.display_name, "Routing Rule")} references an unavailable Transport",
          body: "Update the Routing Rule to use an active Transport.",
          action_label: "Review Routing Rule",
          action_navigate: fallback_href(mission_id, "routing_detail", rule.routing_rule_id)
        })
      end)
    )
  end

  defp selected_path_findings(assignments, endpoints) do
    endpoint_names =
      Map.new(
        endpoints,
        &{&1.source_endpoint_id, display_text(&1.display_name, &1.source_endpoint_id)}
      )

    assignments
    |> Enum.group_by(& &1.source_endpoint_ref)
    |> Enum.flat_map(fn {endpoint_id, items} ->
      selected_uplinks =
        Enum.count(items, &(&1.direction == :uplink and &1.selection_role == :selected))

      selected_downlinks =
        Enum.any?(items, &(&1.direction == :downlink and &1.selection_role == :selected))

      label = Map.get(endpoint_names, endpoint_id, display_text(endpoint_id, "identity"))

      []
      |> add_if(selected_uplinks > 1, %{
        owner: :advanced_runtime_identity,
        severity: :attention,
        title: "Multiple selected uplink runtime artifacts for #{label}",
        body: "Review this identity's selected uplink artifacts."
      })
      |> add_if(items != [] and not selected_downlinks, %{
        owner: :advanced_runtime_identity,
        severity: :attention,
        title: "No selected downlink runtime artifact for #{label}",
        body: "Review this identity's selected downlink artifacts."
      })
    end)
  end

  defp spacecraft_findings(spacecraft, mission_id) do
    Enum.flat_map(spacecraft, fn vehicle ->
      []
      |> add_if(is_nil(vehicle.scid), %{
        owner: :spacecraft_setup,
        severity: :blocked,
        title: "#{display_text(vehicle.display_name, "Spacecraft")} is missing SCID",
        body:
          "Set spacecraft identity so Cadence can associate interpreted bytes with this spacecraft.",
        action_label: "Edit identity",
        action_navigate:
          "/missions/" <>
            validated_segment(mission_id) <>
            "/spacecraft/" <> validated_segment(vehicle.spacecraft_id) <> "/identity"
      })
      |> add_if(is_nil(vehicle.spacecraft_type_id), %{
        owner: :spacecraft_setup,
        severity: :attention,
        title: "#{display_text(vehicle.display_name, "Spacecraft")} has no Spacecraft Profile",
        body: "Select a Spacecraft Profile to pin the byte-interpretation contract.",
        action_label: "Select profile",
        action_navigate:
          "/missions/" <>
            validated_segment(mission_id) <>
            "/spacecraft/" <> validated_segment(vehicle.spacecraft_id) <> "/identity"
      })
    end)
  end

  defp application_status_findings(%Scope{} = scope, spacecraft, mission_id) do
    with declarations when is_map(declarations) <- spacecraft_applications(scope, spacecraft),
         {:ok, applications} <-
           Inventory.declared(
             scope,
             HostContext.spacecraft(mission_id, spacecraft.spacecraft_id),
             declarations,
             ExtensionCatalog.applications_for_scope(:spacecraft)
           ) do
      Enum.flat_map(applications, &status_placement_findings(&1, spacecraft, mission_id))
    else
      _invalid -> []
    end
  end

  defp spacecraft_applications(
         %Scope{organization_id: organization_id},
         %{mission_id: mission_id, spacecraft_type_id: type_id, spacecraft_type_version: version}
       )
       when is_binary(organization_id) and is_binary(type_id) and is_integer(version) and
              version > 0 do
    case SpacecraftTypeStore.fetch_spacecraft_type_version(
           organization_id,
           mission_id,
           type_id,
           version
         ) do
      {:ok, spacecraft_type} -> spacecraft_type.applications
      _invalid -> %{}
    end
  end

  defp spacecraft_applications(_scope, _spacecraft), do: %{}

  defp status_placement_findings(%InventoryItem{definition: nil}, _spacecraft, _mission_id),
    do: []

  defp status_placement_findings(%InventoryItem{} = application, spacecraft, mission_id) do
    if application.declared? or application.lifecycle_state in [:installed, :disabled] do
      Enum.flat_map(application.definition.status_placements, fn
        %StatusPlacement{placement: :comms_validation, scope: :spacecraft} = placement ->
          status_finding(application, placement, spacecraft, mission_id)

        %StatusPlacement{} ->
          []
      end)
    else
      []
    end
  end

  defp status_finding(
         %InventoryItem{status: %{tone: :ready}},
         %StatusPlacement{},
         _spacecraft,
         _mission_id
       ),
       do: []

  defp status_finding(
         %InventoryItem{status: %{state: state}},
         %StatusPlacement{required?: false},
         _spacecraft,
         _mission_id
       )
       when state in [:not_installed, :uninstalled],
       do: []

  defp status_finding(
         %InventoryItem{} = application,
         %StatusPlacement{required?: required?},
         spacecraft,
         mission_id
       ) do
    require_identifiers!([mission_id, spacecraft.spacecraft_id, application.application_key])

    severity =
      case {application.status.tone, required?} do
        {:info, true} -> :blocked
        {:blocked, _required} -> :blocked
        _other -> :attention
      end

    [
      %{
        id:
          "comms-validation-application-#{validated_segment(spacecraft.spacecraft_id)}-#{validated_segment(application.application_key)}",
        owner: :spacecraft_setup,
        application_key: application.application_key,
        severity: severity,
        title:
          "#{display_text(spacecraft.display_name, "Spacecraft")} — #{display_text(application.display_name, "Application")}: #{display_text(application.status.label, "Unavailable")}",
        body:
          "#{display_text(application.display_name, "Application")} reports #{String.downcase(display_text(application.status.label, "unavailable"))} for this spacecraft. Review the application before treating Comms setup as ready.",
        action_label:
          if(application.manageable?, do: "Review application", else: "Review applications"),
        action_navigate: application_action_path(application, mission_id, spacecraft)
      }
    ]
  end

  defp application_action_path(
         %InventoryItem{manageable?: true, application_key: key},
         mission_id,
         spacecraft
       ),
       do:
         "/missions/#{validated_segment(mission_id)}/spacecraft/#{validated_segment(spacecraft.spacecraft_id)}/applications/#{validated_segment(key)}"

  defp application_action_path(%InventoryItem{}, mission_id, spacecraft),
    do:
      "/missions/#{validated_segment(mission_id)}/spacecraft/#{validated_segment(spacecraft.spacecraft_id)}/applications"

  defp validated_segment(value) do
    case Ids.path_segment(value) do
      {:ok, value} -> value
      {:error, :invalid_identifier} -> throw(:invalid_application_request)
    end
  end

  defp add_if(findings, true, finding), do: findings ++ [finding]
  defp add_if(findings, false, _finding), do: findings

  defp finding_group(:spacecraft_setup),
    do: %{
      id: "comms-validation-spacecraft-setup",
      order: 1,
      title: "Spacecraft Setup",
      description: "Identity, Spacecraft Profile, and application setup owned by each spacecraft."
    }

  defp finding_group(:transport_setup),
    do: %{
      id: "comms-validation-transport-setup",
      order: 2,
      title: "Transport Setup",
      description: "Durable byte-moving capabilities available to this mission."
    }

  defp finding_group(:routing_setup),
    do: %{
      id: "comms-validation-routing-setup",
      order: 3,
      title: "Routing Setup",
      description: "Durable rules for how spacecraft use mission Transports."
    }

  defp finding_group(:advanced_runtime_identity),
    do: %{
      id: "comms-validation-advanced-runtime-identity",
      order: 4,
      title: "Internal Runtime Artifacts",
      description:
        "Diagnostics for internal execution artifacts derived from spacecraft routing setup."
    }

  defp validation_data(findings, mission_id) do
    with :ok <- validate_findings_bounds(findings) do
      {:ok,
       %{
         "id" => "comms-validation-page",
         "title" => "Validation",
         "finding_count" => length(findings),
         "empty" => findings == [],
         "href" => fallback_href(mission_id, "validation"),
         "findings" => Enum.with_index(findings) |> Enum.map(&finding_data(&1, mission_id)),
         "finding_groups" =>
           Enum.with_index(finding_groups(findings))
           |> Enum.map(&finding_group_data(&1, mission_id)),
         "status" => if(findings == [], do: "ready", else: "attention")
       }}
    end
  end

  defp finding_group_data({group, index}, mission_id) do
    %{
      "id" => display_text(group.id, "finding-group-#{index + 1}"),
      "title" => display_text(group.title, "Comms findings"),
      "description" => display_text(group.description, "Review the saved Comms configuration."),
      "findings" => Enum.with_index(group.findings) |> Enum.map(&finding_data(&1, mission_id))
    }
  end

  defp finding_data({finding, index}, mission_id) do
    %{
      "id" => display_text(Map.get(finding, :id), "finding-#{index + 1}"),
      "title" => display_text(finding.title, "Comms finding"),
      "body" => display_text(finding.body, "Review the saved Comms configuration."),
      "severity" => finding_label(finding.severity),
      "action_label" => display_text(Map.get(finding, :action_label), "Review"),
      "action_href" => safe_action_href(Map.get(finding, :action_navigate), mission_id)
    }
  end

  defp overview_dto(mission_id, summary) do
    count = summary.transport_count

    %{
      "transport" => %{
        "id" => "comms-transports",
        "eyebrow" => "Transport",
        "count" => count,
        "count_label" =>
          if(count == 1, do: "transport configured", else: "transports configured"),
        "description" =>
          "Transports describe durable capabilities for moving bytes. Routing rules will decide how spacecraft use those capabilities.",
        "status" =>
          if(count == 0,
            do: %{"tone" => "attention", "label" => "Needs Work"},
            else: %{"tone" => "ready", "label" => "Ready"}
          ),
        "empty" => summary.transports == [],
        "empty_state" => %{
          "title" => "No transports configured",
          "description" =>
            "Add a transport to describe a byte-moving capability for this mission.",
          "action_label" => "Add a transport",
          "action_href" => fallback_href(mission_id, "transports") <> "/new"
        },
        "rows" =>
          Enum.map(
            summary.transports,
            &%{
              "id" => "comms-transport-#{&1.transport_id}",
              "display_name" => display_text(&1.display_name, "Transport"),
              "metadata" => "#{&1.transport_kind} · #{&1.direction_capability} · v#{&1.version}",
              "href" => fallback_href(mission_id, "transport", &1.transport_id)
            }
          ),
        "manage_label" => "Manage transports →",
        "manage_href" => fallback_href(mission_id, "transports"),
        "add_label" => "+ Add a transport",
        "add_href" => fallback_href(mission_id, "transports") <> "/new"
      },
      "validation" => %{
        "id" => "comms-validation-page",
        "eyebrow" => "Setup Checks",
        "title" => "What's missing or broken",
        "description" => "Checks on saved configuration for spacecraft on this mission.",
        "status" => %{
          "tone" => if(summary.findings == [], do: "ready", else: "attention"),
          "label" =>
            if(summary.findings == [],
              do: "No Findings",
              else: "#{length(summary.findings)} Findings"
            )
        },
        "empty" => summary.findings == [],
        "empty_state" => %{
          "title" => "All clear",
          "description" => "The saved configuration looks consistent."
        },
        "findings_id" => "comms-validation-findings",
        "finding_groups" =>
          Enum.map(
            summary.finding_groups,
            &%{
              "id" => &1.id,
              "title" => &1.title,
              "description" => &1.description,
              "findings" =>
                Enum.map(&1.findings, fn finding ->
                  %{
                    "id" => Map.get(finding, :id),
                    "title" => finding.title,
                    "body" => finding.body,
                    "action_label" => Map.get(finding, :action_label),
                    "action_href" => Map.get(finding, :action_navigate),
                    "status" => %{
                      "tone" => Atom.to_string(finding.severity),
                      "label" => finding_label(finding.severity)
                    }
                  }
                end)
            }
          )
      }
    }
  end

  defp transport_row(transport, mission_id),
    do: %{
      "id" => transport.transport_id,
      "display_name" => display_text(transport.display_name, "Transport"),
      "origin" => Atom.to_string(transport.origin),
      "transport_kind" => Atom.to_string(transport.transport_kind),
      "direction_capability" => Atom.to_string(transport.direction_capability),
      "version" => transport.version,
      "href" => fallback_href(mission_id, "transport", transport.transport_id)
    }

  defp routing_row(rule, mission_id, spacecraft_names, transport_names),
    do: %{
      "id" => rule.routing_rule_id,
      "display_name" => display_text(rule.display_name, "Routing Rule"),
      "spacecraft_id" => rule.spacecraft_id,
      "spacecraft_name" => Map.get(spacecraft_names, rule.spacecraft_id, rule.spacecraft_id),
      "purpose_label" => display_text(rule.purpose_label, "Unspecified"),
      "direction" => Atom.to_string(rule.direction),
      "transport_id" => rule.transport_id,
      "transport_name" => Map.get(transport_names, rule.transport_id, rule.transport_id),
      "role" => Atom.to_string(rule.role),
      "enabled" => rule.enabled?,
      "href" => fallback_href(mission_id, "routing_detail", rule.routing_rule_id)
    }

  defp ground_station_row(station, mission_id),
    do: %{
      "id" => station.ground_station_id,
      "display_name" => display_text(station.display_name, "Ground Station"),
      "provider" => display_text(station.provider, "Unspecified"),
      "region" => display_text(station.region, "Unspecified"),
      "href" => fallback_href(mission_id, "ground_station", station.ground_station_id)
    }

  defp transport_data(transport, mission_id) do
    with :ok <- validate_identifiers([mission_id, transport.transport_id]) do
      {:ok,
       %{
         "id" => transport.transport_id,
         "display_name" => display_text(transport.display_name, "Transport"),
         "version" => transport.version,
         "lifecycle_state" => Atom.to_string(transport.lifecycle_state),
         "origin" => Atom.to_string(transport.origin),
         "transport_kind" => Atom.to_string(transport.transport_kind),
         "direction_capability" => Atom.to_string(transport.direction_capability),
         "provider_managed" => transport.origin == :provider_managed,
         "href" => fallback_href(mission_id, "transport", transport.transport_id),
         "list_href" => fallback_href(mission_id, "transports")
       }}
    end
  end

  defp routing_detail_data(rule, spacecraft, transport, mission_id) do
    with :ok <-
           validate_identifiers([
             mission_id,
             rule.routing_rule_id,
             rule.spacecraft_id,
             rule.transport_id,
             spacecraft.spacecraft_id,
             transport.transport_id
           ]) do
      {:ok,
       %{
         "id" => rule.routing_rule_id,
         "display_name" => display_text(rule.display_name, "Routing Rule"),
         "enabled" => rule.enabled?,
         "lifecycle_state" => Atom.to_string(rule.lifecycle_state),
         "spacecraft_id" => rule.spacecraft_id,
         "spacecraft_name" => display_text(spacecraft.display_name, rule.spacecraft_id),
         "purpose_label" => display_text(rule.purpose_label, "Unspecified"),
         "direction" => Atom.to_string(rule.direction),
         "transport_id" => rule.transport_id,
         "transport_name" => display_text(transport.display_name, rule.transport_id),
         "transport_version" => rule.transport_version,
         "role" => Atom.to_string(rule.role),
         "href" => fallback_href(mission_id, "routing_detail", rule.routing_rule_id),
         "list_href" => fallback_href(mission_id, "routing")
       }}
    end
  end

  defp ground_station_data(station, mission_id) do
    with :ok <- validate_identifiers([mission_id, station.ground_station_id]) do
      {:ok,
       %{
         "id" => station.ground_station_id,
         "display_name" => display_text(station.display_name, "Ground Station"),
         "lifecycle_state" => Atom.to_string(station.lifecycle_state),
         "provider" => display_text(station.provider, "Unspecified"),
         "region" => display_text(station.region, "Unspecified"),
         "href" => fallback_href(mission_id, "ground_station", station.ground_station_id),
         "list_href" => fallback_href(mission_id, "ground_stations"),
         "edit_href" =>
           fallback_href(mission_id, "ground_station", station.ground_station_id) <> "/edit"
       }}
    end
  end

  defp trusted_payload(surface_id, mission_id, subject_id, data) do
    with {:ok, safe_data} <- bounded_json(data) do
      {:ok,
       %{"navigation" => navigation(surface_id, mission_id, subject_id), "data" => safe_data}}
    end
  end

  defp navigation(surface_id, mission_id, subject_id),
    do: %{
      "fallback_href" => fallback_href(mission_id, surface_id, subject_id),
      "breadcrumbs" => breadcrumbs(surface_id, mission_id, subject_id)
    }

  defp breadcrumbs(surface_id, mission_id, subject_id) do
    items = [
      %{"label" => "Mission", "href" => "/missions/" <> validated_segment(mission_id)},
      %{"label" => "Comms", "href" => fallback_href(mission_id, "overview")},
      %{
        "label" => surface_label(surface_id),
        "href" => fallback_href(mission_id, surface_id, subject_id)
      }
    ]

    if is_binary(subject_id),
      do: List.update_at(items, -1, &Map.put(&1, "href", nil)),
      else: items
  end

  defp surface_label("overview"), do: "Overview"
  defp surface_label("validation"), do: "Validation"
  defp surface_label("transports"), do: "Transports"
  defp surface_label("transport"), do: "Transport"
  defp surface_label("routing"), do: "Routing"
  defp surface_label("routing_detail"), do: "Routing Rule"
  defp surface_label("ground_stations"), do: "Ground Stations"
  defp surface_label("ground_station"), do: "Ground Station"

  defp fallback_href(mission_id, surface_id), do: fallback_href(mission_id, surface_id, nil)

  defp fallback_href(mission_id, "overview", _subject),
    do: "/missions/" <> validated_segment(mission_id) <> "/comms"

  defp fallback_href(mission_id, "validation", _subject),
    do: "/missions/" <> validated_segment(mission_id) <> "/comms/validation"

  defp fallback_href(mission_id, "transports", _subject),
    do: "/missions/" <> validated_segment(mission_id) <> "/comms/transports"

  defp fallback_href(mission_id, "transport", subject) when is_binary(subject),
    do:
      "/missions/" <>
        validated_segment(mission_id) <> "/comms/transports/" <> validated_segment(subject)

  defp fallback_href(mission_id, "transport", _subject),
    do: fallback_href(mission_id, "transports", nil)

  defp fallback_href(mission_id, "routing", _subject),
    do: "/missions/" <> validated_segment(mission_id) <> "/comms/routing"

  defp fallback_href(mission_id, "routing_detail", subject) when is_binary(subject),
    do:
      "/missions/" <>
        validated_segment(mission_id) <> "/comms/routing/" <> validated_segment(subject)

  defp fallback_href(mission_id, "routing_detail", _subject),
    do: fallback_href(mission_id, "routing", nil)

  defp fallback_href(mission_id, "ground_stations", _subject),
    do: "/missions/" <> validated_segment(mission_id) <> "/comms/ground-stations"

  defp fallback_href(mission_id, "ground_station", subject) when is_binary(subject),
    do:
      "/missions/" <>
        validated_segment(mission_id) <> "/comms/ground-stations/" <> validated_segment(subject)

  defp fallback_href(mission_id, "ground_station", _subject),
    do: fallback_href(mission_id, "ground_stations", nil)

  defp safe_action_href(href, mission_id) when is_binary(href) do
    prefix = "/missions/" <> validated_segment(mission_id) <> "/"
    if String.starts_with?(href, prefix), do: href, else: nil
  end

  defp safe_action_href(_href, _mission_id), do: nil

  defp ref_version(ref) do
    case Map.get(ref, "version") do
      version when is_integer(version) and version > 0 ->
        version

      version when is_binary(version) ->
        if byte_size(version) <= 6 and Regex.match?(~r/\A[0-9]+\z/, version),
          do: String.to_integer(version),
          else: 1

      _invalid ->
        1
    end
  end

  defp display_text(value, _fallback) when is_binary(value) and value != "" do
    if String.valid?(value), do: truncate_text(value), else: "Unavailable"
  end

  defp display_text(_value, fallback), do: fallback

  defp truncate_text(value) when byte_size(value) <= @max_text_bytes, do: value

  defp truncate_text(value) do
    value
    |> binary_part(0, @max_text_bytes)
    |> trim_invalid_utf8_suffix()
  end

  defp trim_invalid_utf8_suffix(value) do
    if String.valid?(value) do
      value
    else
      trim_invalid_utf8_suffix(binary_part(value, 0, byte_size(value) - 1))
    end
  end

  defp valid_resource_bounds?(resources),
    do:
      Enum.all?(resources, fn {_key, items} ->
        result =
          is_list(items) and length(items) <= @max_resource_items and
            Enum.all?(items, &bounded_term?(&1, 0))

        result
      end)

  defp validate_resource_identifiers(resources, mission_id) when is_map(resources) do
    identifiers =
      [mission_id] ++
        Enum.flat_map(resources.spacecraft, fn spacecraft ->
          [spacecraft.spacecraft_id]
        end) ++
        Enum.flat_map(resources.path_templates, fn template ->
          [template.path_template_id]
        end) ++
        Enum.flat_map(resources.transports, fn transport -> [transport.transport_id] end) ++
        Enum.flat_map(resources.routing_rules, fn rule -> [rule.routing_rule_id] end)

    validate_identifiers(identifiers)
  end

  defp validate_resource_identifiers(_resources, _mission_id),
    do: {:error, :invalid_application_request}

  defp validate_collection_identifiers("transports", transports, mission_id),
    do: validate_identifiers([mission_id | Enum.map(transports, & &1.transport_id)])

  defp validate_collection_identifiers("routing", rules, mission_id),
    do:
      validate_identifiers([
        mission_id
        | Enum.flat_map(rules, &[&1.routing_rule_id, &1.spacecraft_id, &1.transport_id])
      ])

  defp validate_collection_identifiers("ground_stations", stations, mission_id),
    do: validate_identifiers([mission_id | Enum.map(stations, & &1.ground_station_id)])

  defp validate_collection_identifiers(_surface_id, _items, _mission_id),
    do: {:error, :invalid_application_request}

  defp validate_identifiers(identifiers) when is_list(identifiers) do
    if Enum.all?(identifiers, &valid_identifier?/1),
      do: :ok,
      else: {:error, :invalid_application_request}
  end

  defp require_identifiers!(identifiers) do
    case validate_identifiers(identifiers) do
      :ok -> :ok
      {:error, :invalid_application_request} -> throw(:invalid_application_request)
    end
  end

  defp valid_identifier?(value), do: match?({:ok, _identifier}, Ids.path_segment(value))

  defp bounded_term?(_value, depth) when depth > @max_json_depth, do: false
  defp bounded_term?(nil, _depth), do: true

  defp bounded_term?(value, _depth) when is_boolean(value), do: true
  defp bounded_term?(value, _depth) when is_number(value), do: json_number?(value)

  defp bounded_term?(value, _depth) when is_atom(value),
    do: byte_size(Atom.to_string(value)) <= @max_text_bytes

  defp bounded_term?(value, _depth) when is_binary(value),
    do: String.valid?(value) and byte_size(value) <= @max_text_bytes

  defp bounded_term?(%DateTime{}, _depth), do: true
  defp bounded_term?(%NaiveDateTime{}, _depth), do: true
  defp bounded_term?(%_{} = value, depth), do: bounded_term?(Map.from_struct(value), depth + 1)

  defp bounded_term?(value, depth) when is_list(value),
    do: length(value) <= @max_list_items and Enum.all?(value, &bounded_term?(&1, depth + 1))

  defp bounded_term?(value, depth) when is_map(value),
    do:
      map_size(value) <= @max_map_keys and
        Enum.all?(value, fn {key, item} ->
          bounded_key?(key) and bounded_term?(item, depth + 1)
        end)

  defp bounded_term?(_value, _depth), do: false

  defp bounded_key?(key) when is_atom(key), do: bounded_key?(Atom.to_string(key))

  defp bounded_key?(key) when is_integer(key), do: bounded_key?(Integer.to_string(key))

  defp bounded_key?(key) when is_binary(key),
    do: String.valid?(key) and byte_size(key) <= @max_text_bytes

  defp bounded_key?(_key), do: false

  defp bounded_json(value) do
    with true <- bounded_term?(value, 0),
         {:ok, safe} <- json_safe(value, 0),
         {:ok, encoded} <- Jason.encode(safe),
         true <- byte_size(encoded) <= @max_dto_bytes do
      {:ok, safe}
    else
      _invalid -> {:error, :application_surface_bounds_exceeded}
    end
  end

  defp json_safe(_value, depth) when depth > @max_json_depth, do: {:error, :depth}
  defp json_safe(nil, _depth), do: {:ok, nil}
  defp json_safe(value, _depth) when is_boolean(value), do: {:ok, value}

  defp json_safe(value, _depth) when is_number(value) do
    if json_number?(value), do: {:ok, value}, else: {:error, :number}
  end

  defp json_safe(value, _depth) when is_binary(value) and byte_size(value) <= @max_text_bytes do
    if String.valid?(value), do: {:ok, value}, else: {:error, :string}
  end

  defp json_safe(value, _depth) when is_binary(value), do: {:error, :string}
  defp json_safe(%DateTime{} = value, _depth), do: {:ok, DateTime.to_iso8601(value)}
  defp json_safe(%NaiveDateTime{} = value, _depth), do: {:ok, NaiveDateTime.to_iso8601(value)}
  defp json_safe(%_{} = value, depth), do: json_safe(Map.from_struct(value), depth + 1)

  defp json_safe(value, depth) when is_list(value) do
    if length(value) <= @max_list_items, do: reduce_json(value, depth, []), else: {:error, :list}
  end

  defp json_safe(value, depth) when is_map(value) do
    case map_size(value) <= @max_map_keys do
      true -> json_map(value, depth)
      false -> {:error, :map}
    end
  end

  defp json_safe(_value, _depth), do: {:error, :unsupported}

  defp json_map(value, depth) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      with {:ok, json_key} <- json_key(key), {:ok, safe_item} <- json_safe(item, depth + 1) do
        {:cont, {:ok, Map.put(acc, json_key, safe_item)}}
      else
        _invalid -> {:halt, {:error, :map}}
      end
    end)
  end

  defp reduce_json([], _depth, acc), do: {:ok, Enum.reverse(acc)}

  defp reduce_json([value | rest], depth, acc) do
    with {:ok, safe} <- json_safe(value, depth + 1), do: reduce_json(rest, depth, [safe | acc])
  end

  defp json_key(key) when is_atom(key), do: json_key(Atom.to_string(key))

  defp json_key(key) when is_integer(key), do: json_key(Integer.to_string(key))

  defp json_key(key) when is_binary(key) and byte_size(key) <= @max_text_bytes do
    if String.valid?(key), do: {:ok, key}, else: {:error, :key}
  end

  defp json_key(_key), do: {:error, :key}

  defp json_number?(value) when is_integer(value),
    do: value >= @min_json_integer and value <= @max_json_integer

  defp json_number?(value) when is_float(value) do
    rendered = value |> :erlang.float_to_binary([:short]) |> String.downcase()

    rendered not in [
      "nan",
      "+nan",
      "-nan",
      "inf",
      "+inf",
      "-inf",
      "infinity",
      "+infinity",
      "-infinity"
    ]
  rescue
    _error -> false
  end

  defp validate_findings_bounds(findings) when is_list(findings) do
    groups = finding_groups(findings)

    if length(findings) <= @max_findings and length(groups) <= @max_findings and
         Enum.all?(groups, &(length(&1.findings) <= @max_findings)),
       do: :ok,
       else: {:error, :application_surface_bounds_exceeded}
  end

  defp validate_findings_bounds(_findings), do: {:error, :application_surface_bounds_exceeded}

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

  defp guarded(fun) do
    fun.()
  rescue
    _exception -> {:error, :unsupported_application_surface_query}
  catch
    :throw, :invalid_application_request -> {:error, :invalid_application_request}
    _kind, _value -> {:error, :unsupported_application_surface_query}
  end
end
