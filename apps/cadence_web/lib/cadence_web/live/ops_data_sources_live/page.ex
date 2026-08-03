defmodule CadenceWeb.OpsDataSourcesLive.Page do
  @moduledoc false

  use CadenceWeb, :html

  alias Cadence.Dashboards.DataBinding

  alias CadenceWeb.OpsDataSourcesLive.{
    SourceFocus,
    SourceFocusComponents,
    SourceRegistration
  }

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
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
            <h1 class="text-lg font-semibold text-base-content">
              {if @source_admin?, do: "Data Source Settings", else: "Data Sources"}
            </h1>
            <p class="mt-1 font-mono text-xs text-base-content/60">
              {@current_mission.mission_id}
            </p>
          </div>
          <div class="flex flex-col items-stretch gap-3 md:items-end">
            <.link
              :if={source_admin_eligible?(@current_scope)}
              id="register-source-button"
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/data-sources/registration/new"}
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus" class="h-4 w-4" /> Register Source
            </.link>
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
          <.icon name={SourceFocus.icon(@source_focus)} class="mt-0.5 h-4 w-4 shrink-0" />
          <div class="min-w-0">
            <p class="font-semibold">{SourceFocus.title(@source_focus)}</p>
            <p class="mt-1 break-all font-mono text-xs text-base-content/60">
              {SourceFocus.detail(@source_focus)}
            </p>
            <SourceFocusComponents.remediation_panel
              focus={@source_focus}
              data_sources={@data_sources}
              mission_id={@current_mission.mission_id}
            />
            <SourceFocusComponents.resource_panel
              focus={@source_focus}
              resources={@source_focus_resources}
              mission_id={@current_mission.mission_id}
            />
            <SourceFocusComponents.evidence_panel
              focus={@source_focus}
              mission_id={@current_mission.mission_id}
            />
          </div>
        </div>

        <section
          :if={@register_source? and @source_admin?}
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
              options={SourceRegistration.logical_source_options()}
              required
            />
            <.input
              field={@register_source_form[:kind]}
              type="select"
              label="Ownership"
              options={SourceRegistration.source_kind_options()}
              required
            />
            <.input
              field={@register_source_form[:isolation_level]}
              type="select"
              label="Isolation"
              options={SourceRegistration.source_isolation_options()}
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
              options={SourceRegistration.credential_provider_options()}
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
              options={SourceRegistration.source_storage_options()}
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
                    SourceFocus.binding_focused?(@source_focus, row) &&
                      "ring-1 ring-inset ring-primary/40 bg-primary/5"
                  ]}
                  data-source-focus={SourceFocus.binding_focused?(@source_focus, row)}
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
                        :if={@source_admin?}
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
                    :if={@source_admin? and change_binding_open?(@change_binding, row.binding.binding_id)}
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
                    SourceFocus.source_focused?(@source_focus, source) &&
                      "ring-1 ring-inset ring-primary/40 bg-primary/5"
                  ]}
                  data-source-focus={SourceFocus.source_focused?(@source_focus, source)}
                  data-data-source-row={source.data_source_id}
                  data-source-status={source.status_text}
                  data-source-health={source.health_status}
                  data-source-readiness={source.source_readiness_status}
                  data-source-readiness-reasons={source.source_readiness_reason_text}
                  data-source-readiness-policy={source.source_readiness_policy_id}
                  data-source-probe-kind={source.probe_kind_text}
                  data-source-probe-policy={source.probe_policy_text}
                  data-source-probe-stale-after-ms={source.probe_stale_after_ms_text}
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
                  data-source-deployment-lifecycle-operation={
                    source.deployment_lifecycle_operation_text
                  }
                  data-source-deployment-lifecycle-status={source.deployment_lifecycle_status_text}
                  data-source-deployment-lifecycle-observed-at={
                    source.deployment_lifecycle_observed_at_text
                  }
                  data-source-supported-sampling={source.supported_sampling_text}
                  data-source-supported-products={source.supported_products_text}
                  data-source-supported-metric-history-products={
                    source.supported_metric_history_products_text
                  }
                  data-source-supported-product-families={source.supported_product_families_text}
                >
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <.link
                        navigate={~p"/missions/#{@current_mission.mission_id}/ops/data-sources/#{source.data_source_id}"}
                        class="truncate font-mono text-xs font-semibold text-primary hover:underline"
                      >
                        {source.data_source_id}
                      </.link>
                      <p class="mt-1 text-xs text-base-content/60">
                        {source.kind_text} · {source.owner_text} · {source.isolation_text}
                      </p>
                    </div>
                    <div class="flex shrink-0 flex-col items-end gap-2">
                      <div class="flex flex-wrap justify-end gap-1">
                        <.status_pill status={source.status_text} />
                        <.status_pill status={source.health_status} />
                      </div>
                      <.link
                        :if={source_admin_eligible?(@current_scope) and not @source_admin?}
                        id={"source-settings-#{source.data_source_id}"}
                        navigate={~p"/missions/#{@current_mission.mission_id}/ops/data-sources/#{source.data_source_id}/settings"}
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-cog-6-tooth" class="h-3.5 w-3.5" /> Settings
                      </.link>
                      <.button
                        :if={@source_admin? and source.credential_action?}
                        id={"rotate-credential-#{source.data_source_id}"}
                        variant={:ghost}
                        size={:xs}
                        phx-click="rotate_source_credential"
                        phx-value-data-source-id={source.data_source_id}
                        phx-value-credentials-ref={source.credentials_ref}
                        data-confirm="Rotate this credential reference?"
                      >
                        <.icon name="hero-key" class="h-3.5 w-3.5" /> Rotate Credential
                      </.button>
                      <.button
                        :if={@source_admin? and source.backend_reconcile_action?}
                        id={"reconcile-backend-#{source.data_source_id}"}
                        variant={:ghost}
                        size={:xs}
                        phx-click="reconcile_tsdb_backend"
                        phx-value-data-source-id={source.data_source_id}
                      >
                        <.icon name="hero-arrow-path" class="h-3.5 w-3.5" /> Reconcile Backend
                      </.button>
                      <.button
                        :if={@source_admin? and source.backend_provision_action?}
                        id={"provision-backend-#{source.data_source_id}"}
                        variant={:secondary}
                        size={:xs}
                        phx-click="provision_tsdb_backend"
                        phx-value-data-source-id={source.data_source_id}
                      >
                        <.icon name="hero-server-stack" class="h-3.5 w-3.5" /> Provision Backend
                      </.button>
                      <.button
                        :if={@source_admin? and source.backend_deprovision_action?}
                        id={"deprovision-backend-#{source.data_source_id}"}
                        variant={:danger}
                        size={:xs}
                        phx-click="deprovision_tsdb_backend"
                        phx-value-data-source-id={source.data_source_id}
                        data-confirm="Request deprovisioning for this dedicated TSDB backend?"
                      >
                        <.icon name="hero-trash" class="h-3.5 w-3.5" /> Deprovision Backend
                      </.button>
                      <.button
                        :if={@source_admin? and source.status_text == "active"}
                        id={"probe-source-#{source.data_source_id}"}
                        variant={:ghost}
                        size={:xs}
                        phx-click="probe_source"
                        phx-value-data-source-id={source.data_source_id}
                      >
                        <.icon name="hero-arrow-path" class="h-3.5 w-3.5" /> Probe
                      </.button>
                      <.button
                        :if={@source_admin? and source.status_text == "active"}
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
                        :if={@source_admin? and source.enable_action?}
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
                    <.kv label="probe policy" value={source.probe_policy_text} />
                    <.kv label="probe stale" value={source.probe_stale_after_ms_text} />
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
                    <.kv label="backend op" value={source.deployment_lifecycle_operation_text} />
                    <.kv label="backend state" value={source.deployment_lifecycle_status_text} />
                    <.kv label="backend seen" value={source.deployment_lifecycle_observed_at_text} />
                    <.kv label="capability" value={source.capability_text} />
                    <.kv label="sampling" value={source.supported_sampling_text} />
                    <.kv label="products" value={source.supported_products_text} />
                    <.kv label="history" value={source.supported_metric_history_products_text} />
                    <.kv label="families" value={source.supported_product_families_text} />
                  </dl>
                </div>
              </div>
            </.card>

            <.card heading="Deployment Runs" subtitle="TSDB backend lifecycle jobs" padding={:none}>
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
                        :if={@source_admin? and run.status_text == "failed"}
                        id={"retry-deployment-run-#{run.run_id}"}
                        variant={:secondary}
                        size={:xs}
                        phx-click="retry_deployment_run"
                        phx-value-job-id={run.job_id}
                      >
                        <.icon name="hero-arrow-path" class="h-3.5 w-3.5" /> Retry
                      </.button>
                      <.button
                        :if={@source_admin? and run.status_text == "provisioning"}
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
    </div>
    </Layouts.app>
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

  defp pill_status(status) when status in ["active", "healthy", "recovered", "ready"], do: :ready

  defp pill_status(status) when status in ["degraded", "disabled", "unknown"], do: :attention

  defp pill_status(status) when status in ["unavailable", "superseded", "missing", "blocked"],
    do: :blocked

  defp pill_status(_status), do: :info

  defp source_admin_eligible?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end
end
