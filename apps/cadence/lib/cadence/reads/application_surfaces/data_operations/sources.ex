defmodule Cadence.Reads.ApplicationSurfaces.DataOperations.Sources do
  @moduledoc "Semantic source configuration, binding, health, watermark and deployment evidence."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.DataSources.AdapterRegistry
  alias Cadence.ExtensionCatalog
  alias Cadence.Jobs
  alias Cadence.Missions
  alias Cadence.Reads.DataSources

  @pages ~w(page bindings_page events_page binding_events_page health_page health_events_page watermarks_page jobs_page)a
  @subjects ~w(data_source_id binding_id)
  @keys @subjects ++ Enum.map(@pages, &Atom.to_string/1)
  @page_size 25

  def load(%Scope{} = scope, mission, mode, params) do
    with :ok <- authorize(scope, mission, mode),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission),
         {:ok, query} <- admit_query(params),
         {:ok, source} <- selected_source(scope, mission, query.data_source_id),
         :ok <- selected_mode(mode, source),
         {:ok, binding} <- selected_binding(scope, mission, source, query.binding_id) do
      manage =
        Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}) ==
          :ok

      sources = DataSources.source_inventory_page(scope.organization_id, mission, query.page)

      bindings =
        DataSources.binding_inventory_page(
          scope.organization_id,
          mission,
          query.bindings_page,
          source && source.data_source_id
        )

      model = %{
        contract_version: 1,
        context: %{organization_id: scope.organization_id, mission_id: mission},
        mode: mode,
        query: query,
        permissions: %{manage: manage},
        sources: map_page(sources, &source_dto(&1, scope, mission)),
        bindings: map_page(bindings, &binding_dto(&1, scope, mission)),
        selected: source && selected_dto(scope, mission, source, binding, query),
        adapters:
          ExtensionCatalog.source_adapters()
          |> Enum.map(&to_string(&1.logical_source))
          |> Enum.sort(),
        defaults: defaults()
      }

      {:ok, model, %{source: source, binding: binding}}
    end
  end

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @keys)),
         {:ok, source} <- subject(params["data_source_id"]),
         {:ok, binding} <- subject(params["binding_id"]),
         {:ok, pages} <- pages(params) do
      {:ok, Map.merge(pages, %{data_source_id: source, binding_id: binding})}
    else
      _ -> {:error, :invalid_source_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_source_query}

  def source_evidence(source), do: digest({source, credential_review(source)})

  defp credential_review(%{credentials_ref: nil}), do: nil

  defp credential_review(source),
    do: DataSources.fetch_credential_reference(source.credentials_ref)

  def binding_evidence(binding), do: digest(binding)
  def job_evidence(job), do: digest(job)

  def visible?(record, scope, mission),
    do:
      record.organization_id in [nil, scope.organization_id] and
        record.mission_id in [nil, mission]

  def editable?(record, scope, mission),
    do: record.organization_id == scope.organization_id and record.mission_id == mission

  defp authorize(scope, mission, mode) do
    with true <- mode in ["reader", "registration", "settings"],
         true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }) do
      if mode == "reader",
        do: :ok,
        else: Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id})
    else
      _ -> {:error, :forbidden}
    end
  end

  defp selected_source(_, _, nil), do: {:ok, nil}

  defp selected_source(scope, mission, id) do
    with {:ok, source} <- DataSources.fetch_data_source(id),
         true <- visible?(source, scope, mission) do
      {:ok, source}
    else
      _ -> {:error, :source_unavailable}
    end
  end

  defp selected_mode("settings", nil), do: {:error, :source_required}

  defp selected_mode("registration", source) when not is_nil(source),
    do: {:error, :unexpected_source}

  defp selected_mode(_, _), do: :ok

  defp selected_binding(_, _, _, nil), do: {:ok, nil}

  defp selected_binding(scope, mission, source, id) when not is_nil(source) do
    with {:ok, binding} <- DataSources.fetch_data_binding(id),
         true <- visible?(binding, scope, mission),
         true <- binding.data_source_id == source.data_source_id do
      {:ok, binding}
    else
      _ -> {:error, :binding_unavailable}
    end
  end

  defp selected_binding(_, _, _, _), do: {:error, :binding_unavailable}

  defp selected_dto(scope, mission, source, binding, query) do
    org = scope.organization_id
    id = source.data_source_id

    %{
      source: source_dto(source, scope, mission),
      binding: binding && binding_dto(binding, scope, mission),
      events:
        DataSources.source_event_page(org, mission, query.events_page, id)
        |> map_page(&source_event/1),
      binding_events: binding_events(org, mission, binding, query.binding_events_page),
      health: projection_page(org, mission, id, query.health_page, :health),
      health_events: projection_page(org, mission, id, query.health_events_page, :health_events),
      watermarks: projection_page(org, mission, id, query.watermarks_page, :watermarks),
      jobs: Jobs.source_deployment_page(org, mission, id, query.jobs_page) |> map_page(&job_dto/1)
    }
  end

  defp source_dto(source, scope, mission) do
    capabilities =
      source.capabilities
      |> Enum.filter(fn {_, v} -> is_boolean(v) end)
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)

    lifecycle = value(source.metadata, :tsdb_backend_lifecycle) || %{}

    %{
      id: source.data_source_id,
      organization_id: source.organization_id,
      mission_id: source.mission_id,
      owner: to_string(source.owner),
      kind: to_string(source.kind),
      status: to_string(source.status),
      isolation: to_string(source.isolation_level),
      logical_source: AdapterRegistry.logical_source(source.adapter) |> optional_text(),
      credential_reference: source.credentials_ref,
      event_id: source.current_event_id,
      editable: editable?(source, scope, mission),
      evidence: source_evidence(source),
      backend: %{
        status: safe_code(value(lifecycle, :status)),
        operation: safe_code(value(lifecycle, :operation))
      },
      capabilities:
        capabilities
        |> Enum.take(25)
        |> Enum.map(fn {key, enabled} -> %{name: to_string(key), enabled: enabled} end),
      capabilities_more: length(capabilities) > 25
    }
  end

  defp binding_dto(binding, scope, mission) do
    %{
      id: binding.binding_id,
      source_id: binding.data_source_id,
      logical_source: to_string(binding.logical_source),
      realm: to_string(binding.realm),
      dataset: binding.dataset,
      priority: binding.priority,
      status: to_string(binding.status),
      version: binding.binding_version,
      event_id: binding.current_event_id,
      active_from: iso(binding.active_from),
      active_to: iso(binding.active_to),
      editable: editable?(binding, scope, mission),
      evidence: binding_evidence(binding)
    }
  end

  defp binding_events(_org, _mission, nil, page),
    do: %{entries: [], page: page, page_size: @page_size, has_next: false}

  defp binding_events(org, mission, binding, page),
    do:
      DataSources.binding_event_page(org, mission, page, binding.binding_id)
      |> map_page(&binding_event/1)

  defp source_event(event),
    do: %{
      id: event.data_source_event_id,
      source_id: event.data_source_id,
      type: to_string(event.event_type),
      status: to_string(event.current_status),
      actor_id: event.actor_id,
      occurred_at: iso(event.occurred_at)
    }

  defp binding_event(event),
    do: %{
      id: event.data_binding_event_id,
      binding_id: event.binding_id,
      source_id: event.current_data_source_id,
      previous_source_id: event.previous_data_source_id,
      type: to_string(event.event_type),
      status: to_string(event.current_status),
      version: event.current_binding_version,
      actor_id: event.actor_id,
      occurred_at: iso(event.occurred_at)
    }

  defp projection_page(org, mission, id, page, kind) do
    opts = [data_source_id: id, limit: @page_size + 1, offset: (page - 1) * @page_size]

    {rows, convert} =
      case kind do
        :health ->
          {DataSources.list_source_health_statuses(org, mission, opts), &health_dto/1}

        :health_events ->
          {DataSources.list_source_health_events(org, mission, opts), &health_event_dto/1}

        :watermarks ->
          {DataSources.list_source_watermark_statuses(org, mission, opts), &watermark_dto/1}
      end

    %{
      entries: rows |> Enum.take(@page_size) |> Enum.map(convert),
      page: page,
      page_size: @page_size,
      has_next: length(rows) > @page_size
    }
  end

  defp observation_identity(row),
    do: %{
      source_id: row.data_source_id,
      binding_id: row.source_binding_id,
      logical_source: to_string(row.logical_source),
      realm: optional_text(row.realm),
      dataset: row.dataset,
      replay_run_id: row.replay_run_id,
      observed_at: iso(row.observed_at)
    }

  defp health_event_dto(row),
    do:
      Map.merge(observation_identity(row), %{
        id: row.source_health_event_id,
        state: to_string(row.source_health),
        reason: safe_code(row.reason)
      })

  defp health_dto(row),
    do:
      Map.merge(health_event_dto(row), %{
        key: row.source_health_key,
        last_seen_at: iso(row.last_seen_at),
        transitions: row.transition_count
      })

  defp watermark_dto(row),
    do:
      Map.merge(observation_identity(row), %{
        id: row.source_watermark_event_id,
        key: row.source_watermark_key,
        complete_through: iso(row.complete_through),
        latest_receipt_time: iso(row.latest_receipt_time),
        retention_starts_at: iso(row.retention_starts_at),
        confidence: to_string(row.confidence),
        sample_count: row.sample_count,
        last_seen_at: iso(row.last_seen_at),
        reason: safe_code(row.reason)
      })

  defp job_dto(job),
    do: %{
      id: job.job_id,
      run_id: job.run_id,
      type: to_string(job.job_type),
      status: to_string(job.status),
      attempts: job.attempt_count,
      operation: safe_code(value(job.payload, :operation)),
      started_at: iso(job.started_at),
      completed_at: iso(job.completed_at),
      failure_recorded: not is_nil(job.failure_reason),
      evidence: job_evidence(job)
    }

  defp defaults,
    do: %{
      data_source_id: "",
      logical_source: "telemetry",
      kind: "managed_tsdb",
      isolation_level: "mission_isolated",
      credentials_ref: "",
      credential_provider: "",
      endpoint_ref: "",
      material_env_profile: "",
      http_endpoint_env: "",
      storage: "questdb"
    }

  defp pages(params) do
    Enum.reduce_while(@pages, {:ok, %{}}, fn key, {:ok, acc} ->
      case positive_page(Map.get(params, Atom.to_string(key), "1")) do
        {:ok, page} -> {:cont, {:ok, Map.put(acc, key, page)}}
        _ -> {:halt, {:error, :invalid_page}}
      end
    end)
  end

  defp positive_page(value) when is_integer(value) and value in 1..1_000_000, do: {:ok, value}

  defp positive_page(value) when is_binary(value) and byte_size(value) <= 7 do
    case Integer.parse(value) do
      {page, ""} when page in 1..1_000_000 -> {:ok, page}
      _ -> {:error, :invalid_page}
    end
  end

  defp positive_page(_), do: {:error, :invalid_page}
  defp subject(value) when value in [nil, ""], do: {:ok, nil}

  defp subject(value) when is_binary(value) and byte_size(value) <= 240 do
    if String.valid?(value), do: {:ok, value}, else: {:error, :invalid_subject}
  end

  defp subject(_), do: {:error, :invalid_subject}
  defp map_page(page, convert), do: %{page | entries: Enum.map(page.entries, convert)}

  defp digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
      |> Base.encode16(case: :lower)

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_, _), do: nil
  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp optional_text(nil), do: nil
  defp optional_text(value), do: to_string(value)
  defp safe_code(nil), do: nil
  defp safe_code(value) when is_atom(value), do: Atom.to_string(value)

  defp safe_code(value) when is_binary(value) do
    if Regex.match?(~r/^[a-z][a-z0-9_.-]{0,79}$/, value), do: value, else: "details_withheld"
  end

  defp safe_code(_), do: "details_withheld"
end
