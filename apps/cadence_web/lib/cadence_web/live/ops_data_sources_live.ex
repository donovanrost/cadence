defmodule CadenceWeb.OpsDataSourcesLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    SourceCapabilities,
    SourceCredentials,
    SourceHealth,
    SourceReadiness,
    SourceWatermarks,
    TSDBDeploymentStatus
  }

  @impl true
  def mount(_params, _session, socket) do
    # credo:disable-for-next-line Credo.Check.Design.TagTODO
    # todo(authz): require a mission-level source configuration/read permission once RBAC exists.
    {:ok,
     socket
     |> assign(:page_title, "Data Sources")
     |> assign(:ops_nav_item, :data_sources)
     |> assign(:change_binding, nil)
     |> assign(:change_binding_form, to_form(%{}, as: :binding))
     |> assign(:change_binding_error, nil)
     |> assign(:register_source?, false)
     |> assign(:register_source_form, to_form(register_source_defaults(), as: :source))
     |> assign(:register_source_error, nil)
     |> assign(:source_focus, default_source_focus())
     |> assign(:source_focus_resources, empty_source_focus_resources())
     |> assign_source_inventory()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    source_focus = source_focus_from_params(params)

    {:noreply,
     socket
     |> assign(:source_focus, source_focus)
     |> assign_source_focus_resources()
     |> assign_source_focus_state()}
  end

  @impl true
  def handle_event("open_register_source", _params, socket) do
    {:noreply,
     socket
     |> assign(:register_source?, true)
     |> assign(:register_source_form, to_form(register_source_defaults(), as: :source))
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

  def handle_event("probe_source", %{"data-source-id" => data_source_id}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    source = find_data_source(socket.assigns.data_sources, data_source_id)

    case DataSources.probe_data_source(
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
    case Cadence.Dashboards.retry_managed_questdb_provisioning_run(job_id) do
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
    case Cadence.Dashboards.requeue_managed_questdb_provisioning_run(job_id) do
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

    with {:ok, attrs} <- register_source_attrs(params, scope, mission),
         :ok <-
           maybe_register_source_credentials(
             attrs,
             scope,
             source_action_payload(socket, %{data_source_id: attrs.data_source_id})
           ),
         {:ok, _source} <-
           attrs
           |> data_source_from_attrs()
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
  def render(assigns) do
    ~H"""
    <div
      id="ops-data-sources-page"
      class="flex flex-1 min-h-0"
      data-source-focus-state={@source_focus.state}
      data-source-focus-data-source={@source_focus.data_source_id || ""}
      data-source-focus-binding={@source_focus.source_binding_id || ""}
      data-source-focus-logical-source={@source_focus.logical_source || ""}
      data-source-focus-realm={@source_focus.realm || ""}
      data-source-focus-scope-kind={@source_focus.scope_kind || ""}
      data-source-focus-scope-id={@source_focus.scope_id || ""}
      data-source-focus-contact-id={@source_focus.contact_id || ""}
      data-source-focus-selected-target={@source_focus.selected_target || ""}
      data-source-focus-selected-id={@source_focus.selected_id || ""}
      data-source-focus-transport-id={@source_focus.transport_id || ""}
      data-source-focus-source-endpoint-id={@source_focus.source_endpoint_id || ""}
      data-source-focus-ground-station-id={@source_focus.ground_station_id || ""}
      data-source-focus-link-id={@source_focus.link_id || ""}
      data-source-focus-empty-reason={@source_focus.source_empty_reason || ""}
      data-source-focus-requested-source-products={@source_focus.requested_source_products || ""}
      data-source-focus-requested-product-families={
        @source_focus.requested_product_families || ""
      }
      data-source-focus-dashboard={@source_focus.source_dashboard_id || ""}
      data-source-focus-evidence-kind={@source_focus.selected_evidence_kind || ""}
      data-source-focus-evidence-mode={@source_focus.selected_source_evidence_mode || ""}
      data-source-focus-evidence-state={@source_focus.selected_source_evidence_state || ""}
    >
      <div class="flex-1 min-w-0 overflow-y-auto">
        <div class="mx-auto max-w-6xl px-6 py-8">
        <div class="flex flex-col gap-3 border-b border-base-300/60 pb-5 md:flex-row md:items-end md:justify-between">
          <div>
            <h1 class="text-lg font-semibold text-base-content">Data Sources</h1>
            <p class="mt-1 font-mono text-xs text-base-content/60">
              {@current_mission.mission_id}
            </p>
          </div>
          <div class="flex flex-col items-stretch gap-3 md:items-end">
            <.button id="register-source-button" size={:sm} phx-click="open_register_source">
              <.icon name="hero-plus" class="h-4 w-4" /> Register Source
            </.button>
            <div class="grid grid-cols-3 gap-2 text-right">
              <.stat_tile label="sources" value={length(@data_sources)} />
              <.stat_tile label="bindings" value={length(@data_bindings)} />
              <.stat_tile label="health" value={length(@source_health_statuses)} />
            </div>
            <div
              id="source-readiness-policy"
              class="border border-base-300 bg-base-200 px-3 py-2 text-right"
              data-source-readiness-policy-id={@source_readiness_policy.policy_id}
              data-source-readiness-block-health={@source_readiness_policy.block_source_health}
              data-source-readiness-block-freshness={@source_readiness_policy.block_freshness}
              data-source-readiness-block-connection-test={
                @source_readiness_policy.block_connection_test
              }
            >
              <p class="hud-label">readiness policy</p>
              <p class="font-mono text-xs text-base-content">
                {@source_readiness_policy.policy_id}
              </p>
              <p class="mt-1 font-mono text-[0.65rem] text-base-content/60">
                conn {@source_readiness_policy.block_connection_test}
              </p>
            </div>
          </div>
        </div>

        <div
          :if={@source_focus.state != "none"}
          id="source-focus-status"
          class={[
            "mt-5 flex items-start gap-3 border px-4 py-3 text-sm",
            @source_focus.state == "matched" && "border-primary/30 bg-primary/5 text-base-content",
            @source_focus.state == "missing" && "border-warning/30 bg-warning/10 text-base-content"
          ]}
          data-source-focus-state={@source_focus.state}
          data-source-focus-data-source={@source_focus.data_source_id || ""}
          data-source-focus-binding={@source_focus.source_binding_id || ""}
          data-source-focus-logical-source={@source_focus.logical_source || ""}
          data-source-focus-realm={@source_focus.realm || ""}
          data-source-focus-scope-kind={@source_focus.scope_kind || ""}
          data-source-focus-scope-id={@source_focus.scope_id || ""}
          data-source-focus-contact-id={@source_focus.contact_id || ""}
          data-source-focus-selected-target={@source_focus.selected_target || ""}
          data-source-focus-selected-id={@source_focus.selected_id || ""}
          data-source-focus-transport-id={@source_focus.transport_id || ""}
          data-source-focus-source-endpoint-id={@source_focus.source_endpoint_id || ""}
          data-source-focus-ground-station-id={@source_focus.ground_station_id || ""}
          data-source-focus-link-id={@source_focus.link_id || ""}
          data-source-focus-empty-reason={@source_focus.source_empty_reason || ""}
          data-source-focus-requested-source-products={
            @source_focus.requested_source_products || ""
          }
          data-source-focus-requested-product-families={
            @source_focus.requested_product_families || ""
          }
          data-source-focus-dashboard={@source_focus.source_dashboard_id || ""}
          data-source-focus-evidence-kind={@source_focus.selected_evidence_kind || ""}
          data-source-focus-evidence-mode={@source_focus.selected_source_evidence_mode || ""}
          data-source-focus-evidence-state={@source_focus.selected_source_evidence_state || ""}
        >
          <.icon name={source_focus_icon(@source_focus)} class="mt-0.5 h-4 w-4 shrink-0" />
          <div class="min-w-0">
            <p class="font-semibold">{source_focus_title(@source_focus)}</p>
            <p class="mt-1 break-all font-mono text-xs text-base-content/60">
              {source_focus_detail(@source_focus)}
            </p>
            <.source_focus_remediation_panel
              focus={@source_focus}
              data_sources={@data_sources}
              mission_id={@current_mission.mission_id}
            />
            <.source_focus_resource_panel
              focus={@source_focus}
              resources={@source_focus_resources}
              mission_id={@current_mission.mission_id}
            />
            <.source_focus_evidence_panel
              focus={@source_focus}
              mission_id={@current_mission.mission_id}
            />
          </div>
        </div>

        <section
          :if={@register_source?}
          id="register-source-panel"
          class="mt-5 border border-primary/20 bg-base-200/60 p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <h2 class="text-sm font-semibold text-base-content">Register Source</h2>
              <p class="mt-1 text-xs text-base-content/60">
                Source descriptors are scoped to this mission. BYO sources store only a non-secret credential reference.
              </p>
            </div>
            <.button id="cancel-register-source-top" variant={:ghost} size={:xs} phx-click="cancel_register_source">
              <.icon name="hero-x-mark" class="h-4 w-4" />
            </.button>
          </div>

          <.form
            for={@register_source_form}
            id="register-source-form"
            phx-submit="register_source"
            class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4"
          >
            <.input
              field={@register_source_form[:data_source_id]}
              label="Source ID"
              placeholder="rehearsal-questdb"
              required
            />
            <.input
              field={@register_source_form[:logical_source]}
              type="select"
              label="Logical source"
              options={logical_source_options()}
              required
            />
            <.input
              field={@register_source_form[:kind]}
              type="select"
              label="Ownership"
              options={source_kind_options()}
              required
            />
            <.input
              field={@register_source_form[:isolation_level]}
              type="select"
              label="Isolation"
              options={source_isolation_options()}
              required
            />
            <.input
              field={@register_source_form[:credentials_ref]}
              label="Credential ref"
              placeholder="cred-rehearsal-questdb"
            />
            <.input
              field={@register_source_form[:credential_provider]}
              type="select"
              label="Credential provider"
              options={credential_provider_options()}
            />
            <.input
              field={@register_source_form[:endpoint_ref]}
              label="Endpoint ref"
              placeholder="endpoint://customer/rehearsal"
            />
            <.input
              field={@register_source_form[:material_env_profile]}
              label="Env material profile"
              placeholder="customer-rehearsal-questdb"
            />
            <.input
              field={@register_source_form[:http_endpoint_env]}
              label="HTTP endpoint env"
              placeholder="CADENCE_CUSTOMER_QUESTDB_HTTP_ENDPOINT"
            />
            <.input
              field={@register_source_form[:storage]}
              type="select"
              label="Storage"
              options={source_storage_options()}
              required
            />
            <div class="flex items-end gap-2">
              <.button id="submit-register-source" type="submit" size={:sm}>
                Register
              </.button>
              <.button id="cancel-register-source" variant={:ghost} size={:sm} phx-click="cancel_register_source">
                Cancel
              </.button>
            </div>
          </.form>

          <p :if={@register_source_error} id="register-source-error" class="mt-2 text-xs text-error">
            {@register_source_error}
          </p>
        </section>

        <div class="mt-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <section class="space-y-4">
            <div class="flex items-center justify-between gap-3">
              <h2 class="hud-label">Bindings</h2>
              <span class="font-mono text-xs text-base-content/50">
                grouped by logical source and realm
              </span>
            </div>

            <div :if={@binding_groups == []} class="border border-dashed border-base-300 p-6">
              <p class="text-sm text-base-content/70">No dashboard source bindings registered.</p>
            </div>

            <div
              :for={group <- @binding_groups}
              id={"source-binding-group-#{group.id}"}
              class="border border-base-300 bg-base-200/50"
              data-source-binding-group={group.id}
            >
              <div class="flex items-center justify-between gap-3 border-b border-base-300 px-3 py-2">
                <div class="min-w-0">
                  <h3 class="text-sm font-semibold text-base-content">
                    {group.logical_source_text}
                    <span class="text-base-content/40">/</span>
                    {group.realm_text}
                  </h3>
                  <p class="font-mono text-xs text-base-content/50">
                    {length(group.rows)} bindings
                  </p>
                </div>
                <.status_pill status={group.group_status} />
              </div>

              <div class="divide-y divide-base-300/70">
                <div
                  :for={row <- group.rows}
                  id={"source-binding-#{row.binding.binding_id}"}
                  class={[
                    "grid gap-3 px-3 py-3 xl:grid-cols-[minmax(13rem,1fr)_minmax(16rem,1.1fr)_minmax(11rem,.7fr)]",
                    binding_focused?(@source_focus, row) &&
                      "ring-1 ring-inset ring-primary/40 bg-primary/5"
                  ]}
                  data-source-focus={binding_focused?(@source_focus, row)}
                  data-source-binding-id={row.binding.binding_id}
                  data-logical-source={row.logical_source_text}
                  data-source-realm={row.realm_text}
                  data-data-source-id={row.data_source_id}
                  data-source-health={row.health_status}
                  data-source-readiness={row.source_readiness_status}
                  data-source-readiness-reasons={row.source_readiness_reason_text}
                  data-source-readiness-policy={row.source_readiness_policy_id}
                >
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <p class="truncate font-mono text-xs font-semibold text-base-content">
                        {row.binding.binding_id}
                      </p>
                      <.status_pill status={row.binding_status} />
                      <.button
                        id={"change-binding-#{row.binding.binding_id}"}
                        variant={:ghost}
                        size={:xs}
                        phx-click="open_change_binding"
                        phx-value-binding-id={row.binding.binding_id}
                      >
                        <.icon name="hero-arrows-right-left" class="h-3.5 w-3.5" /> Change
                      </.button>
                    </div>
                    <dl class="mt-2 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <.kv label="dataset" value={row.dataset_text} />
                      <.kv label="priority" value={row.priority_text} />
                      <.kv label="version" value={row.version_text} />
                      <.kv label="active from" value={row.active_from_text} />
                      <.kv label="active to" value={row.active_to_text} />
                    </dl>
                  </div>

                  <div class="min-w-0">
                    <p class="hud-label">Physical source</p>
                    <p class="mt-1 truncate font-mono text-xs text-base-content">
                      {row.data_source_id}
                    </p>
                  <dl class="mt-2 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <.kv label="status" value={row.source_status_text} />
                      <.kv label="kind" value={row.source_kind_text} />
                      <.kv label="owner" value={row.source_owner_text} />
                      <.kv label="isolation" value={row.source_isolation_text} />
                      <.kv label="adapter" value={row.source_adapter_text} />
                      <.kv label="credential" value={row.credential_ref_text} />
                    </dl>
                  </div>

                  <div class="min-w-0">
                    <p class="hud-label">Health</p>
                    <div class="mt-1 flex items-center gap-2">
                      <.status_pill status={row.health_status} />
                      <span class="font-mono text-xs text-base-content/60">
                        {row.health_reason_text}
                      </span>
                    </div>
                    <dl class="mt-2 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <.kv label="observed" value={row.health_observed_at_text} />
                      <.kv label="event" value={row.health_event_type_text} />
                      <.kv label="current event" value={row.current_event_id_text} />
                      <.kv label="readiness" value={row.source_readiness_status} />
                      <.kv label="policy" value={row.source_readiness_policy_id} />
                      <.kv label="reason" value={row.source_readiness_reason_text} />
                    </dl>
                  </div>

                  <div
                    :if={change_binding_open?(@change_binding, row.binding.binding_id)}
                    id={"change-binding-form-panel-#{row.binding.binding_id}"}
                    class="border-t border-primary/20 bg-base-100/80 px-3 py-3 xl:col-span-3"
                  >
                    <.form
                      for={@change_binding_form}
                      id={"change-binding-form-#{row.binding.binding_id}"}
                      phx-submit="change_binding"
                      class="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto]"
                    >
                      <div>
                        <.input
                          field={@change_binding_form[:data_source_id]}
                          type="select"
                          label="Data source"
                          options={@change_binding.source_options}
                          required
                        />
                        <p
                          :if={@change_binding_error}
                          id={"change-binding-error-#{row.binding.binding_id}"}
                          class="mt-2 text-xs text-error"
                        >
                          {@change_binding_error}
                        </p>
                      </div>
                      <div class="flex items-end gap-2">
                        <.button
                          id={"submit-change-binding-#{row.binding.binding_id}"}
                          type="submit"
                          size={:sm}
                        >
                          Apply
                        </.button>
                        <.button
                          id={"cancel-change-binding-#{row.binding.binding_id}"}
                          variant={:ghost}
                          size={:sm}
                          phx-click="cancel_change_binding"
                        >
                          Cancel
                        </.button>
                      </div>
                    </.form>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <aside class="space-y-4">
            <.card heading="Physical Sources" subtitle="Registered adapter-backed stores" padding={:none}>
              <div
                :if={@source_rows == []}
                class="px-4 py-5 text-sm text-base-content/70"
              >
                No data sources registered.
              </div>
              <div class="divide-y divide-base-300/70">
                <div
                  :for={source <- @source_rows}
                  id={"data-source-#{source.data_source_id}"}
                  class={[
                    "px-4 py-3",
                    source_focused?(@source_focus, source) &&
                      "ring-1 ring-inset ring-primary/40 bg-primary/5"
                  ]}
                  data-source-focus={source_focused?(@source_focus, source)}
                  data-data-source-row={source.data_source_id}
                  data-source-status={source.status_text}
                  data-source-health={source.health_status}
                  data-source-readiness={source.source_readiness_status}
                  data-source-readiness-reasons={source.source_readiness_reason_text}
                  data-source-readiness-policy={source.source_readiness_policy_id}
                  data-source-probe-kind={source.probe_kind_text}
                  data-source-probe-message={source.probe_message_text}
                  data-source-probe-metadata={source.probe_metadata_text}
                  data-source-probe-diagnostic-kind={source.probe_diagnostic_kind_text}
                  data-source-probe-diagnostic-stage={source.probe_diagnostic_stage_text}
                  data-source-probe-remediation={source.probe_remediation_text}
                  data-source-connection-test-result={source.connection_test_result_text}
                  data-source-connection-test-kind={source.connection_test_kind_text}
                  data-source-connection-test-message={source.connection_test_message_text}
                  data-source-credential-state={source.credential_state_text}
                  data-source-credential-provider={source.credential_provider_text}
                  data-source-credential-version={source.credential_version_text}
                  data-source-credential-material-state={source.credential_material_state_text}
                  data-source-credential-endpoint={source.credential_endpoint_text}
                  data-source-credential-secret-fields={source.credential_secret_fields_text}
                  data-source-deployment-status={source.deployment_status_text}
                  data-source-deployment-mode={source.deployment_mode_text}
                  data-source-deployment-backend={source.deployment_backend_text}
                  data-source-deployment-boundary={source.deployment_boundary_text}
                  data-source-deployment-job-id={source.deployment_job_id_text}
                  data-source-deployment-run-id={source.deployment_run_id_text}
                  data-source-deployment-remediation={source.deployment_remediation_text}
                  data-source-supported-sampling={source.supported_sampling_text}
                  data-source-supported-products={source.supported_products_text}
                  data-source-supported-metric-history-products={
                    source.supported_metric_history_products_text
                  }
                  data-source-supported-product-families={source.supported_product_families_text}
                >
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <p class="truncate font-mono text-xs font-semibold text-base-content">
                        {source.data_source_id}
                      </p>
                      <p class="mt-1 text-xs text-base-content/60">
                        {source.kind_text} · {source.owner_text} · {source.isolation_text}
                      </p>
                    </div>
                    <div class="flex shrink-0 flex-col items-end gap-2">
                      <div class="flex flex-wrap justify-end gap-1">
                        <.status_pill status={source.status_text} />
                        <.status_pill status={source.health_status} />
                      </div>
                      <.button
                        :if={source.status_text == "active"}
                        id={"probe-source-#{source.data_source_id}"}
                        variant={:ghost}
                        size={:xs}
                        phx-click="probe_source"
                        phx-value-data-source-id={source.data_source_id}
                      >
                        <.icon name="hero-arrow-path" class="h-3.5 w-3.5" /> Probe
                      </.button>
                      <.button
                        :if={source.status_text == "active"}
                        id={"disable-source-#{source.data_source_id}"}
                        variant={:danger}
                        size={:xs}
                        phx-click="disable_source"
                        phx-value-data-source-id={source.data_source_id}
                        data-confirm="Disable this data source?"
                      >
                        <.icon name="hero-pause" class="h-3.5 w-3.5" /> Disable
                      </.button>
                      <.button
                        :if={source.status_text == "disabled"}
                        id={"enable-source-#{source.data_source_id}"}
                        variant={:secondary}
                        size={:xs}
                        phx-click="enable_source"
                        phx-value-data-source-id={source.data_source_id}
                      >
                        <.icon name="hero-play" class="h-3.5 w-3.5" /> Enable
                      </.button>
                    </div>
                  </div>
                  <dl class="mt-3 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                    <.kv label="status" value={source.status_text} />
                    <.kv label="readiness" value={source.source_readiness_status} />
                    <.kv label="policy" value={source.source_readiness_policy_id} />
                    <.kv label="ready reason" value={source.source_readiness_reason_text} />
                    <.kv label="health reason" value={source.health_reason_text} />
                    <.kv label="probe kind" value={source.probe_kind_text} />
                    <.kv label="probe message" value={source.probe_message_text} />
                    <.kv label="probe metadata" value={source.probe_metadata_text} />
                    <.kv label="diagnostic" value={source.probe_diagnostic_kind_text} />
                    <.kv label="diag stage" value={source.probe_diagnostic_stage_text} />
                    <.kv label="remediation" value={source.probe_remediation_text} />
                    <.kv label="connection" value={source.connection_test_result_text} />
                    <.kv label="conn kind" value={source.connection_test_kind_text} />
                    <.kv label="conn detail" value={source.connection_test_message_text} />
                    <.kv label="watermark" value={source.watermark_text} />
                    <.kv label="confidence" value={source.watermark_confidence_text} />
                    <.kv label="adapter" value={source.adapter_text} />
                    <.kv label="credential" value={source.credential_ref_text} />
                    <.kv label="cred state" value={source.credential_state_text} />
                    <.kv label="cred provider" value={source.credential_provider_text} />
                    <.kv label="cred material" value={source.credential_material_state_text} />
                    <.kv label="cred endpoint" value={source.credential_endpoint_text} />
                    <.kv label="cred fields" value={source.credential_secret_fields_text} />
                    <.kv label="deploy" value={source.deployment_status_text} />
                    <.kv label="deploy mode" value={source.deployment_mode_text} />
                    <.kv label="backend" value={source.deployment_backend_text} />
                    <.kv label="boundary" value={source.deployment_boundary_text} />
                    <.kv label="deploy job" value={source.deployment_job_id_text} />
                    <.kv label="deploy run" value={source.deployment_run_id_text} />
                    <.kv label="deploy fix" value={source.deployment_remediation_text} />
                    <.kv label="capability" value={source.capability_text} />
                    <.kv label="sampling" value={source.supported_sampling_text} />
                    <.kv label="products" value={source.supported_products_text} />
                    <.kv label="history" value={source.supported_metric_history_products_text} />
                    <.kv label="families" value={source.supported_product_families_text} />
                  </dl>
                </div>
              </div>
            </.card>

            <.card heading="Deployment Runs" subtitle="Managed TSDB provisioning jobs" padding={:none}>
              <div
                :if={@deployment_run_rows == []}
                class="px-4 py-5 text-sm text-base-content/70"
              >
                No deployment runs recorded.
              </div>
              <div class="divide-y divide-base-300/70">
                <div
                  :for={run <- @deployment_run_rows}
                  id={"deployment-run-#{run.run_id}"}
                  class="px-4 py-3"
                  data-deployment-run-row={run.run_id}
                  data-deployment-run-job-id={run.job_id}
                  data-deployment-run-data-source-id={run.data_source_id}
                  data-deployment-run-status={run.status_text}
                  data-deployment-run-mode={run.mode_text}
                  data-deployment-run-backend={run.backend_text}
                  data-deployment-run-boundary={run.physical_boundary_text}
                  data-deployment-run-attempt-count={run.attempt_count_text}
                  data-deployment-run-failure-summary={run.failure_summary}
                  data-deployment-run-remediation={run.remediation}
                >
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <p class="truncate font-mono text-xs font-semibold text-base-content">
                        {run.data_source_id}
                      </p>
                      <p class="mt-1 truncate font-mono text-xs text-base-content/60">
                        {run.run_id}
                      </p>
                    </div>
                    <div class="flex shrink-0 flex-col items-end gap-2">
                      <.status_pill status={run.status_text} />
                      <.button
                        :if={run.status_text == "failed"}
                        id={"retry-deployment-run-#{run.run_id}"}
                        variant={:secondary}
                        size={:xs}
                        phx-click="retry_deployment_run"
                        phx-value-job-id={run.job_id}
                      >
                        <.icon name="hero-arrow-path" class="h-3.5 w-3.5" /> Retry
                      </.button>
                      <.button
                        :if={run.status_text == "provisioning"}
                        id={"requeue-deployment-run-#{run.run_id}"}
                        variant={:secondary}
                        size={:xs}
                        phx-click="requeue_deployment_run"
                        phx-value-job-id={run.job_id}
                      >
                        <.icon name="hero-arrow-path" class="h-3.5 w-3.5" /> Requeue
                      </.button>
                    </div>
                  </div>
                  <dl class="mt-3 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                    <.kv label="job" value={run.job_id} />
                    <.kv label="mode" value={run.mode_text} />
                    <.kv label="backend" value={run.backend_text} />
                    <.kv label="boundary" value={run.physical_boundary_text} />
                    <.kv label="attempts" value={run.attempt_count_text} />
                    <.kv label="started" value={run.started_at_text} />
                    <.kv label="completed" value={run.completed_at_text} />
                    <.kv label="failure" value={run.failure_summary} />
                    <.kv label="fix" value={run.remediation} />
                  </dl>
                </div>
              </div>
            </.card>

            <.card heading="Recent Binding Events" subtitle="Current projection changes" padding={:none}>
              <.event_list
                id="dashboard-data-binding-events"
                rows={@binding_event_rows}
                empty="No binding events recorded."
              />
            </.card>

            <.card heading="Recent Source Events" subtitle="Physical source descriptor changes" padding={:none}>
              <.event_list
                id="dashboard-data-source-events"
                rows={@source_event_rows}
                empty="No source events recorded."
              />
            </.card>

            <.card heading="Recent Source Health" subtitle="Source subsystem transitions" padding={:none}>
              <.event_list
                id="dashboard-source-health-events"
                rows={@source_health_event_rows}
                empty="No source health events recorded."
              />
            </.card>
          </aside>
        </div>
        </div>
      </div>
      <.mission_context_rail fleet_health={@fleet_health} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp kv(assigns) do
    ~H"""
    <dt class="text-base-content/50">{@label}</dt>
    <dd class="break-all font-mono text-base-content">{@value}</dd>
    """
  end

  attr :status, :string, required: true

  defp status_pill(assigns) do
    ~H"""
    <.status_badge status={pill_status(@status)} label={@status} data-status-pill={@status} />
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :empty, :string, required: true

  defp event_list(assigns) do
    ~H"""
    <div id={@id} class="divide-y divide-base-300/70">
      <div :if={@rows == []} class="px-4 py-5 text-sm text-base-content/70">
        {@empty}
      </div>
      <div
        :for={row <- @rows}
        id={row.id}
        class="px-4 py-3"
        data-event-type={row.event_type}
        data-event-probe-kind={Map.get(row, :probe_kind, "")}
        data-event-probe-message={Map.get(row, :probe_message, "")}
        data-event-probe-metadata={Map.get(row, :probe_metadata, "")}
        data-event-probe-diagnostic-kind={Map.get(row, :probe_diagnostic_kind, "")}
        data-event-probe-diagnostic-stage={Map.get(row, :probe_diagnostic_stage, "")}
        data-event-probe-remediation={Map.get(row, :probe_remediation, "")}
        data-event-connection-test-result={Map.get(row, :connection_test_result, "")}
        data-event-connection-test-kind={Map.get(row, :connection_test_kind, "")}
        data-event-connection-test-message={Map.get(row, :connection_test_message, "")}
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="text-xs font-semibold text-base-content">{row.title}</p>
            <p class="mt-1 truncate font-mono text-xs text-base-content/60">{row.subtitle}</p>
          </div>
          <span class="shrink-0 font-mono text-[0.65rem] text-base-content/50">
            {row.occurred_at}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp change_binding_open?(%{binding: %DataBinding{binding_id: binding_id}}, binding_id),
    do: true

  defp change_binding_open?(_change_binding, _binding_id), do: false

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
      Cadence.Dashboards.list_managed_questdb_provisioning_runs(mission.mission_id)

    binding_events =
      data_bindings
      |> Enum.flat_map(&DataSources.list_data_binding_events(&1.binding_id, limit: 3))
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
      |> Enum.take(12)

    readiness_policy = SourceReadiness.policy()

    source_rows =
      source_rows(
        data_sources,
        credentials,
        health_statuses,
        watermark_statuses,
        readiness_policy
      )

    binding_groups =
      binding_groups(data_bindings, data_sources, credentials, health_statuses, readiness_policy)

    socket
    |> assign(:data_sources, data_sources)
    |> assign(:data_bindings, data_bindings)
    |> assign(:source_health_statuses, health_statuses)
    |> assign(:source_watermark_statuses, watermark_statuses)
    |> assign(:source_readiness_policy, readiness_policy_row(readiness_policy))
    |> assign(:binding_groups, binding_groups)
    |> assign(:source_rows, source_rows)
    |> assign(:deployment_run_rows, Enum.map(deployment_runs, &deployment_run_row/1))
    |> assign(:binding_event_rows, Enum.map(binding_events, &binding_event_row/1))
    |> assign(:source_event_rows, Enum.map(source_events, &source_event_row/1))
    |> assign(:source_health_event_rows, Enum.map(health_events, &source_health_event_row/1))
    |> assign_source_focus_state()
  end

  defp default_source_focus do
    %{
      state: "none",
      data_source_id: nil,
      source_binding_id: nil,
      logical_source: nil,
      realm: nil,
      scope_kind: nil,
      scope_id: nil,
      contact_id: nil,
      selected_target: nil,
      selected_id: nil,
      transport_id: nil,
      source_endpoint_id: nil,
      ground_station_id: nil,
      link_id: nil,
      source_empty_reason: nil,
      requested_sampling: nil,
      supported_sampling: nil,
      requested_products: nil,
      requested_source_products: nil,
      supported_products: nil,
      requested_product_families: nil,
      supported_product_families: nil,
      requested_value_kinds: nil,
      supported_value_kinds: nil,
      requested_shapes: nil,
      supported_shapes: nil,
      requested_time_axes: nil,
      supported_time_axes: nil,
      source_dashboard_id: nil,
      source_return_panel: nil,
      source_return_activity_filter: nil,
      source_return_activity_event: nil,
      selected_evidence_kind: nil,
      selected_source_evidence_mode: nil,
      selected_source_evidence_state: nil,
      matched_data_source_id: nil,
      matched_source_binding_id: nil
    }
  end

  defp source_focus_from_params(params) do
    focus = %{
      default_source_focus()
      | state: "pending",
        data_source_id: optional_text(Map.get(params, "data_source_id")),
        source_binding_id: optional_text(Map.get(params, "source_binding_id")),
        logical_source: optional_text(Map.get(params, "logical_source")),
        realm: optional_text(Map.get(params, "realm")),
        scope_kind: optional_text(Map.get(params, "scope_kind")),
        scope_id: optional_text(Map.get(params, "scope_id")),
        contact_id: optional_text(Map.get(params, "contact_id")),
        selected_target: optional_text(Map.get(params, "selected_target")),
        selected_id: optional_text(Map.get(params, "selected_id")),
        transport_id: optional_text(Map.get(params, "transport_id")),
        source_endpoint_id: optional_text(Map.get(params, "source_endpoint_id")),
        ground_station_id: optional_text(Map.get(params, "ground_station_id")),
        link_id: optional_text(Map.get(params, "link_id")),
        source_empty_reason: optional_text(Map.get(params, "source_empty_reason")),
        requested_sampling: optional_text(Map.get(params, "requested_sampling")),
        supported_sampling: optional_text(Map.get(params, "supported_sampling")),
        requested_products: optional_text(Map.get(params, "requested_products")),
        requested_source_products: optional_text(Map.get(params, "requested_source_products")),
        supported_products: optional_text(Map.get(params, "supported_products")),
        requested_product_families: optional_text(Map.get(params, "requested_product_families")),
        supported_product_families: optional_text(Map.get(params, "supported_product_families")),
        requested_value_kinds: optional_text(Map.get(params, "requested_value_kinds")),
        supported_value_kinds: optional_text(Map.get(params, "supported_value_kinds")),
        requested_shapes: optional_text(Map.get(params, "requested_shapes")),
        supported_shapes: optional_text(Map.get(params, "supported_shapes")),
        requested_time_axes: optional_text(Map.get(params, "requested_time_axes")),
        supported_time_axes: optional_text(Map.get(params, "supported_time_axes")),
        source_dashboard_id: optional_text(Map.get(params, "source_dashboard_id")),
        source_return_panel: optional_text(Map.get(params, "source_return_panel")),
        source_return_activity_filter:
          optional_text(Map.get(params, "source_return_activity_filter")),
        source_return_activity_event:
          optional_text(Map.get(params, "source_return_activity_event")),
        selected_evidence_kind: optional_text(Map.get(params, "selected_evidence_kind")),
        selected_source_evidence_mode:
          optional_text(Map.get(params, "selected_source_evidence_mode")),
        selected_source_evidence_state:
          optional_text(Map.get(params, "selected_source_evidence_state"))
    }

    if source_focus_requested?(focus), do: focus, else: default_source_focus()
  end

  defp source_focus_requested?(focus) do
    Enum.any?(
      [
        focus.data_source_id,
        focus.source_binding_id,
        focus.logical_source,
        focus.realm,
        focus.scope_kind,
        focus.scope_id,
        focus.contact_id,
        focus.selected_target,
        focus.selected_id,
        focus.transport_id,
        focus.source_endpoint_id,
        focus.ground_station_id,
        focus.link_id,
        focus.source_empty_reason,
        focus.requested_sampling,
        focus.supported_sampling,
        focus.requested_products,
        focus.requested_source_products,
        focus.supported_products,
        focus.requested_product_families,
        focus.supported_product_families,
        focus.requested_value_kinds,
        focus.supported_value_kinds,
        focus.requested_shapes,
        focus.supported_shapes,
        focus.requested_time_axes,
        focus.supported_time_axes,
        focus.selected_evidence_kind,
        focus.selected_source_evidence_mode,
        focus.selected_source_evidence_state
      ],
      &is_binary/1
    )
  end

  defp empty_source_focus_resources do
    %{
      transport: nil,
      source_endpoint: nil,
      link_assignment: nil,
      routing_rule: nil,
      ground_station: nil
    }
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

    %{
      resources
      | ground_station:
          resources.ground_station || inferred_ground_station(focus.ground_station_id, resources)
    }
  end

  defp fetch_focused_transport(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_transport(organization_id, mission_id, transport_id) do
    case Cadence.fetch_transport(organization_id, mission_id, transport_id) do
      {:ok, transport} -> transport
      {:error, _reason} -> nil
    end
  end

  defp fetch_focused_source_endpoint(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_source_endpoint(organization_id, mission_id, source_endpoint_id) do
    case Cadence.fetch_source_endpoint(organization_id, mission_id, source_endpoint_id) do
      {:ok, source_endpoint} -> source_endpoint
      {:error, _reason} -> nil
    end
  end

  defp fetch_focused_link_assignment(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_link_assignment(organization_id, mission_id, link_assignment_id) do
    case Cadence.fetch_link_assignment(organization_id, mission_id, link_assignment_id) do
      {:ok, link_assignment} -> link_assignment
      {:error, _reason} -> nil
    end
  end

  defp fetch_focused_ground_station(_organization_id, _mission_id, nil), do: nil

  defp fetch_focused_ground_station(organization_id, mission_id, ground_station_id) do
    case Cadence.fetch_ground_station(organization_id, mission_id, ground_station_id) do
      {:ok, ground_station} -> ground_station
      {:error, _reason} -> nil
    end
  end

  defp focused_routing_rule_for_link_assignment(_organization_id, _mission_id, nil), do: nil

  defp focused_routing_rule_for_link_assignment(organization_id, mission_id, link_assignment_id) do
    organization_id
    |> Cadence.list_routing_rules(mission_id)
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

  defp inferred_ground_station(nil, _resources), do: nil

  defp inferred_ground_station(ground_station_id, resources) do
    source_label =
      [
        ground_station_source(resources.source_endpoint, ground_station_id),
        ground_station_source(resources.transport, ground_station_id),
        ground_station_source(resources.link_assignment, ground_station_id)
      ]
      |> Enum.find(&is_binary/1)

    %{
      id: ground_station_id,
      label: ground_station_label(ground_station_id, source_label),
      status: if(source_label, do: :inferred, else: :unverified)
    }
  end

  defp ground_station_source(nil, _ground_station_id), do: nil

  defp ground_station_source(resource, ground_station_id) do
    metadata = resource_value(resource, :metadata) || %{}
    configuration = resource_value(resource, :configuration) || %{}

    candidate =
      metadata_value(metadata, "ground_station_id") ||
        metadata_value(metadata, "antenna_id") ||
        metadata_value(configuration, "ground_station_id") ||
        metadata_value(configuration, "antenna_id")

    if candidate == ground_station_id do
      resource_label(resource)
    end
  end

  defp assign_source_focus_state(socket) do
    focus = Map.get(socket.assigns, :source_focus, default_source_focus())
    sources = Map.get(socket.assigns, :data_sources, [])
    bindings = Map.get(socket.assigns, :data_bindings, [])

    assign(socket, :source_focus, resolve_source_focus(focus, sources, bindings))
  end

  defp resolve_source_focus(%{state: "none"} = focus, _sources, _bindings), do: focus

  defp resolve_source_focus(focus, sources, bindings) do
    source_by_id = Map.new(sources, &{&1.data_source_id, &1})
    requested_source = requested_source(focus, source_by_id)
    requested_binding = requested_binding(focus, bindings)
    context_binding = context_binding(focus, bindings)
    matched_binding = first_present(requested_binding, context_binding)

    matched_source =
      first_present(requested_source, binding_source(matched_binding, source_by_id))

    if source_focus_matched?(
         focus,
         requested_source,
         requested_binding,
         matched_source,
         matched_binding
       ) do
      %{
        focus
        | state: "matched",
          matched_data_source_id: matched_data_source_id(matched_source),
          matched_source_binding_id: matched_source_binding_id(matched_binding)
      }
    else
      %{focus | state: "missing", matched_data_source_id: nil, matched_source_binding_id: nil}
    end
  end

  defp requested_source(%{data_source_id: nil}, _source_by_id), do: nil
  defp requested_source(focus, source_by_id), do: Map.get(source_by_id, focus.data_source_id)

  defp requested_binding(%{source_binding_id: nil}, _bindings), do: nil
  defp requested_binding(focus, bindings), do: find_binding(bindings, focus.source_binding_id)

  defp context_binding(focus, bindings),
    do: Enum.find(bindings, &binding_matches_focus?(&1, focus))

  defp binding_matches_focus?(%DataBinding{} = binding, focus) do
    binding_matches_context?(binding, focus) and binding_matches_source?(binding, focus)
  end

  defp binding_matches_source?(_binding, %{data_source_id: nil}), do: true

  defp binding_matches_source?(%DataBinding{} = binding, focus),
    do: binding.data_source_id == focus.data_source_id

  defp binding_source(nil, _source_by_id), do: nil

  defp binding_source(%DataBinding{} = binding, source_by_id),
    do: Map.get(source_by_id, binding.data_source_id)

  defp first_present(nil, fallback), do: fallback
  defp first_present(value, _fallback), do: value

  defp matched_data_source_id(nil), do: nil
  defp matched_data_source_id(%DataSource{} = source), do: source.data_source_id

  defp matched_source_binding_id(nil), do: nil
  defp matched_source_binding_id(%DataBinding{} = binding), do: binding.binding_id

  defp source_focus_matched?(
         focus,
         requested_source,
         requested_binding,
         matched_source,
         matched_binding
       ) do
    source_focus_requested?(focus) and
      requested_source_found?(focus, requested_source) and
      requested_binding_found?(focus, requested_binding) and
      binding_source_consistent?(focus, matched_binding) and
      context_consistent?(focus, matched_binding) and
      source_or_binding_found?(matched_source, matched_binding)
  end

  defp source_or_binding_found?(nil, nil), do: false
  defp source_or_binding_found?(_source, _binding), do: true

  defp requested_source_found?(%{data_source_id: nil}, _requested_source), do: true
  defp requested_source_found?(_focus, %DataSource{}), do: true
  defp requested_source_found?(_focus, _requested_source), do: false

  defp requested_binding_found?(%{source_binding_id: nil}, _requested_binding), do: true
  defp requested_binding_found?(_focus, %DataBinding{}), do: true
  defp requested_binding_found?(_focus, _requested_binding), do: false

  defp binding_source_consistent?(%{data_source_id: nil}, _binding), do: true
  defp binding_source_consistent?(_focus, nil), do: true

  defp binding_source_consistent?(focus, %DataBinding{} = binding),
    do: binding.data_source_id == focus.data_source_id

  defp context_consistent?(%{logical_source: nil, realm: nil}, _binding), do: true
  defp context_consistent?(_focus, nil), do: false

  defp context_consistent?(focus, %DataBinding{} = binding),
    do: binding_matches_context?(binding, focus)

  defp binding_matches_context?(%DataBinding{} = binding, focus) do
    (is_nil(focus.logical_source) or text(binding.logical_source) == focus.logical_source) and
      (is_nil(focus.realm) or text(binding.realm) == focus.realm)
  end

  defp source_focused?(%{state: "matched"} = focus, source),
    do: source.data_source_id == focus.matched_data_source_id

  defp source_focused?(_focus, _source), do: false

  defp binding_focused?(%{state: "matched"} = focus, row),
    do: row.binding.binding_id == focus.matched_source_binding_id

  defp binding_focused?(_focus, _row), do: false

  defp source_focus_icon(%{state: "matched"}), do: "hero-arrow-top-right-on-square"
  defp source_focus_icon(%{state: "missing"}), do: "hero-exclamation-triangle"
  defp source_focus_icon(_focus), do: "hero-information-circle"

  defp source_focus_title(%{state: "matched"}), do: "Source evidence matched"

  defp source_focus_title(%{state: "missing"}),
    do: "Source evidence no longer matches current inventory"

  defp source_focus_title(_focus), do: "Source evidence"

  defp source_focus_detail(focus) do
    [
      {"data_source_id", focus.data_source_id},
      {"source_binding_id", focus.source_binding_id},
      {"logical_source", focus.logical_source},
      {"realm", focus.realm},
      {"scope_kind", focus.scope_kind},
      {"scope_id", focus.scope_id},
      {"contact_id", focus.contact_id},
      {"selected_target", focus.selected_target},
      {"selected_id", focus.selected_id},
      {"transport_id", focus.transport_id},
      {"source_endpoint_id", focus.source_endpoint_id},
      {"ground_station_id", focus.ground_station_id},
      {"link_id", focus.link_id},
      {"source_empty_reason", focus.source_empty_reason},
      {"requested_sampling", focus.requested_sampling},
      {"supported_sampling", focus.supported_sampling},
      {"requested_products", focus.requested_products},
      {"requested_source_products", focus.requested_source_products},
      {"supported_products", focus.supported_products},
      {"requested_product_families", focus.requested_product_families},
      {"supported_product_families", focus.supported_product_families},
      {"requested_value_kinds", focus.requested_value_kinds},
      {"supported_value_kinds", focus.supported_value_kinds},
      {"requested_shapes", focus.requested_shapes},
      {"supported_shapes", focus.supported_shapes},
      {"requested_time_axes", focus.requested_time_axes},
      {"supported_time_axes", focus.supported_time_axes},
      {"selected_evidence_kind", focus.selected_evidence_kind},
      {"selected_source_evidence_mode", focus.selected_source_evidence_mode},
      {"selected_source_evidence_state", focus.selected_source_evidence_state},
      {"source_dashboard_id", focus.source_dashboard_id}
    ]
    |> Enum.reject(fn {_label, value} -> is_nil(value) end)
    |> Enum.map_join(" ", fn {label, value} -> "#{label}=#{value}" end)
  end

  attr :focus, :map, required: true
  attr :resources, :map, required: true
  attr :mission_id, :string, required: true

  defp source_focus_resource_panel(assigns) do
    assigns =
      assigns
      |> assign(
        :resource,
        source_focus_resource(assigns.focus, assigns.resources, assigns.mission_id)
      )

    ~H"""
    <div
      :if={@resource}
      id="source-focus-resource"
      class="mt-3 border-l-2 border-primary/70 pl-3"
      data-source-resource-selected-target={@resource.selected_target || ""}
      data-source-resource-selected-id={@resource.selected_id || ""}
      data-source-resource-transport-id={@resource.transport_id || ""}
      data-source-resource-source-endpoint-id={@resource.source_endpoint_id || ""}
      data-source-resource-ground-station-id={@resource.ground_station_id || ""}
      data-source-resource-link-id={@resource.link_id || ""}
    >
      <p class="text-xs font-semibold text-base-content">Operational resource context</p>
      <dl class="mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <%= for row <- @resource.rows do %>
          <dt class="hud-label" data-source-resource-row-label={row.key}>{row.label}</dt>
          <dd
            class="break-all font-mono text-base-content"
            data-source-resource-row={row.key}
            data-source-resource-row-value={row.value}
            data-source-resource-row-name={row.display_value}
            data-source-resource-row-status={row.status}
          >
            <.link
              :if={row.href}
              navigate={row.href}
              class="inline-flex items-center gap-1 text-primary hover:underline"
              data-source-resource-link={row.key}
            >
              {row.display_value} <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
            </.link>
            <span :if={!row.href}>{row.display_value}</span>
            <span class="ml-1 font-sans text-[0.65rem] uppercase tracking-normal text-base-content/50">
              {row.status_text}
            </span>
          </dd>
        <% end %>
      </dl>
    </div>
    """
  end

  defp source_focus_resource(focus, resources, mission_id) do
    rows =
      [
        source_focus_resource_row(
          focus,
          resources,
          mission_id,
          :selected_target,
          "target",
          focus.selected_target
        ),
        source_focus_resource_row(
          focus,
          resources,
          mission_id,
          :selected_id,
          "selected",
          focus.selected_id
        ),
        source_focus_resource_row(
          focus,
          resources,
          mission_id,
          :transport_id,
          "transport",
          focus.transport_id
        ),
        source_focus_resource_row(
          focus,
          resources,
          mission_id,
          :source_endpoint_id,
          "endpoint",
          focus.source_endpoint_id
        ),
        source_focus_resource_row(
          focus,
          resources,
          mission_id,
          :ground_station_id,
          "station",
          focus.ground_station_id
        ),
        source_focus_resource_row(focus, resources, mission_id, :link_id, "link", focus.link_id)
      ]
      |> Enum.reject(&is_nil/1)

    if rows == [] do
      nil
    else
      %{
        selected_target: focus.selected_target,
        selected_id: focus.selected_id,
        transport_id: focus.transport_id,
        source_endpoint_id: focus.source_endpoint_id,
        ground_station_id: focus.ground_station_id,
        link_id: focus.link_id,
        rows: rows
      }
    end
  end

  defp source_focus_resource_row(_focus, _resources, _mission_id, _key, _label, nil), do: nil

  defp source_focus_resource_row(focus, resources, mission_id, key, label, value) do
    resolution = source_focus_resource_resolution(resources, key)

    %{
      key: Atom.to_string(key),
      label: label,
      value: value,
      display_value: source_focus_resource_display_value(key, value, resolution),
      status: source_focus_resource_status(key, resolution),
      status_text: source_focus_resource_status_text(key, resolution),
      href: source_focus_resource_href(focus, resources, mission_id, key, value)
    }
  end

  defp source_focus_resource_resolution(resources, :transport_id), do: resources.transport

  defp source_focus_resource_resolution(resources, :source_endpoint_id),
    do: resources.source_endpoint

  defp source_focus_resource_resolution(resources, :ground_station_id),
    do: resources.ground_station

  defp source_focus_resource_resolution(resources, :link_id), do: resources.link_assignment
  defp source_focus_resource_resolution(_resources, _key), do: nil

  defp source_focus_resource_display_value(:selected_target, value, _resolution), do: value
  defp source_focus_resource_display_value(:selected_id, value, _resolution), do: value

  defp source_focus_resource_display_value(:ground_station_id, _value, %{label: label})
       when is_binary(label) and label != "",
       do: label

  defp source_focus_resource_display_value(_key, value, resolution) do
    case resource_label(resolution) do
      nil -> value
      label -> label
    end
  end

  defp source_focus_resource_status(key, _resolution)
       when key in [:selected_target, :selected_id],
       do: "context"

  defp source_focus_resource_status(:ground_station_id, %{status: status}),
    do: Atom.to_string(status)

  defp source_focus_resource_status(_key, nil), do: "missing"
  defp source_focus_resource_status(_key, _resolution), do: "resolved"

  defp source_focus_resource_status_text(key, _resolution)
       when key in [:selected_target, :selected_id],
       do: "context"

  defp source_focus_resource_status_text(:ground_station_id, %{status: :inferred}), do: "inferred"

  defp source_focus_resource_status_text(:ground_station_id, %{status: :unverified}),
    do: "unverified"

  defp source_focus_resource_status_text(_key, nil), do: "missing"
  defp source_focus_resource_status_text(_key, _resolution), do: "resolved"

  defp present_text?(value) do
    case resource_text(value) do
      value when is_binary(value) -> String.trim(value) != ""
      _value -> false
    end
  end

  defp resource_label(nil), do: nil

  defp resource_label(%{ground_station_id: ground_station_id} = ground_station)
       when is_binary(ground_station_id) do
    display_name = resource_value(ground_station, :display_name)

    if present_text?(display_name), do: display_name, else: ground_station_id
  end

  defp resource_label(%{transport_id: transport_id} = transport) when is_binary(transport_id) do
    display_name = resource_value(transport, :display_name)
    kind = resource_value(transport, :transport_kind)

    cond do
      present_text?(display_name) and not is_nil(kind) -> "#{display_name} / #{kind}"
      present_text?(display_name) -> display_name
      not is_nil(kind) -> "#{transport_id} / #{kind}"
      true -> transport_id
    end
  end

  defp resource_label(%{source_endpoint_id: source_endpoint_id} = source_endpoint)
       when is_binary(source_endpoint_id) do
    display_name = resource_value(source_endpoint, :display_name)
    source_ref = resource_value(source_endpoint, :source_ref)

    cond do
      present_text?(display_name) and present_text?(source_ref) ->
        "#{display_name} / #{source_ref}"

      present_text?(display_name) ->
        display_name

      present_text?(source_ref) ->
        "#{source_ref} / #{source_endpoint_id}"

      true ->
        source_endpoint_id
    end
  end

  defp resource_label(%{link_assignment_id: link_assignment_id} = link_assignment)
       when is_binary(link_assignment_id) do
    [
      resource_value(link_assignment, :spacecraft_id),
      resource_value(link_assignment, :source_endpoint_ref),
      resource_value(link_assignment, :direction)
    ]
    |> Enum.map(&resource_text/1)
    |> Enum.filter(&present_text?/1)
    |> case do
      [] -> link_assignment_id
      parts -> Enum.join(parts, " / ")
    end
  end

  defp resource_label(%{label: label}) when is_binary(label), do: label
  defp resource_label(_resource), do: nil

  defp ground_station_label(ground_station_id, nil), do: ground_station_id

  defp ground_station_label(ground_station_id, source_label),
    do: "#{ground_station_id} / #{source_label}"

  defp resource_value(resource, key) when is_map(resource),
    do: Map.get(resource, key, Map.get(resource, to_string(key)))

  defp resource_value(_resource, _key), do: nil

  defp resource_text(value) when is_atom(value), do: Atom.to_string(value)
  defp resource_text(value), do: value

  defp metadata_value(metadata, key) when is_map(metadata) and is_binary(key) do
    Map.get(metadata, key, Map.get(metadata, metadata_atom_key(key)))
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp metadata_atom_key("antenna_id"), do: :antenna_id
  defp metadata_atom_key("ground_station_id"), do: :ground_station_id
  defp metadata_atom_key("http_endpoint"), do: :http_endpoint
  defp metadata_atom_key("source_connection_profile"), do: :source_connection_profile
  defp metadata_atom_key("secret_material?"), do: :secret_material?
  defp metadata_atom_key("secret_material_fields"), do: :secret_material_fields
  defp metadata_atom_key(_key), do: nil

  defp source_focus_resource_href(_focus, _resources, mission_id, :transport_id, transport_id)
       when is_binary(mission_id) and mission_id != "" and is_binary(transport_id) and
              transport_id != "" do
    ~p"/missions/#{mission_id}/comms/transports/#{transport_id}"
  end

  defp source_focus_resource_href(
         _focus,
         _resources,
         mission_id,
         :source_endpoint_id,
         source_endpoint_id
       )
       when is_binary(mission_id) and mission_id != "" and is_binary(source_endpoint_id) and
              source_endpoint_id != "" do
    ~p"/missions/#{mission_id}/comms?#{%{source_endpoint_id: source_endpoint_id}}"
  end

  defp source_focus_resource_href(
         _focus,
         %{routing_rule: %{routing_rule_id: routing_rule_id}},
         mission_id,
         :link_id,
         _link_assignment_id
       )
       when is_binary(mission_id) and mission_id != "" and is_binary(routing_rule_id) and
              routing_rule_id != "" do
    ~p"/missions/#{mission_id}/comms/routing/#{routing_rule_id}"
  end

  defp source_focus_resource_href(
         _focus,
         %{ground_station: %{ground_station_id: ground_station_id}},
         mission_id,
         :ground_station_id,
         _ground_station_id
       )
       when is_binary(mission_id) and mission_id != "" and is_binary(ground_station_id) and
              ground_station_id != "" do
    ~p"/missions/#{mission_id}/comms/ground-stations/#{ground_station_id}"
  end

  defp source_focus_resource_href(_focus, _resources, _mission_id, _key, _value), do: nil

  attr :focus, :map, required: true
  attr :data_sources, :list, required: true
  attr :mission_id, :string, required: true

  defp source_focus_remediation_panel(assigns) do
    assigns =
      assigns
      |> assign(:remediation, source_focus_remediation(assigns.focus, assigns.data_sources))
      |> assign(:return_href, source_focus_return_href(assigns.focus, assigns.mission_id))

    ~H"""
    <div
      :if={@remediation}
      id="source-focus-remediation"
      class="mt-3 border-l-2 border-warning/60 pl-3"
      data-source-remediation-kind={@remediation.kind}
      data-source-remediation-target={@remediation.target}
      data-source-remediation-target-id={@remediation.target_id || ""}
    >
      <p class="text-xs font-semibold text-base-content">{@remediation.title}</p>
      <p class="mt-1 text-xs text-base-content/70">{@remediation.detail}</p>
      <div
        :if={@remediation.candidate_rows != []}
        id="source-focus-capability-candidates"
        class="mt-2 space-y-1 text-xs"
      >
        <p class="hud-label">candidate sources</p>
        <div
          :for={candidate <- @remediation.candidate_rows}
          class="flex flex-wrap items-center gap-x-2 gap-y-1 font-mono"
          data-source-capability-candidate={candidate.data_source_id}
          data-source-capability-compatible={text(candidate.compatible?)}
          data-source-capability-missing={candidate.missing_text}
        >
          <span class={[
            "font-semibold",
            candidate.compatible? && "text-success",
            !candidate.compatible? && "text-warning"
          ]}>
            {candidate.status_text}
          </span>
          <span class="text-base-content">{candidate.data_source_id}</span>
          <span class="text-base-content/60">{candidate.reason_text}</span>
        </div>
      </div>
      <dl
        :if={@remediation.capability_rows != []}
        id="source-focus-capability-mismatch"
        class="mt-2 grid grid-cols-[6rem_1fr_1fr] gap-x-2 gap-y-1 text-xs"
      >
        <dt class="hud-label">field</dt>
        <dd class="hud-label">requested</dd>
        <dd class="hud-label">supported</dd>
        <%= for row <- @remediation.capability_rows do %>
          <dt
            class="font-mono text-base-content/70"
            data-source-capability-mismatch-field={row.key}
          >
            {row.label}
          </dt>
          <dd
            class="break-all font-mono text-base-content"
            data-source-capability-mismatch-requested={row.key}
          >
            {row.requested}
          </dd>
          <dd
            class="break-all font-mono text-base-content/70"
            data-source-capability-mismatch-supported={row.key}
          >
            {row.supported}
          </dd>
        <% end %>
      </dl>
      <div class="mt-2 flex flex-wrap gap-2">
        <.button
          :if={@remediation.action == :register_source}
          id="source-focus-register-source"
          size={:xs}
          phx-click="open_register_source"
        >
          <.icon name="hero-plus" class="h-3.5 w-3.5" /> Register Source
        </.button>
        <a
          :if={@remediation.action == :review_binding}
          id="source-focus-review-binding"
          href={"#source-binding-#{@remediation.target_id}"}
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-arrows-right-left" class="h-3.5 w-3.5" /> Review Binding
        </a>
        <a
          :if={@remediation.action == :review_source}
          id="source-focus-review-source"
          href={"#data-source-#{@remediation.target_id}"}
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-server-stack" class="h-3.5 w-3.5" /> Review Source
        </a>
        <.link
          :if={@return_href}
          id="source-focus-dashboard-return"
          navigate={@return_href}
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
          data-source-focus-dashboard-return={@focus.source_dashboard_id}
          data-source-focus-dashboard-return-panel={source_focus_return_panel(@focus)}
          data-source-focus-dashboard-return-activity-filter={
            source_focus_return_activity_filter(@focus)
          }
          data-source-focus-dashboard-return-activity-event={
            @focus.source_return_activity_event || ""
          }
        >
          <.icon name="hero-arrow-uturn-left" class="h-3.5 w-3.5" /> Return to dashboard readiness
        </.link>
      </div>
    </div>
    """
  end

  defp source_focus_return_href(%{source_dashboard_id: dashboard_id} = focus, mission_id)
       when is_binary(dashboard_id) and dashboard_id != "" and is_binary(mission_id) and
              mission_id != "" do
    params =
      %{
        "panel" => source_focus_return_panel(focus),
        "activity_filter" => source_focus_return_activity_filter(focus),
        "activity_event" => source_focus_return_activity_event(focus),
        "refresh_readiness" => source_focus_return_refresh_readiness(focus)
      }
      |> compact_query_params()

    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{params}"
  end

  defp source_focus_return_href(_focus, _mission_id), do: nil

  defp source_focus_return_panel(%{source_return_panel: panel})
       when is_binary(panel) and panel != "",
       do: panel

  defp source_focus_return_panel(_focus), do: "versions"

  defp source_focus_return_activity_filter(%{source_return_activity_filter: activity_filter})
       when is_binary(activity_filter) and activity_filter != "",
       do: activity_filter

  defp source_focus_return_activity_filter(_focus), do: "publish_readiness"

  defp source_focus_return_activity_event(%{source_return_activity_event: activity_event})
       when is_binary(activity_event) and activity_event != "",
       do: activity_event

  defp source_focus_return_activity_event(_focus), do: nil

  defp source_focus_return_refresh_readiness(%{
         source_return_activity_filter: "publish_readiness"
       }),
       do: "source_return"

  defp source_focus_return_refresh_readiness(%{source_return_activity_filter: nil}),
    do: "source_return"

  defp source_focus_return_refresh_readiness(_focus), do: nil

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
      source_return_panel: source_focus_return_panel(focus),
      source_return_activity_filter: source_focus_return_activity_filter(focus),
      source_return_activity_event: source_focus_return_activity_event(focus),
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

  attr :focus, :map, required: true
  attr :mission_id, :string, required: true

  defp source_focus_evidence_panel(assigns) do
    assigns =
      assigns
      |> assign(:evidence, source_focus_evidence(assigns.focus))
      |> assign(:return_href, source_focus_return_href(assigns.focus, assigns.mission_id))

    ~H"""
    <div
      :if={@evidence}
      id="source-focus-evidence"
      class="mt-3 border-l-2 border-info/70 pl-3"
      data-source-evidence-kind={@evidence.kind}
      data-source-evidence-mode={@evidence.mode}
      data-source-evidence-state={@evidence.state}
      data-source-evidence-reason={@evidence.reason}
    >
      <p class="text-xs font-semibold text-base-content">{@evidence.title}</p>
      <p class="mt-1 text-xs text-base-content/70">{@evidence.detail}</p>
      <.link
        :if={@return_href}
        id="source-focus-evidence-dashboard-return"
        navigate={@return_href}
        class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        data-source-focus-dashboard-return={@focus.source_dashboard_id}
        data-source-focus-dashboard-return-panel={source_focus_return_panel(@focus)}
        data-source-focus-dashboard-return-activity-filter={
          source_focus_return_activity_filter(@focus)
        }
        data-source-focus-dashboard-return-activity-event={
          @focus.source_return_activity_event || ""
        }
      >
        <.icon name="hero-arrow-uturn-left" class="h-3.5 w-3.5" /> Return to dashboard readiness
      </.link>
    </div>
    """
  end

  defp source_focus_evidence(%{selected_evidence_kind: nil, selected_source_evidence_mode: nil}) do
    nil
  end

  defp source_focus_evidence(focus) do
    kind = focus.selected_evidence_kind || "source"
    mode = focus.selected_source_evidence_mode || "health"
    state = focus.selected_source_evidence_state || source_focus_evidence_state(focus)
    reason = focus.source_empty_reason || "source_evidence"

    %{
      kind: kind,
      mode: mode,
      state: state || "unknown",
      reason: reason,
      title: source_focus_evidence_title(mode, state),
      detail: source_focus_evidence_detail(focus, mode, state, reason)
    }
  end

  defp source_focus_evidence_state(%{source_empty_reason: "stale_data"}), do: "stale"
  defp source_focus_evidence_state(%{source_empty_reason: "retention_gap"}), do: "retention_gap"
  defp source_focus_evidence_state(%{source_empty_reason: "watermark_unknown"}), do: "unknown"
  defp source_focus_evidence_state(%{source_empty_reason: "unknown_watermark"}), do: "unknown"
  defp source_focus_evidence_state(_focus), do: nil

  defp source_focus_evidence_title("execution", _state), do: "Source execution evidence"
  defp source_focus_evidence_title(_mode, "stale"), do: "Source freshness evidence is stale"

  defp source_focus_evidence_title(_mode, "retention_gap"),
    do: "Source freshness has a retention gap"

  defp source_focus_evidence_title(_mode, "unknown"), do: "Source freshness evidence is unknown"
  defp source_focus_evidence_title(_mode, _state), do: "Source evidence"

  defp source_focus_evidence_detail(focus, mode, state, reason) do
    [
      "kind=#{focus.selected_evidence_kind || "source"}",
      "mode=#{mode || "health"}",
      "state=#{state || "unknown"}",
      "reason=#{reason}",
      source_focus_evidence_identity(focus)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp source_focus_evidence_identity(focus) do
    cond do
      is_binary(focus.source_binding_id) and is_binary(focus.data_source_id) ->
        "source=#{focus.source_binding_id}->#{focus.data_source_id}"

      is_binary(focus.source_binding_id) ->
        "source_binding_id=#{focus.source_binding_id}"

      is_binary(focus.data_source_id) ->
        "data_source_id=#{focus.data_source_id}"

      true ->
        nil
    end
  end

  defp source_focus_remediation(focus, data_sources)
  defp source_focus_remediation(%{source_empty_reason: nil}, _data_sources), do: nil

  defp source_focus_remediation(
         %{source_empty_reason: "missing_source_binding"} = focus,
         _data_sources
       ) do
    %{
      kind: "missing_source_binding",
      title: "Publish blocker: no source binding resolves",
      detail:
        "Register a compatible source if needed, then bind #{focus_text(focus.logical_source)} / #{focus_text(focus.realm)} for this mission context.",
      action: :register_source,
      target: "source_registration",
      target_id: nil,
      capability_rows: [],
      candidate_rows: []
    }
  end

  defp source_focus_remediation(
         %{source_empty_reason: "missing_data_source"} = focus,
         _data_sources
       ) do
    source_remediation(
      focus,
      "missing_data_source",
      "Publish blocker: binding points at a missing source",
      "Register the missing data source or change the highlighted binding to an active source."
    )
  end

  defp source_focus_remediation(
         %{source_empty_reason: "disabled_data_source"} = focus,
         _data_sources
       ) do
    source_review_remediation(
      focus,
      "disabled_data_source",
      "Publish blocker: source is disabled",
      "Review the highlighted source and enable it or move the binding to an active source."
    )
  end

  defp source_focus_remediation(
         %{source_empty_reason: "unsupported_source_capability"} = focus,
         data_sources
       ) do
    source_remediation(
      focus,
      "unsupported_source_capability",
      "Publish blocker: source capability mismatch",
      "Use the highlighted binding's Change action to select a source whose capabilities match the planned widget request.",
      capability_rows: source_capability_mismatch_rows(focus),
      candidate_rows: source_capability_candidate_rows(focus, data_sources)
    )
  end

  defp source_focus_remediation(
         %{source_empty_reason: "source_unavailable"} = focus,
         _data_sources
       ) do
    source_review_remediation(
      focus,
      "source_unavailable",
      "Publish blocker: source unavailable",
      "Probe or repair the highlighted source, then refresh publish readiness."
    )
  end

  defp source_focus_remediation(
         %{source_empty_reason: "source_degraded"} = focus,
         _data_sources
       ) do
    source_review_remediation(
      focus,
      "source_degraded",
      "Publish blocker: source health degraded",
      "Review the highlighted source health and restore it or change the binding to a healthier source."
    )
  end

  defp source_focus_remediation(
         %{source_empty_reason: "invalid_data_source_configuration"} = focus,
         _data_sources
       ) do
    source_review_remediation(
      focus,
      "invalid_data_source_configuration",
      "Publish blocker: source configuration is invalid",
      "Review the highlighted source adapter, credentials, dataset, and endpoint configuration."
    )
  end

  defp source_focus_remediation(
         %{source_empty_reason: "source_binding_interval_ambiguous"} = focus,
         _data_sources
       ) do
    source_remediation(
      focus,
      "source_binding_interval_ambiguous",
      "Publish blocker: binding interval is ambiguous",
      "Adjust binding activation intervals so this publish context resolves to exactly one active binding."
    )
  end

  defp source_focus_remediation(_focus, _data_sources), do: nil

  defp source_remediation(focus, kind, title, detail, opts \\ []) do
    %{
      kind: kind,
      title: title,
      detail: detail,
      action: source_remediation_action(focus),
      target: source_remediation_target(focus),
      target_id: source_remediation_target_id(focus),
      capability_rows: Keyword.get(opts, :capability_rows, []),
      candidate_rows: Keyword.get(opts, :candidate_rows, [])
    }
  end

  defp source_review_remediation(focus, kind, title, detail) do
    %{
      kind: kind,
      title: title,
      detail: detail,
      action: source_review_action(focus),
      target: source_review_target(focus),
      target_id: source_review_target_id(focus),
      capability_rows: [],
      candidate_rows: []
    }
  end

  defp source_capability_mismatch_rows(focus) do
    [
      capability_row("sampling", "sampling", focus.requested_sampling, focus.supported_sampling),
      capability_row("products", "products", focus.requested_products, focus.supported_products),
      capability_row(
        "source_products",
        "source products",
        focus.requested_source_products,
        focus.supported_products
      ),
      capability_row(
        "product_families",
        "product families",
        focus.requested_product_families,
        focus.supported_product_families
      ),
      capability_row(
        "value_kinds",
        "value kinds",
        focus.requested_value_kinds,
        focus.supported_value_kinds
      ),
      capability_row("shapes", "shapes", focus.requested_shapes, focus.supported_shapes),
      capability_row(
        "time_axes",
        "time axes",
        focus.requested_time_axes,
        focus.supported_time_axes
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp capability_row(_key, _label, nil, nil), do: nil

  defp capability_row(key, label, requested, supported) do
    %{
      key: key,
      label: label,
      requested: focus_text(requested),
      supported: focus_text(supported)
    }
  end

  defp source_capability_candidate_rows(focus, sources) do
    sources
    |> Enum.filter(&candidate_source_for_focus?(&1, focus))
    |> Enum.map(&source_capability_candidate_row(&1, focus))
    |> Enum.sort_by(fn candidate -> {not candidate.compatible?, candidate.data_source_id} end)
  end

  defp candidate_source_for_focus?(%DataSource{} = source, focus) do
    DataSource.active?(source) and source_logical_source_text(source) == focus.logical_source
  end

  defp source_capability_candidate_row(%DataSource{} = source, focus) do
    missing = source_contract_missing_requirements(source, focus)
    compatible? = missing == []

    %{
      data_source_id: source.data_source_id,
      compatible?: compatible?,
      status_text: if(compatible?, do: "compatible", else: "blocked"),
      missing_text: missing_requirements_text(missing),
      reason_text: candidate_reason_text(missing)
    }
  end

  defp candidate_reason_text([]), do: "matches requested contract"
  defp candidate_reason_text(missing), do: "missing #{missing_requirements_text(missing)}"

  defp missing_requirements_text([]), do: "none"

  defp missing_requirements_text(missing) do
    Enum.map_join(missing, ";", fn {field, values} -> "#{field}=#{Enum.join(values, ",")}" end)
  end

  defp source_remediation_action(%{matched_source_binding_id: binding_id})
       when is_binary(binding_id),
       do: :review_binding

  defp source_remediation_action(_focus), do: :register_source

  defp source_remediation_target(%{matched_source_binding_id: binding_id})
       when is_binary(binding_id),
       do: "binding"

  defp source_remediation_target(_focus), do: "source_registration"

  defp source_remediation_target_id(%{matched_source_binding_id: binding_id})
       when is_binary(binding_id),
       do: binding_id

  defp source_remediation_target_id(_focus), do: nil

  defp source_review_action(%{matched_data_source_id: data_source_id})
       when is_binary(data_source_id),
       do: :review_source

  defp source_review_action(focus), do: source_remediation_action(focus)

  defp source_review_target(%{matched_data_source_id: data_source_id})
       when is_binary(data_source_id),
       do: "source"

  defp source_review_target(focus), do: source_remediation_target(focus)

  defp source_review_target_id(%{matched_data_source_id: data_source_id})
       when is_binary(data_source_id),
       do: data_source_id

  defp source_review_target_id(focus), do: source_remediation_target_id(focus)

  defp focus_text(nil), do: "unknown"
  defp focus_text(value), do: value

  defp binding_groups(bindings, sources, credentials, health_statuses, readiness_policy) do
    sources_by_id = Map.new(sources, &{&1.data_source_id, &1})
    credentials_by_ref = Map.new(credentials, &{&1.credentials_ref, &1})

    bindings
    |> Enum.map(
      &binding_row(&1, sources_by_id, credentials_by_ref, health_statuses, readiness_policy)
    )
    |> Enum.group_by(&{&1.logical_source_text, &1.realm_text})
    |> Enum.map(fn {{logical_source, realm}, rows} ->
      rows = Enum.sort_by(rows, &{status_sort_key(&1.binding_status), &1.binding.binding_id})

      %{
        id: dom_id("#{logical_source}-#{realm}"),
        logical_source_text: logical_source,
        realm_text: realm,
        group_status: group_status(rows),
        rows: rows
      }
    end)
    |> Enum.sort_by(&{&1.logical_source_text, &1.realm_text})
  end

  defp binding_row(
         %DataBinding{} = binding,
         sources_by_id,
         credentials_by_ref,
         health_statuses,
         readiness_policy
       ) do
    source = Map.get(sources_by_id, binding.data_source_id)
    credential = source && Map.get(credentials_by_ref, source.credentials_ref)

    health =
      health_statuses
      |> matching_health_status(binding)
      |> SourceHealth.classify_status(source)

    %{
      binding: binding,
      logical_source_text: text(binding.logical_source),
      realm_text: text(binding.realm),
      binding_status: text(binding.status),
      data_source_id: binding.data_source_id,
      dataset_text: text(binding.dataset),
      priority_text: text(binding.priority),
      version_text: text(binding.binding_version),
      active_from_text: text(binding.active_from),
      active_to_text: text(binding.active_to),
      current_event_id_text: text(binding.current_event_id)
    }
    |> Map.merge(binding_source_fields(source, credential))
    |> Map.merge(binding_health_fields(health))
    |> Map.merge(source_readiness_fields(health, readiness_policy))
  end

  defp binding_source_fields(nil, _credential) do
    %{
      source_status_text: "missing",
      source_kind_text: "missing",
      source_owner_text: "missing",
      source_isolation_text: "missing",
      source_adapter_text: "missing",
      credential_ref_text: "missing"
    }
  end

  defp binding_source_fields(%DataSource{} = source, credential) do
    %{
      source_status_text: text(source.status),
      source_kind_text: text(source.kind),
      source_owner_text: text(source.owner),
      source_isolation_text: text(source.isolation_level),
      source_adapter_text: module_text(source.adapter),
      credential_ref_text: credential_text(source, credential)
    }
  end

  defp binding_health_fields(health) do
    status = Map.get(health, :status)

    %{
      health_status: text(health.source_health),
      health_reason_text: text(health.reason),
      health_observed_at_text: text(health.observed_at),
      health_event_type_text: (status && text(status.event_type)) || text(health.freshness)
    }
  end

  defp source_readiness_fields(health, readiness_policy) do
    readiness = SourceReadiness.classify(health, readiness_policy)

    %{
      source_readiness_status: readiness_status(readiness),
      source_readiness_policy_id: text(readiness.policy_id),
      source_readiness_reason_text: readiness_reason_text(readiness)
    }
  end

  defp readiness_policy_row(readiness_policy) do
    %{
      policy_id: text(readiness_policy.policy_id),
      block_source_health: joined_text(readiness_policy.block_source_health),
      block_freshness: joined_text(readiness_policy.block_freshness),
      block_connection_test: joined_text(readiness_policy.block_connection_test)
    }
  end

  defp source_rows(sources, credentials, health_statuses, watermark_statuses, readiness_policy) do
    credentials_by_ref = Map.new(credentials, &{&1.credentials_ref, &1})

    sources
    |> Enum.map(fn %DataSource{} = source ->
      credential = Map.get(credentials_by_ref, source.credentials_ref)
      health = source_health_rollup(health_statuses, source, readiness_policy)
      watermark = source_watermark_rollup(watermark_statuses, source)
      credential_status = source_credential_rollup(source, credential, health.connection_profile)
      capabilities = effective_source_capabilities(source)
      deployment_status = TSDBDeploymentStatus.from_data_source(source)

      %{
        data_source_id: source.data_source_id,
        status_text: text(source.status),
        kind_text: text(source.kind),
        owner_text: text(source.owner),
        isolation_text: text(source.isolation_level),
        adapter_text: module_text(source.adapter),
        credential_ref_text: credential_text(source, credential),
        credential_state_text: credential_status.state,
        credential_provider_text: credential_status.provider,
        credential_version_text: credential_status.version,
        credential_material_state_text: credential_status.material_state,
        credential_endpoint_text: credential_status.endpoint,
        credential_secret_fields_text: credential_status.secret_fields,
        deployment_status_text: deployment_status.status_text,
        deployment_mode_text: deployment_status.mode_text,
        deployment_backend_text: deployment_status.backend_text,
        deployment_boundary_text: deployment_status.physical_boundary_text,
        deployment_job_id_text: text(deployment_status.job_id),
        deployment_run_id_text: text(deployment_status.run_id),
        deployment_remediation_text: deployment_status.remediation,
        capability_text: capability_text(source.capabilities),
        supported_sampling_text: source_supported_sampling_text(capabilities),
        supported_products_text: source_supported_products_text(capabilities),
        supported_metric_history_products_text:
          source_supported_metric_history_products_text(capabilities),
        supported_product_families_text: source_supported_product_families_text(capabilities),
        health_status: health.status,
        health_reason_text: health.reason,
        source_readiness_status: health.readiness_status,
        source_readiness_policy_id: health.readiness_policy_id,
        source_readiness_reason_text: health.readiness_reason,
        probe_kind_text: health.probe_kind,
        probe_message_text: health.probe_message,
        probe_metadata_text: health.probe_metadata,
        probe_diagnostic_kind_text: health.probe_diagnostic_kind,
        probe_diagnostic_stage_text: health.probe_diagnostic_stage,
        probe_remediation_text: health.probe_remediation,
        connection_test_result_text: health.connection_test_result,
        connection_test_kind_text: health.connection_test_kind,
        connection_test_message_text: health.connection_test_message,
        watermark_text: watermark.complete_through,
        watermark_confidence_text: watermark.confidence
      }
    end)
    |> Enum.sort_by(& &1.data_source_id)
  end

  defp register_source_defaults do
    %{
      "data_source_id" => "",
      "logical_source" => "telemetry",
      "kind" => "byo_tsdb",
      "isolation_level" => "customer_owned",
      "credentials_ref" => "",
      "credential_provider" => "questdb",
      "endpoint_ref" => "",
      "material_env_profile" => "",
      "http_endpoint_env" => "",
      "storage" => "questdb"
    }
  end

  defp register_source_attrs(params, scope, mission) do
    with {:ok, data_source_id} <- required_text(params, "data_source_id", "Source ID"),
         {:ok, logical_source} <- parse_logical_source(Map.get(params, "logical_source")),
         {:ok, kind} <- parse_source_kind(Map.get(params, "kind")),
         {:ok, isolation_level} <- parse_isolation_level(Map.get(params, "isolation_level")),
         :ok <- validate_kind_isolation(kind, isolation_level),
         {:ok, storage} <- parse_source_storage(Map.get(params, "storage")),
         {:ok, credentials_ref} <- source_credentials_ref(params, kind) do
      {:ok,
       %{
         data_source_id: data_source_id,
         logical_source: logical_source,
         kind: kind,
         owner: source_owner(kind),
         isolation_level: isolation_level,
         organization_id: scope.organization_id,
         mission_id: mission.mission_id,
         credentials_ref: credentials_ref,
         credential_provider: optional_text(Map.get(params, "credential_provider")),
         endpoint_ref: optional_text(Map.get(params, "endpoint_ref")),
         material_env_profile: optional_text(Map.get(params, "material_env_profile")),
         http_endpoint_env: optional_text(Map.get(params, "http_endpoint_env")),
         storage: storage
       }}
    end
  end

  defp data_source_from_attrs(attrs) do
    %DataSource{
      data_source_id: attrs.data_source_id,
      owner: attrs.owner,
      kind: attrs.kind,
      adapter: source_adapter(attrs.logical_source),
      organization_id: attrs.organization_id,
      mission_id: attrs.mission_id,
      isolation_level: attrs.isolation_level,
      credentials_ref: attrs.credentials_ref,
      capabilities: source_capabilities(attrs.logical_source),
      metadata:
        %{
          storage: attrs.storage,
          registered_by: "ops_data_sources_live",
          logical_source: attrs.logical_source,
          endpoint_ref: attrs.endpoint_ref,
          material_env_profile: attrs.material_env_profile
        }
        |> compact_query_params()
    }
  end

  defp maybe_register_source_credentials(%{credentials_ref: nil}, _scope, _payload), do: :ok

  defp maybe_register_source_credentials(attrs, scope, payload) do
    case SourceCredentials.fetch_reference(attrs.credentials_ref) do
      {:ok, _reference} ->
        :ok

      {:error, :credential_reference_not_found} ->
        attrs
        |> source_credential_attrs(payload)
        |> SourceCredentials.register_reference(actor_id: current_user_id(scope))
        |> case do
          {:ok, _reference, _event} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp source_credential_attrs(attrs, payload) do
    %{
      credentials_ref: attrs.credentials_ref,
      organization_id: attrs.organization_id,
      mission_id: attrs.mission_id,
      data_source_id: attrs.data_source_id,
      owner: attrs.owner,
      kind: credential_kind(attrs.kind),
      provider: attrs.credential_provider,
      metadata:
        %{
          storage: attrs.storage,
          registered_by: "ops_data_sources_live",
          endpoint_ref: attrs.endpoint_ref,
          material_env_profile: attrs.material_env_profile,
          http_endpoint_env: attrs.http_endpoint_env
        }
        |> compact_query_params(),
      payload: payload
    }
  end

  defp required_text(params, key, label) do
    params
    |> Map.get(key)
    |> optional_text()
    |> case do
      nil -> {:error, "#{label} is required."}
      value -> {:ok, value}
    end
  end

  defp source_credentials_ref(params, :byo_tsdb) do
    params
    |> Map.get("credentials_ref")
    |> optional_text()
    |> case do
      nil -> {:error, "Credential ref is required for BYO TSDB sources."}
      value -> {:ok, value}
    end
  end

  defp source_credentials_ref(params, :managed_tsdb) do
    {:ok, optional_text(Map.get(params, "credentials_ref"))}
  end

  defp optional_text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional_text(_value), do: nil

  defp parse_logical_source("telemetry"), do: {:ok, :telemetry}
  defp parse_logical_source("limits"), do: {:ok, :limits}
  defp parse_logical_source("operational_observables"), do: {:ok, :operational_observables}
  defp parse_logical_source("events"), do: {:ok, :events}
  defp parse_logical_source(_value), do: {:error, "Choose a logical source."}

  defp parse_source_kind("managed_tsdb"), do: {:ok, :managed_tsdb}
  defp parse_source_kind("byo_tsdb"), do: {:ok, :byo_tsdb}
  defp parse_source_kind(_value), do: {:error, "Choose a source ownership model."}

  defp parse_isolation_level("shared"), do: {:ok, :shared}
  defp parse_isolation_level("org_isolated"), do: {:ok, :org_isolated}
  defp parse_isolation_level("mission_isolated"), do: {:ok, :mission_isolated}
  defp parse_isolation_level("customer_owned"), do: {:ok, :customer_owned}
  defp parse_isolation_level(_value), do: {:error, "Choose an isolation model."}

  defp validate_kind_isolation(:byo_tsdb, :customer_owned), do: :ok

  defp validate_kind_isolation(:byo_tsdb, _isolation_level),
    do: {:error, "BYO TSDB sources must use customer_owned isolation."}

  defp validate_kind_isolation(:managed_tsdb, :customer_owned),
    do: {:error, "Managed TSDB sources cannot use customer_owned isolation."}

  defp validate_kind_isolation(:managed_tsdb, _isolation_level), do: :ok

  defp parse_source_storage("questdb"), do: {:ok, :questdb}
  defp parse_source_storage("postgres_projection"), do: {:ok, :postgres_projection}
  defp parse_source_storage(_value), do: {:error, "Choose a storage backend."}

  defp source_owner(:byo_tsdb), do: :customer
  defp source_owner(:managed_tsdb), do: :cadence

  defp credential_kind(:byo_tsdb), do: :byo_tsdb_connection
  defp credential_kind(:managed_tsdb), do: :managed_tsdb_connection

  defp source_adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry
  defp source_adapter(:limits), do: Cadence.Dashboards.Sources.Limits

  defp source_adapter(:operational_observables),
    do: Cadence.Dashboards.Sources.OperationalObservables

  defp source_adapter(:events), do: Cadence.Dashboards.Sources.Events

  defp source_capabilities(:telemetry) do
    %{
      latest?: true,
      range_scan?: true,
      bounded_history?: true,
      watermarks?: true,
      native_decimation?: false
    }
  end

  defp source_capabilities(:limits) do
    %{latest_state?: true, event_history?: true, definition_intervals?: true, watermarks?: true}
  end

  defp source_capabilities(:operational_observables) do
    %{constellation_health?: true, watermarks?: false}
  end

  defp source_capabilities(:events) do
    %{
      contact_intervals?: true,
      mission_timeline?: true,
      source_health_transitions?: true,
      source_watermark_events?: true,
      source_capability_postures?: true,
      telemetry_backfill_lifecycle?: true,
      telemetry_revision_decisions?: true,
      watermarks?: false
    }
  end

  defp logical_source_options do
    [
      {"Telemetry", "telemetry"},
      {"Limits", "limits"},
      {"Operational observables", "operational_observables"},
      {"Events", "events"}
    ]
  end

  defp source_kind_options do
    [
      {"Bring your own TSDB", "byo_tsdb"},
      {"Managed TSDB", "managed_tsdb"}
    ]
  end

  defp source_isolation_options do
    [
      {"Customer owned", "customer_owned"},
      {"Mission isolated", "mission_isolated"},
      {"Organization isolated", "org_isolated"},
      {"Shared", "shared"}
    ]
  end

  defp credential_provider_options do
    [
      {"QuestDB", "questdb"},
      {"External vault", "external_vault"},
      {"Cadence managed", "cadence_managed"}
    ]
  end

  defp source_storage_options do
    [
      {"QuestDB", "questdb"},
      {"Postgres projection", "postgres_projection"}
    ]
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
      |> compatible_sources(binding)
      |> Enum.filter(&source_satisfies_focus_contract?(&1, focus))
    else
      compatible_sources(sources, binding)
    end
  end

  defp validate_changed_source(%DataBinding{data_source_id: data_source_id}, data_source_id),
    do: {:error, "Choose a different data source."}

  defp validate_changed_source(%DataBinding{}, _data_source_id), do: :ok

  defp validate_compatible_source(sources, %DataBinding{} = binding, data_source_id) do
    sources
    |> compatible_sources(binding)
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
    if source_satisfies_focus_contract?(source, focus) do
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

  defp compatible_sources(sources, %DataBinding{} = binding) do
    sources
    |> Enum.filter(&compatible_source?(&1, binding))
    |> Enum.sort_by(& &1.data_source_id)
  end

  defp compatible_source?(%DataSource{} = source, %DataBinding{} = binding) do
    DataSource.active?(source) and source_logical_source(source) == binding.logical_source
  end

  defp focused_capability_binding?(
         %{source_empty_reason: "unsupported_source_capability"} = focus,
         %DataBinding{} = binding
       ) do
    binding.binding_id in [focus.matched_source_binding_id, focus.source_binding_id]
  end

  defp focused_capability_binding?(_focus, _binding), do: false

  defp source_satisfies_focus_contract?(%DataSource{} = source, focus) do
    source_contract_missing_requirements(source, focus) == []
  end

  defp source_contract_missing_requirements(%DataSource{} = source, focus) do
    case effective_source_capabilities(source) do
      %SourceCapabilities{} = capabilities ->
        [
          missing_capability(
            :sampling,
            requested_values(focus.requested_sampling),
            capabilities.supported_sampling
          ),
          missing_capability(
            :source_products,
            requested_product_values_for_source_contract(focus),
            source_supported_products_for_focus(capabilities)
          ),
          missing_capability(
            :product_families,
            requested_values(focus.requested_product_families),
            source_supported_product_families(capabilities)
          ),
          missing_capability(
            :value_kinds,
            requested_values(focus.requested_value_kinds),
            capabilities.supported_value_types
          ),
          missing_capability(
            :shapes,
            requested_values(focus.requested_shapes),
            capabilities.supported_shapes
          ),
          missing_capability(
            :time_axes,
            requested_values(focus.requested_time_axes),
            capabilities.supported_time_axes
          )
        ]
        |> Enum.reject(&is_nil/1)

      nil ->
        [{:capabilities, ["unknown"]}]
    end
  end

  defp missing_capability(_field, [], _supported), do: nil

  defp missing_capability(field, requested, supported) do
    supported = MapSet.new(Enum.map(supported, &text/1))
    missing = Enum.reject(requested, &MapSet.member?(supported, &1))

    case missing do
      [] -> nil
      missing -> {field, missing}
    end
  end

  defp requested_values(nil), do: []

  defp requested_values(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp requested_values(value), do: [text(value)]

  defp requested_product_values_for_source_contract(focus) do
    case requested_values(focus.requested_source_products) do
      [] -> requested_values(focus.requested_products)
      values -> values
    end
  end

  defp source_supported_products_for_focus(%SourceCapabilities{} = capabilities) do
    capabilities.supported_products
    |> Kernel.++(source_supported_backing_products(capabilities))
    |> Enum.uniq()
  end

  defp source_supported_backing_products(%SourceCapabilities{} = capabilities) do
    capabilities
    |> source_backing_contracts()
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&source_backing_product_supported?(capabilities, &1))
    |> Enum.uniq()
  end

  defp source_supported_product_families(%SourceCapabilities{} = capabilities) do
    capabilities
    |> source_backing_contracts()
    |> Enum.filter(fn contract ->
      source_backing_product_supported?(capabilities, Map.get(contract, :product))
    end)
    |> Enum.map(&Map.get(&1, :product_family))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp source_backing_contracts(%SourceCapabilities{} = capabilities) do
    capabilities.metadata
    |> metadata_value(:source_backing_contracts)
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp source_backing_product_supported?(%SourceCapabilities{} = capabilities, product) do
    products = capabilities.supported_products

    product in products or
      (product in supported_source_products_for_aggregate(:operational_latest, capabilities) and
         :operational_latest in products) or
      (product in supported_source_products_for_aggregate(
         :operational_state_history,
         capabilities
       ) and
         :operational_state_history in products) or
      (product in supported_source_products_for_aggregate(
         :operational_metric_history,
         capabilities
       ) and
         :operational_metric_history in products)
  end

  defp supported_source_products_for_aggregate(
         aggregate_product,
         %SourceCapabilities{} = capabilities
       ) do
    capabilities
    |> source_backing_contracts()
    |> Enum.filter(&(Map.get(&1, :product) == aggregate_product))
    |> Enum.flat_map(fn aggregate_contract ->
      aggregate_observables = Map.get(aggregate_contract, :observables, [])
      aggregate_sampling = Map.get(aggregate_contract, :sampling)

      capabilities
      |> source_backing_contracts()
      |> Enum.filter(fn contract ->
        Map.get(contract, :sampling) == aggregate_sampling and
          Enum.all?(Map.get(contract, :observables, []), &(&1 in aggregate_observables))
      end)
      |> Enum.map(&Map.get(&1, :product))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp effective_source_capabilities(%DataSource{adapter: adapter} = source)
       when is_atom(adapter) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :capabilities, 0),
         %SourceCapabilities{} = capabilities <-
           SourceCapabilities.normalize(adapter.capabilities()) do
      SourceCapabilities.with_data_source_capabilities(capabilities, source)
    else
      _other -> nil
    end
  end

  defp effective_source_capabilities(%DataSource{}), do: nil

  defp source_logical_source(%DataSource{adapter: Cadence.Dashboards.Sources.Telemetry}),
    do: :telemetry

  defp source_logical_source(%DataSource{adapter: Cadence.Dashboards.Sources.Limits}), do: :limits

  defp source_logical_source(%DataSource{
         adapter: Cadence.Dashboards.Sources.OperationalObservables
       }),
       do: :operational_observables

  defp source_logical_source(%DataSource{adapter: Cadence.Dashboards.Sources.Events}), do: :events
  defp source_logical_source(%DataSource{}), do: nil

  defp source_logical_source_text(%DataSource{} = source), do: text(source_logical_source(source))

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

  defp matching_health_status(statuses, %DataBinding{} = binding) do
    Enum.find(statuses, fn status ->
      status.logical_source == binding.logical_source and
        status.data_source_id == binding.data_source_id and
        status.source_binding_id == binding.binding_id and
        text(status.realm) == text(binding.realm) and
        status.dataset == binding.dataset
    end)
  end

  defp source_health_rollup(statuses, %DataSource{} = source, readiness_policy) do
    statuses =
      statuses
      |> Enum.filter(&(&1.data_source_id == source.data_source_id))
      |> Enum.map(&SourceHealth.classify_status(&1, source))
      |> Enum.sort_by(&source_health_sort_key/1)

    case statuses do
      [health | _rest] ->
        readiness = SourceReadiness.classify(health, readiness_policy)

        %{
          status: text(health.source_health),
          reason: text(health.reason),
          readiness_status: readiness_status(readiness),
          readiness_policy_id: text(readiness.policy_id),
          readiness_reason: readiness_reason_text(readiness),
          probe_kind: probe_payload_text(health.status, :probe_kind),
          probe_message: probe_payload_text(health.status, :probe_message),
          probe_metadata: probe_metadata_summary(health.status),
          probe_diagnostic_kind:
            probe_metadata_payload_text(health.status, :probe_diagnostic_kind),
          probe_diagnostic_stage:
            probe_metadata_payload_text(health.status, :probe_diagnostic_stage),
          probe_remediation: probe_metadata_payload_text(health.status, :probe_remediation),
          connection_test_result: probe_payload_text(health.status, :connection_test_result),
          connection_test_kind: probe_payload_text(health.status, :connection_test_kind),
          connection_test_message: probe_payload_text(health.status, :connection_test_message),
          connection_profile: source_connection_profile(health.status)
        }

      [] ->
        health = SourceHealth.classify_status(nil, source)
        readiness = SourceReadiness.classify(health, readiness_policy)

        %{
          status: text(health.source_health),
          reason: text(health.reason),
          readiness_status: readiness_status(readiness),
          readiness_policy_id: text(readiness.policy_id),
          readiness_reason: readiness_reason_text(readiness),
          probe_kind: "none",
          probe_message: "none",
          probe_metadata: "none",
          probe_diagnostic_kind: "none",
          probe_diagnostic_stage: "none",
          probe_remediation: "none",
          connection_test_result: "none",
          connection_test_kind: "none",
          connection_test_message: "none",
          connection_profile: nil
        }
    end
  end

  defp source_health_sort_key(health) do
    {
      source_health_severity(health.source_health),
      health.last_seen_at && -DateTime.to_unix(health.last_seen_at, :microsecond)
    }
  end

  defp source_health_severity(:unavailable), do: 0
  defp source_health_severity(:degraded), do: 1
  defp source_health_severity(:unknown), do: 2
  defp source_health_severity(_source_health), do: 3

  defp readiness_status(%{blocked?: true}), do: "blocked"
  defp readiness_status(%{blocked?: false}), do: "ready"

  defp readiness_reason_text(%{reasons: []}), do: "none"

  defp readiness_reason_text(%{reasons: reasons}) do
    joined_text(reasons)
  end

  defp joined_text(values) when is_list(values) do
    Enum.map_join(values, " ", &text/1)
  end

  defp source_watermark_rollup(statuses, %DataSource{} = source) do
    statuses
    |> Enum.filter(&(&1.data_source_id == source.data_source_id))
    |> Enum.sort_by(&source_watermark_sort_key/1)
    |> case do
      [status | _rest] ->
        %{
          complete_through: text(status.complete_through || status.latest_receipt_time),
          confidence: text(status.confidence)
        }

      [] ->
        %{complete_through: "none", confidence: "unknown"}
    end
  end

  defp source_watermark_sort_key(status) do
    observed_at = status.last_seen_at || status.observed_at
    observed_at && -DateTime.to_unix(observed_at, :microsecond)
  end

  defp group_status(rows) do
    statuses = Enum.map(rows, & &1.binding_status)

    cond do
      "active" in statuses -> "active"
      "disabled" in statuses -> "disabled"
      "superseded" in statuses -> "superseded"
      true -> "unknown"
    end
  end

  defp deployment_run_row(run) do
    %{
      job_id: run.job_id,
      run_id: run.run_id,
      data_source_id: run.data_source_id,
      status_text: run.status_text,
      mode_text: run.mode_text,
      backend_text: run.backend_text,
      physical_boundary_text: run.physical_boundary_text,
      attempt_count_text: text(run.attempt_count),
      failure_summary: run.failure_summary,
      started_at_text: text(run.started_at),
      completed_at_text: text(run.completed_at),
      remediation: run.remediation
    }
  end

  defp binding_event_row(event) do
    %{
      id: "binding-event-#{event.data_binding_event_id}",
      event_type: text(event.event_type),
      title: "#{text(event.event_type)} #{event.binding_id}",
      subtitle:
        "#{text(event.current_logical_source)} / #{text(event.current_realm)} -> #{event.current_data_source_id}",
      occurred_at: text(event.occurred_at)
    }
  end

  defp source_event_row(event) do
    %{
      id: "source-event-#{event.data_source_event_id}",
      event_type: text(event.event_type),
      title: "#{text(event.event_type)} #{event.data_source_id}",
      subtitle:
        "#{module_text(event.current_adapter)} / #{text(event.current_kind)} / #{text(event.current_isolation_level)}",
      occurred_at: text(event.occurred_at)
    }
  end

  defp source_health_event_row(event) do
    %{
      id: "source-health-event-#{event.source_health_event_id}",
      event_type: text(event.event_type),
      title: "#{text(event.source_health)} #{text(event.logical_source)}",
      subtitle: "#{event.data_source_id} / #{text(event.realm)} / #{text(event.reason)}",
      occurred_at: text(event.observed_at),
      probe_kind: probe_payload_text(event, :probe_kind),
      probe_message: probe_payload_text(event, :probe_message),
      probe_metadata: probe_metadata_summary(event),
      probe_diagnostic_kind: probe_metadata_payload_text(event, :probe_diagnostic_kind),
      probe_diagnostic_stage: probe_metadata_payload_text(event, :probe_diagnostic_stage),
      probe_remediation: probe_metadata_payload_text(event, :probe_remediation),
      connection_test_result: probe_payload_text(event, :connection_test_result),
      connection_test_kind: probe_payload_text(event, :connection_test_kind),
      connection_test_message: probe_payload_text(event, :connection_test_message)
    }
  end

  defp probe_payload_text(source_health, key) do
    source_health
    |> probe_payload_value(key)
    |> text()
  end

  defp probe_payload_value(%{payload: payload}, key) when is_map(payload) do
    Map.get(payload, Atom.to_string(key), Map.get(payload, key))
  end

  defp probe_payload_value(_source_health, _key), do: nil

  defp probe_metadata_payload_text(source_health, key) do
    source_health
    |> probe_payload_value(:probe_metadata)
    |> metadata_value(key)
    |> text()
  end

  defp probe_metadata_summary(source_health) do
    case probe_payload_value(source_health, :probe_metadata) do
      metadata when is_map(metadata) and map_size(metadata) > 0 ->
        metadata
        |> Enum.map(fn {key, value} -> "#{key}=#{safe_probe_metadata_value(key, value)}" end)
        |> Enum.sort()
        |> Enum.join(" ")

      _other ->
        "none"
    end
  end

  defp safe_probe_metadata_value(key, _value)
       when key in [
              :access_key,
              :api_key,
              :api_token,
              :apikey,
              :bearer_token,
              :credential,
              :credentials,
              :password,
              :passwd,
              :secret,
              :secret_key,
              :token,
              "access_key",
              "api_key",
              "api_token",
              "apikey",
              "bearer_token",
              "credential",
              "credentials",
              "password",
              "passwd",
              "secret",
              "secret_key",
              "token"
            ],
       do: "redacted"

  defp safe_probe_metadata_value(_key, value) when is_boolean(value), do: to_string(value)
  defp safe_probe_metadata_value(_key, nil), do: "none"
  defp safe_probe_metadata_value(_key, value) when is_binary(value), do: value
  defp safe_probe_metadata_value(_key, value) when is_atom(value), do: Atom.to_string(value)
  defp safe_probe_metadata_value(_key, value) when is_number(value), do: to_string(value)
  defp safe_probe_metadata_value(_key, _value), do: "complex"

  defp source_connection_profile(source_health) do
    source_health
    |> probe_payload_value(:probe_metadata)
    |> metadata_value(:source_connection_profile)
  end

  defp source_credential_rollup(%DataSource{credentials_ref: nil}, _credential, _profile) do
    %{
      state: "none",
      provider: "none",
      version: "none",
      material_state: "none",
      endpoint: "none",
      secret_fields: "none"
    }
  end

  defp source_credential_rollup(%DataSource{} = source, nil, profile) do
    %{
      state: "unresolved",
      provider: "unknown",
      version: "unknown",
      material_state: credential_material_state(source, profile),
      endpoint: credential_endpoint(source, nil, profile),
      secret_fields: credential_secret_fields(profile)
    }
  end

  defp source_credential_rollup(%DataSource{} = source, credential, profile) do
    %{
      state: text(credential.status),
      provider: text(credential.provider),
      version: text(credential.credential_version),
      material_state: credential_material_state(source, profile),
      endpoint: credential_endpoint(source, credential, profile),
      secret_fields: credential_secret_fields(profile)
    }
  end

  defp credential_material_state(%DataSource{}, profile) when is_map(profile) do
    if truthy?(metadata_value(profile, :secret_material?)), do: "resolved", else: "descriptor"
  end

  defp credential_material_state(%DataSource{}, _profile), do: "unprobed"

  defp credential_endpoint(%DataSource{} = source, credential, profile) do
    metadata_value(profile, :http_endpoint) ||
      metadata_value(source.metadata, :http_endpoint) ||
      (credential && metadata_value(credential.metadata, :http_endpoint)) ||
      "none"
  end

  defp credential_secret_fields(profile) when is_map(profile) do
    profile
    |> metadata_value(:secret_material_fields)
    |> List.wrap()
    |> Enum.map(&text/1)
    |> Enum.reject(&(&1 in ["", "none"]))
    |> case do
      [] -> "none"
      fields -> Enum.join(fields, " ")
    end
  end

  defp credential_secret_fields(_profile), do: "none"

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false

  defp credential_text(%DataSource{credentials_ref: nil}, _credential), do: "none"
  defp credential_text(%DataSource{credentials_ref: ref}, nil), do: "#{ref} (unresolved)"

  defp credential_text(%DataSource{credentials_ref: ref}, credential) do
    "#{ref} / #{text(credential.status)} v#{credential.credential_version}"
  end

  defp capability_text(capabilities) when is_map(capabilities) do
    enabled =
      capabilities
      |> Enum.filter(fn {_key, value} -> value == true end)
      |> Enum.map(fn {key, _value} -> text(key) end)
      |> Enum.sort()

    case enabled do
      [] -> "none"
      values -> Enum.join(values, " ")
    end
  end

  defp capability_text(_capabilities), do: "none"

  defp source_supported_sampling_text(%SourceCapabilities{} = capabilities),
    do: capability_values_text(capabilities.supported_sampling)

  defp source_supported_sampling_text(_capabilities), do: "unknown"

  defp source_supported_products_text(%SourceCapabilities{} = capabilities),
    do: capability_values_text(capabilities.supported_products)

  defp source_supported_products_text(_capabilities), do: "unknown"

  defp source_supported_metric_history_products_text(%SourceCapabilities{} = capabilities) do
    capabilities
    |> source_backing_contracts()
    |> Enum.filter(&(Map.get(&1, :sampling) == :raw_series))
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&source_backing_product_supported?(capabilities, &1))
    |> Enum.uniq()
    |> capability_values_text()
  end

  defp source_supported_metric_history_products_text(_capabilities), do: "unknown"

  defp source_supported_product_families_text(%SourceCapabilities{} = capabilities),
    do: capability_values_text(source_supported_product_families(capabilities))

  defp source_supported_product_families_text(_capabilities), do: "unknown"

  defp capability_values_text([]), do: "none"

  defp capability_values_text(values) when is_list(values) do
    values
    |> Enum.map(&text/1)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp pill_status(status) when status in ["active", "healthy", "recovered", "ready"], do: :ready

  defp pill_status(status) when status in ["degraded", "disabled", "unknown"], do: :attention

  defp pill_status(status) when status in ["unavailable", "superseded", "missing", "blocked"],
    do: :blocked

  defp pill_status(_status), do: :info

  defp status_sort_key("active"), do: 0
  defp status_sort_key("healthy"), do: 0
  defp status_sort_key("degraded"), do: 1
  defp status_sort_key("unknown"), do: 2
  defp status_sort_key("disabled"), do: 3
  defp status_sort_key("superseded"), do: 4
  defp status_sort_key(_status), do: 5

  defp module_text(nil), do: "none"

  defp module_text(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp module_text(value), do: text(value)

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

  defp dom_id(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
  end

  defp clear_change_binding(socket) do
    socket
    |> assign(:change_binding, nil)
    |> assign(:change_binding_form, to_form(%{}, as: :binding))
    |> assign(:change_binding_error, nil)
  end

  defp clear_register_source(socket) do
    socket
    |> assign(:register_source?, false)
    |> assign(:register_source_form, to_form(register_source_defaults(), as: :source))
    |> assign(:register_source_error, nil)
  end

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
