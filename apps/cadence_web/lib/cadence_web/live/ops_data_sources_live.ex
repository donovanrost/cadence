defmodule CadenceWeb.OpsDataSourcesLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.{GroundStationStore, RoutingRuleStore, TransportStore}
  alias Cadence.Control.DataSources, as: DataSourceControl
  alias Cadence.Control.ManagedResources
  alias Cadence.Dashboards.SourceReadiness
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials
  alias Cadence.Projections.DataSources.Health, as: SourceHealth
  alias Cadence.Projections.DataSources.Watermarks, as: SourceWatermarks
  alias Cadence.Projections.ManagedResourceStatus

  alias CadenceWeb.OpsDataSourcesLive.{
    Page,
    SourceActivityPresentation,
    SourceBindingPresentation,
    SourceContract,
    SourceFocus,
    SourceFocusResources,
    SourceInventoryPresentation,
    SourceRegistration
  }

  @source_mutation_events ~w(
    open_register_source cancel_register_source register_source
    open_change_binding cancel_change_binding change_binding
    rotate_source_credential reconcile_tsdb_backend provision_tsdb_backend
    deprovision_tsdb_backend probe_source disable_source enable_source
    retry_deployment_run requeue_deployment_run
  )

  @impl true
  def mount(_params, _session, socket) do
    source_admin? = socket.assigns.live_action in [:new, :settings]

    {:ok,
     socket
     |> assign(:page_title, "Data Sources")
     |> assign(:ops_nav_item, :data_sources)
     |> assign(:source_admin?, source_admin?)
     |> assign(:change_binding, nil)
     |> assign(:change_binding_form, to_form(%{}, as: :binding))
     |> assign(:change_binding_error, nil)
     |> assign(:register_source?, socket.assigns.live_action == :new)
     |> assign(:register_source_form, to_form(SourceRegistration.defaults(), as: :source))
     |> assign(:register_source_error, nil)
     |> assign(:source_focus, SourceFocus.default())
     |> assign(:source_focus_resources, SourceFocusResources.default())
     |> assign_source_inventory()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    source_focus = SourceFocus.from_params(params)

    {:noreply,
     socket
     |> assign(:source_focus, source_focus)
     |> assign_source_focus_resources()
     |> assign_source_focus_state()}
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{source_admin?: false}} = socket)
      when event in @source_mutation_events do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Source configuration requires the Data Source Settings administrator route."
     )}
  end

  @impl true
  def handle_event("open_register_source", _params, socket) do
    {:noreply,
     socket
     |> assign(:register_source?, true)
     |> assign(:register_source_form, to_form(SourceRegistration.defaults(), as: :source))
     |> assign(:register_source_error, nil)}
  end

  def handle_event("cancel_register_source", _params, socket) do
    {:noreply, clear_register_source(socket)}
  end

  def handle_event("disable_source", %{"data-source-id" => data_source_id}, socket) do
    %{current_scope: scope} = socket.assigns

    case DataSources.disable_data_source(data_source_id, %{},
           actor_id: current_user_id(scope),
           payload: source_action_payload(socket)
         ) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "Data source disabled.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disable source: #{error_text(reason)}")}
    end
  end

  def handle_event("enable_source", %{"data-source-id" => data_source_id}, socket) do
    %{current_scope: scope} = socket.assigns

    case DataSources.enable_data_source(data_source_id, %{},
           actor_id: current_user_id(scope),
           payload: source_action_payload(socket)
         ) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "Data source enabled.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enable source: #{error_text(reason)}")}
    end
  end

  def handle_event(
        "rotate_source_credential",
        %{"credentials-ref" => credentials_ref, "data-source-id" => data_source_id},
        socket
      ) do
    %{current_scope: scope} = socket.assigns

    attrs = %{
      data_source_id: data_source_id,
      payload: source_action_payload(socket, %{data_source_id: data_source_id})
    }

    case SourceCredentials.rotate_reference(credentials_ref, attrs,
           actor_id: current_user_id(scope)
         ) do
      {:ok, _reference, _event} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "Credential reference rotated.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to rotate credential: #{error_text(reason)}")}
    end
  end

  def handle_event("reconcile_tsdb_backend", %{"data-source-id" => data_source_id}, socket) do
    %{current_scope: scope} = socket.assigns

    case ManagedResources.reconcile_tsdb_backend(data_source_id, %{},
           actor_id: current_user_id(scope),
           payload: source_action_payload(socket, %{data_source_id: data_source_id})
         ) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "TSDB backend reconciled.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to reconcile backend: #{error_text(reason)}")}
    end
  end

  def handle_event("deprovision_tsdb_backend", %{"data-source-id" => data_source_id}, socket) do
    %{current_scope: scope} = socket.assigns

    case ManagedResources.request_tsdb_backend(data_source_id, :deprovision, %{},
           actor_id: current_user_id(scope),
           payload: source_action_payload(socket, %{data_source_id: data_source_id})
         ) do
      {:ok, _source, _job} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "TSDB backend deprovisioning requested.")}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Failed to request backend deprovisioning: #{error_text(reason)}"
         )}
    end
  end

  def handle_event("provision_tsdb_backend", %{"data-source-id" => data_source_id}, socket) do
    %{current_scope: scope} = socket.assigns

    case ManagedResources.request_tsdb_backend(data_source_id, :provision, %{},
           actor_id: current_user_id(scope),
           payload: source_action_payload(socket, %{data_source_id: data_source_id})
         ) do
      {:ok, _source, _job} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "TSDB backend provisioning requested.")}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Failed to request backend provisioning: #{error_text(reason)}"
         )}
    end
  end

  def handle_event("probe_source", %{"data-source-id" => data_source_id}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    source = find_data_source(socket.assigns.data_sources, data_source_id)

    case DataSourceControl.probe(
           data_source_id,
           %{mission_id: mission.mission_id},
           [
             actor_id: current_user_id(scope),
             materialize_adapter_capabilities?: true,
             payload: source_action_payload(socket)
           ] ++ source_probe_opts(source)
         ) do
      {:ok, _event_or_unchanged, status} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "Source probe recorded: #{text(status.source_health)}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to probe source: #{error_text(reason)}")}
    end
  end

  def handle_event("retry_deployment_run", %{"job-id" => job_id}, socket) do
    case retry_deployment_run(job_id) do
      {:ok, run} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "Deployment run retried: #{run.run_id}.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to retry deployment run: #{error_text(reason)}")}
    end
  end

  def handle_event("requeue_deployment_run", %{"job-id" => job_id}, socket) do
    case requeue_deployment_run(job_id) do
      {:ok, run} ->
        {:noreply,
         socket
         |> assign_source_inventory()
         |> put_flash(:info, "Deployment run requeued: #{run.run_id}.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to requeue deployment run: #{error_text(reason)}")}
    end
  end

  def handle_event("register_source", %{"source" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, attrs} <-
           SourceRegistration.parse(params, scope.organization_id, mission.mission_id),
         :ok <-
           maybe_register_source_credentials(
             attrs,
             scope,
             source_action_payload(socket, %{data_source_id: attrs.data_source_id})
           ),
         {:ok, _source} <-
           attrs
           |> SourceRegistration.data_source()
           |> DataSources.persist_data_source(
             actor_id: current_user_id(scope),
             payload:
               source_action_payload(socket, %{
                 logical_source: attrs.logical_source,
                 storage: attrs.storage
               })
           ) do
      {:noreply,
       socket
       |> clear_register_source()
       |> assign_source_inventory()
       |> put_flash(:info, "Data source registered.")}
    else
      {:error, message} when is_binary(message) ->
        {:noreply,
         socket
         |> assign(:register_source?, true)
         |> assign(:register_source_form, to_form(params, as: :source))
         |> assign(:register_source_error, message)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:register_source?, true)
         |> assign(:register_source_form, to_form(params, as: :source))
         |> assign(:register_source_error, "Failed to register source: #{error_text(reason)}")}
    end
  end

  def handle_event("open_change_binding", %{"binding-id" => binding_id}, socket) do
    case find_binding(socket.assigns.data_bindings, binding_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Binding not found.")}

      %DataBinding{} = binding ->
        candidates = change_binding_candidates(socket, binding)

        {:noreply,
         socket
         |> assign(:change_binding, %{
           binding: binding,
           source_options: source_options(candidates)
         })
         |> assign(
           :change_binding_form,
           to_form(%{"data_source_id" => binding.data_source_id}, as: :binding)
         )
         |> assign(:change_binding_error, nil)}
    end
  end

  def handle_event("cancel_change_binding", _params, socket) do
    {:noreply, clear_change_binding(socket)}
  end

  def handle_event("change_binding", %{"binding" => params}, socket) do
    %{current_scope: scope} = socket.assigns

    with %{binding: %DataBinding{} = binding} <- socket.assigns.change_binding,
         {:ok, data_source_id} <- selected_data_source_id(params),
         :ok <- validate_changed_source(binding, data_source_id),
         :ok <- validate_compatible_source(socket.assigns.data_sources, binding, data_source_id),
         :ok <-
           validate_focused_source_contract(
             socket.assigns.source_focus,
             socket.assigns.data_sources,
             binding,
             data_source_id
           ),
         {:ok, _binding} <-
           DataSources.persist_data_binding(
             %DataBinding{binding | data_source_id: data_source_id},
             actor_id: current_user_id(scope),
             payload:
               source_action_payload(socket, %{
                 previous_data_source_id: binding.data_source_id,
                 current_data_source_id: data_source_id
               })
           ) do
      {:noreply,
       socket
       |> clear_change_binding()
       |> assign_source_inventory()
       |> put_flash(:info, "Source binding changed.")}
    else
      {:error, message} when is_binary(message) ->
        {:noreply,
         socket
         |> assign(:change_binding_form, to_form(params, as: :binding))
         |> assign(:change_binding_error, message)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:change_binding_form, to_form(params, as: :binding))
         |> assign(:change_binding_error, "Failed to change binding: #{inspect(reason)}")}

      nil ->
        {:noreply, put_flash(socket, :error, "No binding selected.")}
    end
  end

  @impl true
  def render(assigns), do: Page.render(assigns)

  defp assign_source_inventory(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    data_sources = DataSources.list_data_sources(scope.organization_id, mission.mission_id)
    data_bindings = DataSources.list_data_bindings(scope.organization_id, mission.mission_id)
    credentials = SourceCredentials.list_references(scope.organization_id, mission.mission_id)

    health_statuses =
      SourceHealth.list_source_health_statuses(scope.organization_id, mission.mission_id)

    watermark_statuses =
      SourceWatermarks.list_source_watermark_statuses(scope.organization_id, mission.mission_id)

    health_events =
      SourceHealth.list_source_health_events(scope.organization_id, mission.mission_id, limit: 12)

    source_events =
      DataSources.list_data_source_events(scope.organization_id, mission.mission_id, limit: 12)

    deployment_runs =
      mission.mission_id
      |> tsdb_deployment_runs()
      |> Enum.sort_by(&deployment_run_sort_key/1, {:desc, DateTime})

    binding_events =
      data_bindings
      |> Enum.flat_map(&DataSources.list_data_binding_events(&1.binding_id, limit: 3))
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
      |> Enum.take(12)

    readiness_policy = SourceReadiness.policy()

    source_rows =
      SourceInventoryPresentation.rows(
        data_sources,
        credentials,
        health_statuses,
        watermark_statuses,
        readiness_policy
      )

    binding_groups =
      SourceBindingPresentation.groups(
        data_bindings,
        data_sources,
        credentials,
        health_statuses,
        readiness_policy
      )

    socket
    |> assign(:data_sources, data_sources)
    |> assign(:data_bindings, data_bindings)
    |> assign(:source_health_statuses, health_statuses)
    |> assign(:source_watermark_statuses, watermark_statuses)
    |> assign(
      :source_readiness_policy,
      SourceBindingPresentation.readiness_policy_row(readiness_policy)
    )
    |> assign(:binding_groups, binding_groups)
    |> assign(:source_rows, source_rows)
    |> assign(
      :deployment_run_rows,
      Enum.map(deployment_runs, &SourceActivityPresentation.deployment_run_row/1)
    )
    |> assign(
      :binding_event_rows,
      Enum.map(binding_events, &SourceActivityPresentation.binding_event_row/1)
    )
    |> assign(
      :source_event_rows,
      Enum.map(source_events, &SourceActivityPresentation.source_event_row/1)
    )
    |> assign(
      :source_health_event_rows,
      Enum.map(health_events, &SourceActivityPresentation.source_health_event_row/1)
    )
    |> assign_source_focus_state()
  end

  defp assign_source_focus_resources(socket) do
    %{
      current_scope: scope,
      current_mission: mission,
      source_focus: focus
    } = socket.assigns

    assign(
      socket,
      :source_focus_resources,
      resolve_source_focus_resources(scope.organization_id, mission.mission_id, focus)
    )
  end

  defp resolve_source_focus_resources(organization_id, mission_id, focus) do
    resources = %{
      transport: fetch_focused_transport(organization_id, mission_id, focus.transport_id),
      source_endpoint:
        fetch_focused_source_endpoint(organization_id, mission_id, focus.source_endpoint_id),
      link_assignment: fetch_focused_link_assignment(organization_id, mission_id, focus.link_id),
      routing_rule: nil,
      ground_station:
        fetch_focused_ground_station(organization_id, mission_id, focus.ground_station_id)
    }

    resources = %{
      resources
      | routing_rule:
          focused_routing_rule_for_link_assignment(organization_id, mission_id, focus.link_id)
    }

    SourceFocusResources.put_inferred_ground_station(resources, focus.ground_station_id)
  end

  defp fetch_focused_transport(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_transport(organization_id, mission_id, transport_id) do
    case TransportStore.fetch_transport(organization_id, mission_id, transport_id) do
      {:ok, transport} -> transport
      {:error, _reason} -> nil
    end
  end

  defp fetch_focused_source_endpoint(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_source_endpoint(organization_id, mission_id, source_endpoint_id) do
    case Cadence.SourceEndpoints.fetch_source_endpoint(
           organization_id,
           mission_id,
           source_endpoint_id
         ) do
      {:ok, source_endpoint} -> source_endpoint
      {:error, _reason} -> nil
    end
  end

  defp fetch_focused_link_assignment(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_link_assignment(organization_id, mission_id, link_assignment_id) do
    case Cadence.Contacts.fetch_link_assignment(organization_id, mission_id, link_assignment_id) do
      {:ok, link_assignment} -> link_assignment
      {:error, _reason} -> nil
    end
  end

  defp fetch_focused_ground_station(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_ground_station(organization_id, mission_id, ground_station_id) do
    case GroundStationStore.fetch_ground_station(
           organization_id,
           mission_id,
           ground_station_id
         ) do
      {:ok, ground_station} -> ground_station
      {:error, _reason} -> nil
    end
  end

  defp focused_routing_rule_for_link_assignment(_organization_id, _mission_id, nil), do: nil

  defp focused_routing_rule_for_link_assignment(organization_id, mission_id, link_assignment_id) do
    organization_id
    |> RoutingRuleStore.list_routing_rules(mission_id)
    |> Enum.find(&routing_rule_materialized_link?(&1, link_assignment_id))
  end

  defp routing_rule_materialized_link?(routing_rule, link_assignment_id) do
    routing_rule.materialized_link_assignment_id == link_assignment_id or
      link_assignment_id in materialized_link_assignment_ids(routing_rule.metadata)
  end

  defp materialized_link_assignment_ids(metadata) when is_map(metadata) do
    metadata
    |> Map.get(
      "materialized_link_assignment_ids",
      Map.get(metadata, :materialized_link_assignment_ids, [])
    )
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
  end

  defp materialized_link_assignment_ids(_metadata), do: []

  defp assign_source_focus_state(socket) do
    focus = Map.get(socket.assigns, :source_focus, SourceFocus.default())
    sources = Map.get(socket.assigns, :data_sources, [])
    bindings = Map.get(socket.assigns, :data_bindings, [])

    assign(socket, :source_focus, SourceFocus.resolve(focus, sources, bindings))
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp retry_deployment_run(job_id) do
    ManagedResources.retry_deployment_run(job_id)
  end

  defp requeue_deployment_run(job_id) do
    ManagedResources.requeue_deployment_run(job_id)
  end

  defp tsdb_deployment_runs(mission_id) do
    ManagedResourceStatus.deployment_runs(mission_id)
  end

  defp deployment_run_sort_key(run) do
    run.started_at ||
      run.completed_at ||
      (Map.get(run, :job) && Map.get(run.job, :started_at)) ||
      DateTime.from_unix!(0)
  end

  defp source_action_payload(socket, extra \\ %{}) do
    %{
      source: "ops_data_sources_live"
    }
    |> Map.merge(source_focus_event_payload(Map.get(socket.assigns, :source_focus)))
    |> Map.merge(extra)
    |> compact_query_params()
  end

  defp source_focus_event_payload(%{state: state} = focus) when state != "none" do
    %{
      source_dashboard_id: focus.source_dashboard_id,
      source_return_panel: SourceFocus.return_panel(focus),
      source_return_activity_filter: SourceFocus.return_activity_filter(focus),
      source_return_activity_event: SourceFocus.return_activity_event(focus),
      source_focus_state: focus.state,
      source_focus_data_source_id: focus.data_source_id,
      source_focus_binding_id: focus.source_binding_id,
      source_focus_logical_source: focus.logical_source,
      source_focus_realm: focus.realm,
      source_focus_selected_target: focus.selected_target,
      source_focus_selected_id: focus.selected_id,
      source_focus_transport_id: focus.transport_id,
      source_focus_source_endpoint_id: focus.source_endpoint_id,
      source_focus_ground_station_id: focus.ground_station_id,
      source_focus_link_id: focus.link_id,
      source_focus_reason: focus.source_empty_reason,
      selected_evidence_kind: focus.selected_evidence_kind,
      selected_source_evidence_mode: focus.selected_source_evidence_mode,
      selected_source_evidence_state: focus.selected_source_evidence_state
    }
  end

  defp source_focus_event_payload(_focus), do: %{}

  defp compact_query_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp maybe_register_source_credentials(%{credentials_ref: nil}, _scope, _payload), do: :ok

  defp maybe_register_source_credentials(attrs, scope, payload) do
    case SourceCredentials.fetch_reference(attrs.credentials_ref) do
      {:ok, _reference} ->
        :ok

      {:error, :credential_reference_not_found} ->
        attrs
        |> SourceRegistration.credential_attrs(payload)
        |> SourceCredentials.register_reference(actor_id: current_user_id(scope))
        |> case do
          {:ok, _reference, _event} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp find_binding(bindings, binding_id) do
    Enum.find(bindings, &(&1.binding_id == binding_id))
  end

  defp selected_data_source_id(%{"data_source_id" => data_source_id})
       when is_binary(data_source_id) do
    data_source_id = String.trim(data_source_id)

    if data_source_id == "" do
      {:error, "Choose a data source."}
    else
      {:ok, data_source_id}
    end
  end

  defp selected_data_source_id(_params), do: {:error, "Choose a data source."}

  defp change_binding_candidates(socket, %DataBinding{} = binding) do
    focus = socket.assigns.source_focus
    sources = socket.assigns.data_sources

    if focused_capability_binding?(focus, binding) do
      sources
      |> SourceContract.compatible_sources(binding)
      |> Enum.filter(&SourceContract.satisfies_focus?(&1, focus))
    else
      SourceContract.compatible_sources(sources, binding)
    end
  end

  defp validate_changed_source(%DataBinding{data_source_id: data_source_id}, data_source_id),
    do: {:error, "Choose a different data source."}

  defp validate_changed_source(%DataBinding{}, _data_source_id), do: :ok

  defp validate_compatible_source(sources, %DataBinding{} = binding, data_source_id) do
    sources
    |> SourceContract.compatible_sources(binding)
    |> Enum.any?(&(&1.data_source_id == data_source_id))
    |> case do
      true -> :ok
      false -> {:error, "Choose a compatible registered data source."}
    end
  end

  defp validate_focused_source_contract(focus, sources, %DataBinding{} = binding, data_source_id) do
    if focused_capability_binding?(focus, binding),
      do: validate_source_contract(sources, focus, data_source_id),
      else: :ok
  end

  defp validate_source_contract(sources, focus, data_source_id) do
    case Enum.find(sources, &(&1.data_source_id == data_source_id)) do
      %DataSource{} = source ->
        validate_source_contract(source, focus)

      nil ->
        {:error, "Choose a compatible registered data source."}
    end
  end

  defp validate_source_contract(%DataSource{} = source, focus) do
    if SourceContract.satisfies_focus?(source, focus) do
      :ok
    else
      {:error, "Choose a data source that satisfies the requested dashboard contract."}
    end
  end

  defp find_data_source(sources, data_source_id) do
    Enum.find(sources, &(&1.data_source_id == data_source_id))
  end

  defp source_probe_opts(%DataSource{} = source) do
    if metadata_value(source.metadata, :storage) in [:questdb, "questdb"] and
         questdb_live_probe_hint?(source) do
      [questdb_probe?: true]
    else
      []
    end
  end

  defp source_probe_opts(_source), do: []

  defp questdb_live_probe_hint?(%DataSource{} = source) do
    Enum.any?([:http_endpoint, :material_env_profile, :http_endpoint_env], fn key ->
      metadata_value(source.metadata, key) not in [nil, ""]
    end)
  end

  defp focused_capability_binding?(
         %{source_empty_reason: "unsupported_source_capability"} = focus,
         %DataBinding{} = binding
       ) do
    binding.binding_id in [focus.matched_source_binding_id, focus.source_binding_id]
  end

  defp focused_capability_binding?(_focus, _binding), do: false

  defp source_options(sources) do
    Enum.map(sources, fn source ->
      label =
        [
          source.data_source_id,
          text(source.kind),
          text(source.isolation_level)
        ]
        |> Enum.join(" / ")

      {label, source.data_source_id}
    end)
  end

  defp error_text(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp error_text(value) when is_atom(value), do: Atom.to_string(value)
  defp error_text(value), do: inspect(value)

  defp text(nil), do: "none"
  defp text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)

  defp clear_change_binding(socket) do
    socket
    |> assign(:change_binding, nil)
    |> assign(:change_binding_form, to_form(%{}, as: :binding))
    |> assign(:change_binding_error, nil)
  end

  defp clear_register_source(socket) do
    socket
    |> assign(:register_source?, false)
    |> assign(:register_source_form, to_form(SourceRegistration.defaults(), as: :source))
    |> assign(:register_source_error, nil)
  end

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
