defmodule Cadence.Dashboards.DataSources do
  @moduledoc """
  Persistence boundary for dashboard data sources and source bindings.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Dashboards.{
    DataBinding,
    DataBindingEvent,
    DataBindingInterval,
    DataSource,
    DataSourceEvent,
    DataSourceRegistry,
    ResolvedSourceCredential,
    RuntimeCacheKey,
    RuntimeInvalidation,
    SourceCapabilities,
    SourceCredentialMaterial,
    SourceCredentials,
    SourceHealth,
    SourceHealthEvent,
    SourceProbe
  }

  alias Cadence.Dashboards.Sources.{Events, Limits, OperationalObservables, Telemetry}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Persistence.JsonDocument

  alias Cadence.Dashboards.DataSources.{
    DataBindingEventRow,
    DataBindingRow,
    DataSourceEventRow,
    DataSourceRow
  }

  alias Cadence.Repo

  @default_data_source_id "managed_questdb_primary"
  @default_limits_data_source_id "managed_limits_projection"
  @default_operational_observables_data_source_id "managed_operational_observables"
  @default_events_data_source_id "managed_events_projection"
  @default_binding_id "default_flight_telemetry"
  @default_limits_binding_id "default_flight_limits"
  @default_operational_observables_binding_id "default_flight_operational_observables"
  @default_events_binding_id "default_flight_events"

  @spec default_managed_data_source() :: DataSource.t()
  def default_managed_data_source do
    %DataSource{
      data_source_id: @default_data_source_id,
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Telemetry,
      isolation_level: :shared,
      capabilities: %{
        range_scan?: true,
        bounded_history?: true,
        latest?: true,
        watermarks?: true,
        native_decimation?: false
      },
      metadata: %{storage: :questdb, bootstrap_default?: true}
    }
  end

  @spec default_limits_data_source() :: DataSource.t()
  def default_limits_data_source do
    %DataSource{
      data_source_id: @default_limits_data_source_id,
      owner: :cadence,
      kind: :projection,
      adapter: Limits,
      isolation_level: :shared,
      capabilities: %{
        latest_state?: true,
        event_history?: true,
        definition_intervals?: true,
        watermarks?: true
      },
      metadata: %{storage: :postgres_projection, bootstrap_default?: true}
    }
  end

  @spec default_operational_observables_data_source() :: DataSource.t()
  def default_operational_observables_data_source do
    %DataSource{
      data_source_id: @default_operational_observables_data_source_id,
      owner: :cadence,
      kind: :projection,
      adapter: OperationalObservables,
      isolation_level: :shared,
      capabilities: %{
        constellation_health?: true,
        watermarks?: false
      },
      metadata: %{storage: :postgres_projection, bootstrap_default?: true}
    }
  end

  @spec default_events_data_source() :: DataSource.t()
  def default_events_data_source do
    %DataSource{
      data_source_id: @default_events_data_source_id,
      owner: :cadence,
      kind: :projection,
      adapter: Events,
      isolation_level: :shared,
      capabilities: %{
        contact_intervals?: true,
        mission_timeline?: true,
        source_health_transitions?: true,
        source_watermark_events?: true,
        source_capability_postures?: true,
        telemetry_backfill_lifecycle?: true,
        telemetry_revision_decisions?: true,
        watermarks?: false
      },
      metadata: %{storage: :postgres_projection, bootstrap_default?: true}
    }
  end

  @spec default_flight_telemetry_binding() :: DataBinding.t()
  def default_flight_telemetry_binding do
    %DataBinding{
      binding_id: @default_binding_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: @default_data_source_id,
      dataset: "flight",
      priority: 0,
      metadata: %{bootstrap_default?: true}
    }
  end

  @spec default_flight_limits_binding() :: DataBinding.t()
  def default_flight_limits_binding do
    %DataBinding{
      binding_id: @default_limits_binding_id,
      realm: :flight,
      logical_source: :limits,
      data_source_id: @default_limits_data_source_id,
      dataset: "telemetry_latest_limit_states",
      priority: 0,
      metadata: %{bootstrap_default?: true}
    }
  end

  @spec default_flight_operational_observables_binding() :: DataBinding.t()
  def default_flight_operational_observables_binding do
    %DataBinding{
      binding_id: @default_operational_observables_binding_id,
      realm: :flight,
      logical_source: :operational_observables,
      data_source_id: @default_operational_observables_data_source_id,
      dataset: "operational_observables",
      priority: 0,
      metadata: %{bootstrap_default?: true}
    }
  end

  @spec default_flight_events_binding() :: DataBinding.t()
  def default_flight_events_binding do
    %DataBinding{
      binding_id: @default_events_binding_id,
      realm: :flight,
      logical_source: :events,
      data_source_id: @default_events_data_source_id,
      dataset: "mission_events",
      priority: 0,
      metadata: %{bootstrap_default?: true}
    }
  end

  @spec ensure_default_managed_sources!() :: %{
          data_source: DataSource.t(),
          data_binding: DataBinding.t(),
          data_sources: [DataSource.t()],
          data_bindings: [DataBinding.t()]
        }
  def ensure_default_managed_sources! do
    with {:ok, data_source} <- persist_data_source(default_managed_data_source()),
         {:ok, limits_data_source} <- persist_data_source(default_limits_data_source()),
         {:ok, operational_observables_data_source} <-
           persist_data_source(default_operational_observables_data_source()),
         {:ok, events_data_source} <- persist_data_source(default_events_data_source()),
         {:ok, data_binding} <- persist_data_binding(default_flight_telemetry_binding()),
         {:ok, limits_data_binding} <- persist_data_binding(default_flight_limits_binding()),
         {:ok, operational_observables_binding} <-
           persist_data_binding(default_flight_operational_observables_binding()),
         {:ok, events_binding} <- persist_data_binding(default_flight_events_binding()) do
      %{
        data_source: data_source,
        data_binding: data_binding,
        data_sources: [
          data_source,
          limits_data_source,
          operational_observables_data_source,
          events_data_source
        ],
        data_bindings: [
          data_binding,
          limits_data_binding,
          operational_observables_binding,
          events_binding
        ]
      }
    else
      {:error, reason} ->
        raise "failed to bootstrap dashboard data sources: #{inspect(reason)}"
    end
  end

  @spec persist_data_source(DataSource.t(), keyword()) :: {:ok, DataSource.t()} | {:error, term()}
  def persist_data_source(%DataSource{} = data_source, opts \\ []) when is_list(opts) do
    with :ok <- validate_data_source_credentials(data_source),
         {:ok, {data_source, event}} <-
           Repo.transaction(fn -> persist_data_source_projection!(data_source, opts) end) do
      if event, do: maybe_invalidate_data_source(data_source)
      {:ok, data_source}
    else
      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec persist_data_binding(DataBinding.t(), keyword()) ::
          {:ok, DataBinding.t()} | {:error, term()}
  def persist_data_binding(%DataBinding{} = data_binding, opts \\ []) when is_list(opts) do
    Repo.transaction(fn ->
      data_binding
      |> persist_data_binding_projection(opts)
      |> case do
        {:ok, binding, event} -> {binding, event}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {data_binding, event}} ->
        if event, do: maybe_invalidate_data_binding(data_binding, event)
        {:ok, data_binding}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_data_binding(binary()) :: {:ok, DataBinding.t()} | {:error, :data_binding_not_found}
  def fetch_data_binding(binding_id) when is_binary(binding_id) do
    case Repo.get(DataBindingRow, binding_id) do
      nil -> {:error, :data_binding_not_found}
      row -> {:ok, DataBindingRow.to_domain(row)}
    end
  end

  @spec fetch_data_source(binary()) :: {:ok, DataSource.t()} | {:error, :data_source_not_found}
  def fetch_data_source(data_source_id) when is_binary(data_source_id) do
    case Repo.get(DataSourceRow, data_source_id) do
      nil -> {:error, :data_source_not_found}
      row -> {:ok, DataSourceRow.to_domain(row)}
    end
  end

  @spec disable_data_source(binary(), map(), keyword()) ::
          {:ok, DataSource.t()} | {:error, term()}
  def disable_data_source(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    mutate_data_source(data_source_id, attrs, opts, fn %DataSource{} = current, occurred_at ->
      %DataSource{current | status: :disabled, disabled_at: occurred_at}
    end)
  end

  @spec enable_data_source(binary(), map(), keyword()) :: {:ok, DataSource.t()} | {:error, term()}
  def enable_data_source(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    mutate_data_source(data_source_id, attrs, opts, fn %DataSource{} = current, _occurred_at ->
      %DataSource{current | status: :active, disabled_at: nil}
    end)
  end

  @spec reconcile_tsdb_backend(binary(), map(), keyword()) ::
          {:ok, DataSource.t()} | {:error, term()}
  def reconcile_tsdb_backend(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_data_source(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "reconcile",
          "reconciled",
          "reconciled_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "reconcile_tsdb_backend",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> persist_data_source(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  @spec request_tsdb_backend_deprovisioning(binary(), map(), keyword()) ::
          {:ok, DataSource.t()} | {:error, term()}
  def request_tsdb_backend_deprovisioning(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_data_source(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "deprovision",
          "deprovision_requested",
          "deprovision_requested_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "request_tsdb_backend_deprovisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> then(fn %DataSource{} = source ->
        %DataSource{source | status: :disabled, disabled_at: occurred_at}
      end)
      |> persist_data_source(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  @spec request_tsdb_backend_provisioning(binary(), map(), keyword()) ::
          {:ok, DataSource.t()} | {:error, term()}
  def request_tsdb_backend_provisioning(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_data_source(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "provision",
          "provision_requested",
          "provision_requested_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "request_tsdb_backend_provisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> persist_data_source(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  @spec complete_tsdb_backend_provisioning(binary(), map(), keyword()) ::
          {:ok, DataSource.t()} | {:error, term()}
  def complete_tsdb_backend_provisioning(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_data_source(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "provision",
          "provisioned",
          "provisioned_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "complete_tsdb_backend_provisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> then(fn %DataSource{} = source ->
        %DataSource{source | status: :active, disabled_at: nil}
      end)
      |> persist_data_source(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  @spec complete_tsdb_backend_deprovisioning(binary(), map(), keyword()) ::
          {:ok, DataSource.t()} | {:error, term()}
  def complete_tsdb_backend_deprovisioning(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_data_source(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "deprovision",
          "deprovisioned",
          "deprovisioned_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "complete_tsdb_backend_deprovisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> then(fn %DataSource{} = source ->
        %DataSource{source | status: :disabled, disabled_at: source.disabled_at || occurred_at}
      end)
      |> persist_data_source(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  @spec probe_data_source(binary(), map(), keyword()) ::
          SourceHealth.record_result() | {:error, term()}
  def probe_data_source(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    with {:ok, %DataSource{} = data_source} <- fetch_data_source(data_source_id),
         {:ok, mission_id} <- probe_mission_id(data_source, attrs) do
      probe = probe_data_source_health(data_source, opts)

      data_source
      |> source_probe_attrs(mission_id, probe, attrs, opts)
      |> annotate_capability_probe_drift()
      |> record_probe_health_and_maybe_materialize_capabilities(data_source, opts)
    end
  end

  @spec disable_data_binding(binary(), map(), keyword()) ::
          {:ok, DataBinding.t()} | {:error, term()}
  def disable_data_binding(binding_id, attrs \\ %{}, opts \\ [])
      when is_binary(binding_id) and is_map(attrs) and is_list(opts) do
    mutate_data_binding(binding_id, attrs, opts, fn current, occurred_at ->
      %DataBinding{} = current

      %DataBinding{
        current
        | status: :disabled,
          disabled_at: occurred_at,
          active_to: get_attr(attrs, :active_to, current.active_to)
      }
    end)
  end

  @spec enable_data_binding(binary(), map(), keyword()) ::
          {:ok, DataBinding.t()} | {:error, term()}
  def enable_data_binding(binding_id, attrs \\ %{}, opts \\ [])
      when is_binary(binding_id) and is_map(attrs) and is_list(opts) do
    mutate_data_binding(binding_id, attrs, opts, fn current, _occurred_at ->
      %DataBinding{} = current

      %DataBinding{
        current
        | status: :active,
          disabled_at: nil,
          superseded_at: nil,
          active_from: get_attr(attrs, :active_from, current.active_from),
          active_to: get_attr(attrs, :active_to, current.active_to)
      }
    end)
  end

  @spec supersede_data_binding(binary(), map(), keyword()) ::
          {:ok, DataBinding.t()} | {:error, term()}
  def supersede_data_binding(binding_id, attrs \\ %{}, opts \\ [])
      when is_binary(binding_id) and is_map(attrs) and is_list(opts) do
    mutate_data_binding(binding_id, attrs, opts, fn current, occurred_at ->
      %DataBinding{} = current

      %DataBinding{
        current
        | status: :superseded,
          active_to: get_attr(attrs, :active_to, current.active_to || occurred_at),
          superseded_at: occurred_at
      }
    end)
  end

  @spec list_data_binding_events(binary(), keyword()) :: [DataBindingEvent.t()]
  def list_data_binding_events(binding_id, opts \\ [])
      when is_binary(binding_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    DataBindingEventRow
    |> where([row], row.binding_id == ^binding_id)
    |> order_by([row], desc: row.occurred_at, desc: row.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&DataBindingEventRow.to_domain/1)
  end

  @spec list_data_source_events(binary() | nil, binary() | nil, keyword()) :: [
          DataSourceEvent.t()
        ]
  def list_data_source_events(organization_id \\ nil, mission_id \\ nil, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    DataSourceEventRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter_data_source_id(Keyword.get(opts, :data_source_id))
    |> order_by([row], desc: row.occurred_at, desc: row.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&DataSourceEventRow.to_domain/1)
  end

  @spec list_data_binding_intervals(binary() | nil, binary() | nil, keyword()) :: [
          DataBindingInterval.t()
        ]
  def list_data_binding_intervals(organization_id \\ nil, mission_id \\ nil, opts \\ []) do
    DataBindingEventRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> order_by([row], asc: row.binding_id, asc: row.occurred_at, asc: row.inserted_at)
    |> Repo.all()
    |> Enum.map(&DataBindingEventRow.to_domain/1)
    |> events_to_intervals()
    |> filter_intervals(opts)
  end

  @spec list_data_sources(binary() | nil, binary() | nil) :: [DataSource.t()]
  def list_data_sources(organization_id \\ nil, mission_id \\ nil) do
    DataSourceRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> order_by([row], asc: row.data_source_id)
    |> Repo.all()
    |> Enum.map(&DataSourceRow.to_domain/1)
  end

  @spec list_data_bindings(binary() | nil, binary() | nil) :: [DataBinding.t()]
  def list_data_bindings(organization_id \\ nil, mission_id \\ nil) do
    DataBindingRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> order_by([row], asc: row.priority, asc: row.binding_id)
    |> Repo.all()
    |> Enum.map(&DataBindingRow.to_domain/1)
  end

  @spec list_data_realms(binary() | nil, binary() | nil, keyword()) :: [binary()]
  def list_data_realms(organization_id \\ nil, mission_id \\ nil, opts \\ []) do
    logical_source = Keyword.get(opts, :logical_source, :telemetry)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    realms =
      organization_id
      |> list_data_bindings(mission_id)
      |> Enum.filter(&(&1.logical_source == logical_source and active_binding?(&1, now)))
      |> Enum.map(&normalize_realm/1)
      |> Enum.uniq()
      |> Enum.sort_by(&realm_sort_key/1)

    case realms do
      [] -> ["flight"]
      realms -> realms
    end
  end

  @spec resolve_binding(Cadence.Dashboards.PlannedSourceRequest.t(), keyword()) ::
          {:ok, Cadence.Dashboards.ResolvedSourceBinding.t()}
          | {:error, Cadence.Dashboards.ResolveWarning.t()}
  def resolve_binding(request, opts \\ []) do
    registry_opts =
      [
        data_sources: list_data_sources(request.organization_id, request.mission_id),
        data_bindings: list_data_bindings(request.organization_id, request.mission_id),
        source_health_statuses:
          SourceHealth.list_source_health_statuses(request.organization_id, request.mission_id,
            logical_source: request.logical_source
          )
      ]
      |> Keyword.merge(opts)

    DataSourceRegistry.resolve(request, registry_opts)
  end

  defp maybe_invalidate_data_source(%DataSource{} = data_source) do
    with {:ok, runtime_cache} <- dashboard_runtime_invalidation_cache() do
      RuntimeInvalidation.data_source_binding_changed(
        %{
          organization_id: data_source.organization_id,
          mission_id: data_source.mission_id,
          logical_source: logical_source_for_adapter(data_source.adapter),
          data_source_id: data_source.data_source_id
        },
        runtime_cache: runtime_cache
      )
    end

    :ok
  end

  defp validate_data_source_credentials(%DataSource{credentials_ref: nil}), do: :ok

  defp validate_data_source_credentials(%DataSource{} = data_source) do
    case SourceCredentials.resolve(data_source.credentials_ref,
           organization_id: data_source.organization_id,
           mission_id: data_source.mission_id,
           data_source_id: data_source.data_source_id
         ) do
      {:ok, _resolved_credential} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_invalidate_data_binding(%DataBinding{} = data_binding, event) do
    with {:ok, runtime_cache} <- dashboard_runtime_invalidation_cache() do
      RuntimeInvalidation.data_source_binding_changed(
        %{
          organization_id: data_binding.organization_id,
          mission_id: data_binding.mission_id,
          logical_source: data_binding.logical_source,
          source_binding_id: data_binding.binding_id,
          data_source_id: data_binding.data_source_id,
          realm: data_binding.realm,
          dataset: data_binding.dataset,
          reason: event && event.event_type,
          evidence_ref:
            event && %{kind: "dashboard_data_binding_event", id: event.data_binding_event_id}
        },
        runtime_cache: runtime_cache
      )
    end

    :ok
  end

  defp dashboard_runtime_invalidation_cache do
    config = Application.get_env(:cadence, :dashboard_runtime_invalidation, [])

    if Keyword.get(config, :enabled?, true) do
      {:ok, Keyword.get(config, :runtime_cache, Cadence.Dashboards.RuntimeCache)}
    else
      :disabled
    end
  end

  defp persist_data_source_projection(%DataSource{} = data_source, opts) do
    previous_row = Repo.get(DataSourceRow, data_source.data_source_id)
    previous = previous_row && DataSourceRow.to_domain(previous_row)

    if same_data_source_projection?(previous, data_source) do
      {:ok, previous, nil}
    else
      event = data_source_event(data_source, previous, opts)
      data_source = %{data_source | current_event_id: event.data_source_event_id}

      with {:ok, row} <- persist_data_source_row(previous_row, data_source),
           {:ok, event_row} <-
             event
             |> DataSourceEventRow.changeset()
             |> Repo.insert() do
        {:ok, DataSourceRow.to_domain(row), DataSourceEventRow.to_domain(event_row)}
      else
        {:error, %Changeset{} = changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp persist_data_source_projection!(%DataSource{} = data_source, opts) do
    case persist_data_source_projection(data_source, opts) do
      {:ok, source, event} -> {source, event}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp mutate_data_source(data_source_id, attrs, opts, update_fun) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_data_source(data_source_id) do
      current
      |> update_fun.(occurred_at)
      |> persist_data_source(Keyword.put(opts, :occurred_at, occurred_at))
    end
  end

  defp validate_dedicated_byo_tsdb_backend(%DataSource{
         kind: :byo_tsdb,
         isolation_level: isolation_level
       })
       when isolation_level in [:org_isolated, :mission_isolated],
       do: :ok

  defp validate_dedicated_byo_tsdb_backend(%DataSource{kind: :byo_tsdb}),
    do: {:error, :dedicated_tsdb_backend_required}

  defp validate_dedicated_byo_tsdb_backend(%DataSource{}),
    do: {:error, :byo_tsdb_backend_required}

  defp tsdb_backend_lifecycle_metadata(
         %DataSource{} = source,
         attrs,
         occurred_at,
         operation,
         default_status,
         observed_at_key
       ) do
    isolation_profile = DataSource.isolation_profile(source)

    %{
      "operation" => operation,
      "status" => text(get_attr(attrs, :status, default_status)),
      observed_at_key => DateTime.to_iso8601(occurred_at),
      "backend" =>
        text(Map.get(isolation_profile, :storage) || metadata_value(source.metadata, :storage)),
      "physical_boundary" => text(Map.get(isolation_profile, :physical_boundary)),
      "endpoint_ref" => text(Map.get(isolation_profile, :endpoint_ref)),
      "topology_ref" => text(Map.get(isolation_profile, :topology_ref)),
      "job_id" => text(get_attr(attrs, :job_id)),
      "run_id" => text(get_attr(attrs, :run_id)),
      "executor_status" => text(executor_status(get_attr(attrs, :executor_result)))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", "none"] end)
    |> Map.new()
  end

  defp put_tsdb_backend_lifecycle(%DataSource{} = source, lifecycle_metadata) do
    metadata =
      source.metadata
      |> normalize_metadata_map()
      |> Map.put("tsdb_backend_lifecycle", lifecycle_metadata)

    %DataSource{source | metadata: metadata}
  end

  defp probe_mission_id(%DataSource{mission_id: mission_id}, _attrs) when is_binary(mission_id),
    do: {:ok, mission_id}

  defp probe_mission_id(%DataSource{}, attrs) do
    case get_attr(attrs, :mission_id) do
      mission_id when is_binary(mission_id) and mission_id != "" ->
        {:ok, mission_id}

      _other ->
        {:error, "Mission id is required to record source health."}
    end
  end

  defp probe_data_source_health(%DataSource{status: :disabled}, _opts) do
    SourceProbe.unavailable(:source_disabled, %{}, probe_kind: :descriptor)
  end

  defp probe_data_source_health(%DataSource{} = data_source, opts) do
    with :ok <- validate_probe_configuration(data_source),
         {:ok, credential} <- resolve_probe_credentials(data_source, opts),
         :ok <- validate_probe_adapter(data_source) do
      run_adapter_probe(data_source, put_probe_connection_profile(opts, data_source, credential))
    else
      {:degraded, reason} ->
        SourceProbe.degraded(reason, %{}, probe_kind: :descriptor)

      {:unavailable, reason} ->
        SourceProbe.unavailable(reason, %{}, probe_kind: :descriptor)
    end
  end

  defp run_adapter_probe(%DataSource{adapter: adapter} = data_source, opts)
       when is_atom(adapter) do
    probe =
      if function_exported?(adapter, :probe, 2) do
        data_source
        |> adapter.probe(opts)
        |> SourceProbe.normalize()
      else
        SourceProbe.unsupported(%{adapter: module_text(adapter)})
      end

    probe
    |> SourceProbe.merge_metadata(connection_probe_metadata(opts))
    |> SourceProbe.merge_metadata(capability_probe_metadata(data_source, adapter, probe))
  end

  defp validate_probe_configuration(%DataSource{} = data_source) do
    case DataSource.validate_configuration(data_source) do
      :ok -> :ok
      {:error, _errors} -> {:degraded, :invalid_data_source_configuration}
    end
  end

  defp resolve_probe_credentials(%DataSource{credentials_ref: nil}, _opts), do: {:ok, nil}

  defp resolve_probe_credentials(%DataSource{} = data_source, opts) do
    resolver_opts = credential_resolver_opts(data_source, opts)

    resolver_result =
      if credential_material_resolver_configured?(opts) do
        SourceCredentials.resolve_material(data_source.credentials_ref, resolver_opts)
      else
        SourceCredentials.resolve(data_source.credentials_ref, resolver_opts)
      end

    case resolver_result do
      {:ok, credential} -> {:ok, credential}
      {:error, reason} -> {:unavailable, reason}
    end
  end

  defp credential_resolver_opts(%DataSource{} = data_source, opts) do
    opts
    |> Keyword.take([
      :credential_material_resolver,
      :credential_material_authorizer,
      :credential_secret_backend,
      :secret_backend,
      :env_material_profiles,
      :env_reader
    ])
    |> Keyword.merge(
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      data_source_id: data_source.data_source_id
    )
  end

  defp credential_material_resolver_configured?(opts) do
    configured = Application.get_env(:cadence, :dashboard_source_credentials, [])

    Keyword.has_key?(opts, :credential_material_resolver) ||
      Keyword.has_key?(opts, :credential_secret_backend) ||
      Keyword.has_key?(opts, :secret_backend) ||
      Keyword.has_key?(configured, :material_resolver) ||
      Keyword.has_key?(configured, :secret_backend)
  end

  defp put_probe_connection_profile(opts, _data_source, nil), do: opts

  defp put_probe_connection_profile(
         opts,
         %DataSource{} = data_source,
         %ResolvedSourceCredential{} = credential
       ) do
    profile = ResolvedSourceCredential.connection_profile(credential, data_source)

    opts
    |> Keyword.put(:source_connection_profile, profile)
    |> maybe_put_questdb_http_endpoint(profile)
  end

  defp put_probe_connection_profile(
         opts,
         %DataSource{} = data_source,
         %SourceCredentialMaterial{} = credential_material
       ) do
    profile =
      SourceCredentialMaterial.redacted_connection_profile(credential_material, data_source)

    opts
    |> Keyword.put(:source_connection_profile, profile)
    |> Keyword.put(
      :source_connection_material,
      SourceCredentialMaterial.adapter_options(credential_material)
    )
    |> maybe_put_questdb_http_endpoint(profile)
  end

  defp maybe_put_questdb_http_endpoint(opts, %{http_endpoint: http_endpoint})
       when is_binary(http_endpoint) do
    Keyword.put_new(opts, :questdb_http_endpoint, http_endpoint)
  end

  defp maybe_put_questdb_http_endpoint(opts, _profile), do: opts

  defp record_probe_health_and_maybe_materialize_capabilities(attrs, data_source, opts) do
    case SourceHealth.record_source_health(attrs, opts) do
      {:ok, event_or_unchanged, _status} = result ->
        with :ok <-
               maybe_materialize_adapter_capabilities(
                 data_source,
                 attrs,
                 source_health_event_id(event_or_unchanged),
                 opts
               ) do
          result
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp source_health_event_id(%SourceHealthEvent{} = event), do: event.source_health_event_id
  defp source_health_event_id(_event_or_unchanged), do: nil

  defp maybe_materialize_adapter_capabilities(%DataSource{} = data_source, attrs, event_id, opts) do
    if Keyword.get(opts, :materialize_adapter_capabilities?, false) do
      materialize_adapter_capabilities(data_source, attrs, event_id, opts)
    else
      :ok
    end
  end

  defp materialize_adapter_capabilities(%DataSource{} = data_source, attrs, event_id, opts) do
    metadata = probe_metadata(attrs)

    with true <- materializable_adapter_capability_probe?(attrs, metadata),
         reported when is_map(reported) <-
           metadata_value(metadata, :adapter_reported_capabilities) do
      reported = normalize_capability_map(reported)

      materialized =
        %DataSource{
          data_source
          | capabilities: reported,
            metadata:
              Map.merge(data_source.metadata || %{}, %{
                adapter_capability_discovery?: true,
                adapter_capability_discovery_source: :probe,
                adapter_capability_discovery_health: get_attr(attrs, :source_health),
                adapter_capability_discovery_reason: get_attr(attrs, :reason),
                adapter_capability_discovery_fingerprint:
                  metadata_value(metadata, :source_reported_capability_fingerprint)
              })
        }

      payload =
        %{
          source: "data_source_probe",
          adapter_capability_discovery?: true,
          source_health_event_id: event_id,
          probe_kind: get_in(attrs, [:payload, :probe_kind]),
          source_health: get_attr(attrs, :source_health),
          reason: get_attr(attrs, :reason),
          previous_capabilities: data_source.capabilities,
          adapter_reported_capabilities: reported,
          source_reported_capability_fingerprint:
            metadata_value(metadata, :source_reported_capability_fingerprint)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}, []] end)
        |> Map.new()

      case persist_data_source(materialized,
             actor_id: Keyword.get(opts, :actor_id),
             occurred_at: get_attr(attrs, :observed_at, DateTime.utc_now()),
             payload: payload
           ) do
        {:ok, _source} -> :ok
        {:error, reason} -> {:error, {:adapter_capability_materialization_failed, reason}}
      end
    else
      _not_materializable -> :ok
    end
  end

  defp materializable_adapter_capability_probe?(attrs, metadata) do
    get_in(attrs, [:payload, :probe_kind]) == "adapter" and
      get_attr(attrs, :source_health) in [:healthy, :degraded] and
      is_map(metadata_value(metadata, :adapter_reported_capabilities))
  end

  defp normalize_capability_map(capabilities) when is_map(capabilities) do
    capabilities
    |> Enum.map(fn {key, value} -> {text(key), value} end)
    |> Map.new()
  end

  defp validate_probe_adapter(%DataSource{adapter: nil}),
    do: {:unavailable, :source_adapter_missing}

  defp validate_probe_adapter(%DataSource{adapter: adapter}) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) do
      :ok
    else
      {:unavailable, :source_adapter_unavailable}
    end
  end

  defp validate_probe_adapter(%DataSource{}), do: {:unavailable, :source_adapter_unavailable}

  defp capability_probe_metadata(%DataSource{} = data_source, adapter, %SourceProbe{} = probe) do
    case adapter_capabilities(adapter, data_source) do
      %SourceCapabilities{} = capabilities ->
        fingerprint = source_capability_fingerprint(capabilities)
        reported_metadata = reported_capability_probe_metadata(adapter, probe, fingerprint)

        Map.merge(
          %{
            source_capability_fingerprint: fingerprint,
            source_supported_sampling: Enum.join(capabilities.supported_sampling, ","),
            source_supports_watermarks?: capabilities.supports_watermarks?,
            source_capabilities: source_capability_snapshot(adapter, capabilities, fingerprint)
          },
          reported_metadata
        )

      nil ->
        %{
          source_capabilities: %{
            adapter: module_text(adapter),
            supported?: false
          }
        }
    end
  end

  defp connection_probe_metadata(opts) do
    case Keyword.get(opts, :source_connection_profile) do
      profile when is_map(profile) -> %{source_connection_profile: profile}
      _other -> %{}
    end
  end

  defp reported_capability_probe_metadata(adapter, %SourceProbe{} = probe, configured_fingerprint) do
    case metadata_value(probe.metadata, :adapter_reported_capabilities) do
      reported when is_map(reported) ->
        case adapter_capabilities(adapter, %{capabilities: reported}) do
          %SourceCapabilities{} = capabilities ->
            fingerprint = source_capability_fingerprint(capabilities)

            %{
              source_reported_capability_fingerprint: fingerprint,
              source_reported_supported_sampling: Enum.join(capabilities.supported_sampling, ","),
              source_reported_supports_watermarks?: capabilities.supports_watermarks?,
              source_reported_capability_mismatch?: fingerprint != configured_fingerprint,
              source_reported_capabilities:
                source_capability_snapshot(adapter, capabilities, fingerprint)
            }

          nil ->
            %{source_reported_capabilities: %{adapter: module_text(adapter), supported?: false}}
        end

      _other ->
        %{}
    end
  end

  defp adapter_capabilities(adapter, data_source) when is_atom(adapter) and is_map(data_source) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :capabilities, 0),
         %SourceCapabilities{} = adapter_capabilities <-
           SourceCapabilities.normalize(adapter.capabilities()) do
      SourceCapabilities.with_data_source_capabilities(adapter_capabilities, data_source)
    else
      _other -> nil
    end
  end

  defp adapter_capabilities(_adapter, _data_source), do: nil

  defp source_capability_snapshot(adapter, %SourceCapabilities{} = capabilities, fingerprint) do
    %{
      adapter: module_text(adapter),
      supported_sampling: capabilities.supported_sampling,
      supported_products: capabilities.supported_products,
      supported_time_axes: capabilities.supported_time_axes,
      supported_value_types: capabilities.supported_value_types,
      supported_shapes: capabilities.supported_shapes,
      supports_watermarks?: capabilities.supports_watermarks?,
      completeness: capabilities.completeness,
      data_source_capabilities: get_in(capabilities.metadata, [:data_source_capabilities]) || %{},
      capability_fingerprint: fingerprint
    }
  end

  defp source_capability_fingerprint(%SourceCapabilities{} = capabilities) do
    "source-capability:" <>
      RuntimeCacheKey.fingerprint(%{
        logical_source: capabilities.logical_source,
        supported_sampling: capabilities.supported_sampling,
        supported_products: capabilities.supported_products,
        supported_time_axes: capabilities.supported_time_axes,
        supported_value_types: capabilities.supported_value_types,
        supported_shapes: capabilities.supported_shapes,
        supports_watermarks?: capabilities.supports_watermarks?,
        completeness: capabilities.completeness,
        data_source_capabilities:
          get_in(capabilities.metadata, [:data_source_capabilities]) || %{}
      })
  end

  defp source_probe_attrs(
         %DataSource{} = data_source,
         mission_id,
         %SourceProbe{} = probe,
         attrs,
         opts
       ) do
    payload =
      %{
        probe_kind: text(probe.probe_kind),
        actor_id: Keyword.get(opts, :actor_id)
      }
      |> Map.merge(Keyword.get(opts, :payload, %{}))
      |> Map.merge(connection_test_payload(probe))
      |> maybe_put_payload(:probe_message, probe.message)
      |> maybe_put_payload(:probe_metadata, probe.metadata)

    %{
      organization_id: data_source.organization_id,
      mission_id: mission_id,
      logical_source: logical_source_for_adapter(data_source.adapter) || :unknown,
      data_source_id: data_source.data_source_id,
      source_health: probe.source_health,
      reason: probe.reason,
      observed_at: get_attr(attrs, :observed_at, occurred_at(attrs, opts)),
      payload: payload
    }
  end

  defp connection_test_payload(%SourceProbe{} = probe) do
    classification = connection_test_classification(probe)

    %{
      connection_test_result: text(classification.result),
      connection_test_kind: text(classification.kind),
      connection_test_message: classification.message
    }
  end

  defp connection_test_classification(%SourceProbe{probe_kind: :adapter_unsupported}) do
    %{
      result: :unsupported,
      kind: :adapter_capability,
      message: "Adapter does not implement an active connection test."
    }
  end

  defp connection_test_classification(%SourceProbe{probe_kind: :adapter, source_health: :healthy}) do
    %{
      result: :succeeded,
      kind: :adapter_io,
      message: "Adapter connection test succeeded."
    }
  end

  defp connection_test_classification(%SourceProbe{probe_kind: :adapter}) do
    %{
      result: :failed,
      kind: :adapter_io,
      message: "Adapter connection test failed."
    }
  end

  defp connection_test_classification(%SourceProbe{source_health: :healthy}) do
    %{
      result: :skipped,
      kind: :descriptor_preflight,
      message: "Connection test was not attempted."
    }
  end

  defp connection_test_classification(%SourceProbe{}) do
    %{
      result: :blocked,
      kind: :descriptor_preflight,
      message: "Connection test was blocked before adapter IO."
    }
  end

  defp annotate_capability_probe_drift(attrs) when is_map(attrs) do
    current_metadata = probe_metadata(attrs)
    current_fingerprint = metadata_value(current_metadata, :source_capability_fingerprint)

    with fingerprint when is_binary(fingerprint) <- current_fingerprint,
         {:ok, previous_status} <- previous_source_health_status(attrs),
         previous_metadata when is_map(previous_metadata) <- probe_metadata(previous_status),
         previous_fingerprint when is_binary(previous_fingerprint) <-
           metadata_value(previous_metadata, :source_capability_fingerprint),
         true <- previous_fingerprint != fingerprint do
      put_probe_metadata(
        attrs,
        Map.merge(current_metadata, %{
          source_capability_drift?: true,
          previous_source_capability_fingerprint: previous_fingerprint,
          current_source_capability_fingerprint: fingerprint,
          previous_source_supported_sampling:
            metadata_value(previous_metadata, :source_supported_sampling),
          current_source_supported_sampling:
            metadata_value(current_metadata, :source_supported_sampling),
          previous_source_supports_watermarks?:
            metadata_value(previous_metadata, :source_supports_watermarks?),
          current_source_supports_watermarks?:
            metadata_value(current_metadata, :source_supports_watermarks?)
        })
      )
    else
      _other -> attrs
    end
  end

  defp previous_source_health_status(attrs) do
    attrs
    |> SourceHealthEvent.source_health_key()
    |> SourceHealth.fetch_source_health_status()
  end

  defp probe_metadata(%{payload: payload}) when is_map(payload) do
    case metadata_value(payload, :probe_metadata) do
      metadata when is_map(metadata) -> metadata
      _other -> %{}
    end
  end

  defp probe_metadata(_other), do: %{}

  defp put_probe_metadata(attrs, metadata) when is_map(attrs) and is_map(metadata) do
    payload = Map.get(attrs, :payload, %{}) |> Map.put(:probe_metadata, metadata)
    Map.put(attrs, :payload, payload)
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp maybe_put_payload(payload, _key, nil), do: payload
  defp maybe_put_payload(payload, _key, metadata) when metadata == %{}, do: payload
  defp maybe_put_payload(payload, key, value), do: Map.put(payload, key, value)

  defp persist_data_source_row(nil, %DataSource{} = data_source) do
    data_source
    |> DataSourceRow.changeset()
    |> Repo.insert()
  end

  defp persist_data_source_row(%DataSourceRow{} = row, %DataSource{} = data_source) do
    row
    |> DataSourceRow.changeset(data_source)
    |> Repo.update()
  end

  defp data_source_event_type(%DataSource{status: :active}, %DataSource{status: :disabled}),
    do: :enabled

  defp data_source_event_type(%DataSource{status: :disabled}, %DataSource{}), do: :disabled
  defp data_source_event_type(%DataSource{}, %DataSource{}), do: :changed
  defp data_source_event_type(%DataSource{}, nil), do: :registered

  defp current_source_event_attrs(%DataSource{} = data_source) do
    %{
      data_source_id: data_source.data_source_id,
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      current_status: data_source.status,
      current_owner: data_source.owner,
      current_kind: data_source.kind,
      current_adapter: data_source.adapter,
      current_isolation_level: data_source.isolation_level,
      current_credentials_ref: data_source.credentials_ref,
      current_capabilities: data_source.capabilities,
      current_metadata: data_source.metadata
    }
  end

  defp previous_source_event_attrs(nil), do: %{}

  defp previous_source_event_attrs(%DataSource{} = previous) do
    %{
      previous_status: previous.status,
      previous_owner: previous.owner,
      previous_kind: previous.kind,
      previous_adapter: previous.adapter,
      previous_isolation_level: previous.isolation_level,
      previous_credentials_ref: previous.credentials_ref,
      previous_capabilities: previous.capabilities,
      previous_metadata: previous.metadata
    }
  end

  defp data_source_event(%DataSource{} = data_source, previous, opts) do
    data_source
    |> current_source_event_attrs()
    |> Map.merge(previous_source_event_attrs(previous))
    |> Map.merge(%{
      event_type: data_source_event_type(data_source, previous),
      actor_id: Keyword.get(opts, :actor_id),
      occurred_at: Keyword.get(opts, :occurred_at, DateTime.utc_now()),
      payload: Keyword.get(opts, :payload, %{})
    })
    |> DataSourceEvent.new()
  end

  defp same_data_source_projection?(nil, %DataSource{}), do: false

  defp same_data_source_projection?(%DataSource{} = previous, %DataSource{} = current) do
    comparable_source_attrs(previous) == comparable_source_attrs(current)
  end

  defp comparable_source_attrs(%DataSource{} = data_source) do
    %{
      data_source_id: data_source.data_source_id,
      owner: enum_string(data_source.owner),
      kind: enum_string(data_source.kind),
      adapter: enum_string(data_source.adapter),
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      isolation_level: enum_string(data_source.isolation_level),
      credentials_ref: data_source.credentials_ref,
      status: enum_string(data_source.status),
      disabled_at: data_source.disabled_at,
      capabilities: JsonDocument.encode(data_source.capabilities),
      metadata: JsonDocument.encode(data_source.metadata)
    }
  end

  defp persist_data_binding_projection(%DataBinding{} = data_binding, opts) do
    previous_row = Repo.get(DataBindingRow, data_binding.binding_id)
    previous = previous_row && DataBindingRow.to_domain(previous_row)
    data_binding = prepare_data_binding_projection(data_binding, previous)

    if same_data_binding_projection?(previous, data_binding) do
      {:ok, previous, nil}
    else
      event = data_binding_event(data_binding, previous, opts)
      data_binding = %{data_binding | current_event_id: event.data_binding_event_id}

      with {:ok, row} <- persist_data_binding_row(previous_row, data_binding),
           {:ok, event_row} <-
             event
             |> DataBindingEventRow.changeset()
             |> Repo.insert(),
           event = DataBindingEventRow.to_domain(event_row),
           {:ok, _operational_event_or_skipped} <- persist_data_binding_operational_event(event) do
        {:ok, DataBindingRow.to_domain(row), event}
      else
        {:error, %Changeset{} = changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp persist_data_binding_operational_event(%DataBindingEvent{mission_id: mission_id})
       when is_nil(mission_id) or mission_id == "",
       do: {:ok, :skipped_non_mission_scoped_binding}

  defp persist_data_binding_operational_event(%DataBindingEvent{} = event) do
    event
    |> OperationalEvent.from_data_binding_event()
    |> then(&OperationalEvents.persist_event(Repo, &1))
  end

  defp prepare_data_binding_projection(%DataBinding{} = data_binding, nil) do
    %DataBinding{
      data_binding
      | binding_version: positive_integer(data_binding.binding_version, 1)
    }
  end

  defp prepare_data_binding_projection(%DataBinding{} = data_binding, %DataBinding{} = previous) do
    %DataBinding{data_binding | binding_version: previous.binding_version + 1}
  end

  defp persist_data_binding_row(nil, %DataBinding{} = data_binding) do
    data_binding
    |> DataBindingRow.changeset()
    |> Repo.insert()
  end

  defp persist_data_binding_row(%DataBindingRow{} = row, %DataBinding{} = data_binding) do
    row
    |> DataBindingRow.changeset(data_binding)
    |> Repo.update()
  end

  defp mutate_data_binding(binding_id, attrs, opts, update_fun) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataBinding{} = current} <- fetch_data_binding(binding_id) do
      current
      |> update_fun.(occurred_at)
      |> apply_data_binding_attrs(attrs)
      |> persist_data_binding(Keyword.put(opts, :occurred_at, occurred_at))
    end
  end

  defp data_binding_event(%DataBinding{} = data_binding, previous, opts) do
    data_binding
    |> current_event_attrs()
    |> Map.merge(previous_event_attrs(previous))
    |> Map.merge(%{
      event_type: data_binding_event_type(data_binding, previous),
      actor_id: Keyword.get(opts, :actor_id),
      occurred_at: Keyword.get(opts, :occurred_at, DateTime.utc_now()),
      payload: Keyword.get(opts, :payload, %{})
    })
    |> DataBindingEvent.new()
  end

  defp current_event_attrs(%DataBinding{} = data_binding) do
    %{
      binding_id: data_binding.binding_id,
      organization_id: data_binding.organization_id,
      mission_id: data_binding.mission_id,
      current_status: data_binding.status,
      current_binding_version: data_binding.binding_version,
      current_logical_source: data_binding.logical_source,
      current_realm: data_binding.realm,
      current_data_source_id: data_binding.data_source_id,
      current_dataset: data_binding.dataset,
      current_priority: data_binding.priority,
      current_active_from: data_binding.active_from,
      current_active_to: data_binding.active_to
    }
  end

  defp previous_event_attrs(nil), do: %{}

  defp previous_event_attrs(%DataBinding{} = previous) do
    %{
      previous_status: previous.status,
      previous_binding_version: previous.binding_version,
      previous_logical_source: previous.logical_source,
      previous_realm: previous.realm,
      previous_data_source_id: previous.data_source_id,
      previous_dataset: previous.dataset,
      previous_priority: previous.priority,
      previous_active_from: previous.active_from,
      previous_active_to: previous.active_to
    }
  end

  defp data_binding_event_type(%DataBinding{}, nil), do: :registered

  defp data_binding_event_type(%DataBinding{status: :disabled}, %DataBinding{}), do: :disabled
  defp data_binding_event_type(%DataBinding{status: :superseded}, %DataBinding{}), do: :superseded

  defp data_binding_event_type(%DataBinding{status: :active}, %DataBinding{
         status: previous_status
       })
       when previous_status in [:disabled, :superseded],
       do: :enabled

  defp data_binding_event_type(%DataBinding{}, %DataBinding{}), do: :changed

  defp same_data_binding_projection?(nil, %DataBinding{}), do: false

  defp same_data_binding_projection?(%DataBinding{} = previous, %DataBinding{} = current) do
    comparable_binding_attrs(previous) == comparable_binding_attrs(current)
  end

  defp comparable_binding_attrs(%DataBinding{} = data_binding) do
    %{
      binding_id: data_binding.binding_id,
      organization_id: data_binding.organization_id,
      mission_id: data_binding.mission_id,
      realm: enum_string(data_binding.realm),
      logical_source: enum_string(data_binding.logical_source),
      data_source_id: data_binding.data_source_id,
      dataset: data_binding.dataset,
      priority: data_binding.priority,
      status: enum_string(data_binding.status),
      active_from: data_binding.active_from,
      active_to: data_binding.active_to,
      disabled_at: data_binding.disabled_at,
      superseded_at: data_binding.superseded_at,
      metadata: JsonDocument.encode(data_binding.metadata)
    }
  end

  defp apply_data_binding_attrs(%DataBinding{} = data_binding, attrs) do
    %DataBinding{
      data_binding
      | data_source_id: get_attr(attrs, :data_source_id, data_binding.data_source_id),
        dataset: get_attr(attrs, :dataset, data_binding.dataset),
        priority: get_attr(attrs, :priority, data_binding.priority),
        metadata: merge_metadata(data_binding.metadata, get_attr(attrs, :metadata))
    }
  end

  defp merge_metadata(metadata, nil), do: metadata

  defp merge_metadata(metadata, patch) when is_map(metadata) and is_map(patch),
    do: Map.merge(metadata, patch)

  defp merge_metadata(_metadata, patch) when is_map(patch), do: patch
  defp merge_metadata(metadata, _patch), do: metadata

  defp normalize_metadata_map(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata_map(_metadata), do: %{}

  defp executor_status(%{} = result), do: metadata_value(result, :status)
  defp executor_status(_result), do: nil

  defp occurred_at(attrs, opts) do
    attrs
    |> get_attr(:occurred_at, Keyword.get(opts, :occurred_at, DateTime.utc_now()))
    |> DateTime.truncate(:microsecond)
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp module_text(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp text(nil), do: "none"
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp events_to_intervals(events) do
    events
    |> Enum.group_by(& &1.binding_id)
    |> Enum.flat_map(fn {_binding_id, binding_events} ->
      binding_events
      |> Enum.sort_by(&event_sort_key/1)
      |> binding_events_to_intervals()
    end)
    |> Enum.sort_by(&interval_sort_key/1)
  end

  defp binding_events_to_intervals(events) do
    events
    |> Enum.zip(tl(events) ++ [nil])
    |> Enum.map(fn {event, next_event} ->
      DataBindingInterval.from_event(event, next_event && next_event.occurred_at)
    end)
  end

  defp event_sort_key(%DataBindingEvent{} = event) do
    {DateTime.to_unix(event.occurred_at, :microsecond), event.data_binding_event_id}
  end

  defp interval_sort_key(%DataBindingInterval{} = interval) do
    {interval.binding_id, DateTime.to_unix(interval.started_at, :microsecond)}
  end

  defp filter_intervals(intervals, opts) do
    intervals
    |> maybe_filter_interval_binding_id(Keyword.get(opts, :binding_id))
    |> maybe_filter_interval_logical_source(Keyword.get(opts, :logical_source))
    |> maybe_filter_interval_realm(Keyword.get(opts, :realm))
  end

  defp maybe_filter_interval_binding_id(intervals, nil), do: intervals

  defp maybe_filter_interval_binding_id(intervals, binding_id) when is_binary(binding_id) do
    Enum.filter(intervals, &(&1.binding_id == binding_id))
  end

  defp maybe_filter_interval_logical_source(intervals, nil), do: intervals

  defp maybe_filter_interval_logical_source(intervals, logical_source) do
    Enum.filter(intervals, &(normalize_enum(&1.logical_source) == normalize_enum(logical_source)))
  end

  defp maybe_filter_interval_realm(intervals, nil), do: intervals

  defp maybe_filter_interval_realm(intervals, realm) do
    Enum.filter(intervals, &(normalize_enum(&1.realm) == normalize_enum(realm)))
  end

  defp maybe_filter_data_source_id(query, nil), do: query

  defp maybe_filter_data_source_id(query, data_source_id) when is_binary(data_source_id) do
    where(query, [row], row.data_source_id == ^data_source_id)
  end

  defp normalize_enum(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_enum(value), do: value

  defp logical_source_for_adapter(Telemetry), do: :telemetry
  defp logical_source_for_adapter(Limits), do: :limits
  defp logical_source_for_adapter(OperationalObservables), do: :operational_observables
  defp logical_source_for_adapter(Events), do: :events
  defp logical_source_for_adapter(_adapter), do: nil

  defp maybe_scope_organization(query, nil), do: query

  defp maybe_scope_organization(query, organization_id) when is_binary(organization_id) do
    where(query, [row], is_nil(row.organization_id) or row.organization_id == ^organization_id)
  end

  defp maybe_scope_mission(query, nil), do: query

  defp maybe_scope_mission(query, mission_id) when is_binary(mission_id) do
    where(query, [row], is_nil(row.mission_id) or row.mission_id == ^mission_id)
  end

  defp active_binding?(%DataBinding{} = binding, %DateTime{} = now) do
    DataBinding.active?(binding) and active_after?(binding.active_from, now) and
      active_before?(binding.active_to, now)
  end

  defp active_after?(nil, _now), do: true
  defp active_after?(active_from, now), do: DateTime.compare(active_from, now) != :gt

  defp active_before?(nil, _now), do: true
  defp active_before?(active_to, now), do: DateTime.compare(active_to, now) == :gt

  defp normalize_realm(%DataBinding{realm: realm}) when is_atom(realm), do: Atom.to_string(realm)
  defp normalize_realm(%DataBinding{realm: realm}), do: realm

  defp realm_sort_key("flight"), do: {0, "flight"}
  defp realm_sort_key("rehearsal"), do: {1, "rehearsal"}
  defp realm_sort_key("replay"), do: {2, "replay"}
  defp realm_sort_key(realm), do: {3, realm}
end
