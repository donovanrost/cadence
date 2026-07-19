defmodule Cadence.Dashboards.DataSourcesFixtures do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Revision

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    Frame,
    PlannedSourceRequest,
    RuntimeCacheKey,
    SourceResult,
    SourceWatermark
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow}

  @fixture_dir Path.expand("../fixtures/dashboards", __DIR__)

  def persist_source(data_source_id, isolation_level) do
    assert {:ok, data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id:
                 if(isolation_level == :mission_isolated, do: "mission-dash-source", else: nil),
               isolation_level: isolation_level,
               capabilities: %{range_scan?: true},
               metadata: %{storage: :questdb}
             })

    data_source
  end

  def persist_watermarked_source(data_source_id) do
    assert {:ok, data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    data_source
  end

  def source_cache_entries(result) do
    result.plan_metadata
    |> get_in([:cache, :source_result_cache_by_request_id])
    |> Map.values()
  end

  def source_cache_statuses(result) do
    result
    |> source_cache_entries()
    |> Enum.map(& &1.status)
    |> Enum.sort()
  end

  def segmented_history_document do
    "time_series_with_limits.v1.json"
    |> load_fixture_map!()
    |> Map.put("organization_id", "org-dash-source")
    |> Map.put("mission_id", "mission-dash-source")
    |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "observables"], [
      "HK.counter"
    ])
    |> put_in(
      ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
      "raw_series"
    )
    |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
    |> Document.from_map()
  end

  def load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  def persist_limits_source(data_source_id) do
    assert {:ok, data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :projection,
               adapter: Cadence.Dashboards.Sources.Limits,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest_state?: true,
                 event_history?: true,
                 definition_intervals?: true,
                 watermarks?: true
               },
               metadata: %{storage: :postgres_projection}
             })

    data_source
  end

  def use_dashboard_runtime_cache!(cache) do
    previous_config = Application.get_env(:cadence, :dashboard_runtime_invalidation, [])

    Application.put_env(:cadence, :dashboard_runtime_invalidation,
      enabled?: true,
      runtime_cache: cache
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_runtime_invalidation, previous_config)
    end)
  end

  def dashboard_source_result_key(logical_source, opts) do
    request = dashboard_source_request(logical_source, opts)

    RuntimeCacheKey.source_result(request,
      source_binding: dashboard_source_binding(logical_source, opts),
      data_source: dashboard_data_source(logical_source, opts),
      watermark: dashboard_watermark(logical_source, opts)
    )
  end

  def dashboard_frame_key(%RuntimeCacheKey{} = source_key, frame_id) do
    RuntimeCacheKey.frame(source_key,
      placement_id: "placement-#{frame_id}",
      placement_size: %{width_px: 320, height_px: 120},
      display: %{density: :normal},
      frame_shape: :scalar
    )
  end

  def dashboard_source_request(logical_source, opts) do
    binding_id = Keyword.fetch!(opts, :binding_id)

    %PlannedSourceRequest{
      request_id: "source-request-#{binding_id}",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      logical_source: logical_source,
      observables: [Keyword.get(opts, :observable, "HK.counter")],
      data_context: %{realm: Keyword.fetch!(opts, :realm)},
      sampling: %{mode: :latest}
    }
  end

  def dashboard_source_binding(logical_source, opts) do
    %DataBinding{
      binding_id: Keyword.fetch!(opts, :binding_id),
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: Keyword.fetch!(opts, :realm),
      logical_source: logical_source,
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      dataset: Keyword.fetch!(opts, :dataset),
      priority: 0
    }
  end

  def dashboard_data_source(logical_source, opts) do
    %DataSource{
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      owner: :cadence,
      kind: dashboard_source_kind(logical_source),
      adapter: dashboard_source_adapter(logical_source),
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{latest?: true, latest_state?: true, event_history?: true, watermarks?: true}
    }
  end

  def dashboard_source_result(%RuntimeCacheKey{} = key) do
    %SourceResult{
      request_id: key.parts.request.request_id,
      watermarks: []
    }
  end

  def dashboard_frames(logical_source, frame_id) do
    [%Frame{frame_id: frame_id, source: logical_source, shape: :scalar, fields: []}]
  end

  def dashboard_watermark(logical_source, opts) do
    %SourceWatermark{
      logical_source: logical_source,
      request_id: "source-request-#{Keyword.fetch!(opts, :binding_id)}",
      source_binding_id: Keyword.fetch!(opts, :binding_id),
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      realm: Keyword.fetch!(opts, :realm),
      dataset: Keyword.fetch!(opts, :dataset),
      complete_through: ~U[2026-06-17 12:00:00Z],
      latest_receipt_time: ~U[2026-06-17 12:00:00Z],
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: :best_effort,
      freshness_state: :fresh
    }
  end

  def dashboard_source_kind(:limits), do: :projection
  def dashboard_source_kind(_logical_source), do: :managed_tsdb

  def dashboard_source_adapter(:limits), do: Cadence.Dashboards.Sources.Limits
  def dashboard_source_adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry

  def catalog_revision(catalog_revision_id, opts) do
    Revision.new(%{
      catalog_revision_id: catalog_revision_id,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      catalog_database_id: "bus-catalog",
      revision_number: Keyword.fetch!(opts, :revision_number),
      revision_label: Keyword.get(opts, :revision_label, "FSW 3.6"),
      catalog_family: :telemetry,
      artifact_id: "#{catalog_revision_id}-artifact",
      import_run_id: "#{catalog_revision_id}-import-run",
      telemetry_snapshot_id: "#{catalog_revision_id}-telemetry-snapshot",
      command_snapshot_id: nil,
      content_sha256: "#{catalog_revision_id}-sha",
      created_by: %{"service_identity_id" => "svc-importer"},
      metadata: %{"source_artifact_name" => "#{catalog_revision_id}.json"}
    })
  end

  def application_binding_set(binding_set_id, opts) do
    source_endpoint_ref = Keyword.fetch!(opts, :source_endpoint_ref)
    apid = Keyword.fetch!(opts, :apid)
    metric_name = Keyword.fetch!(opts, :metric_name)

    BindingSet.new(%{
      mission_id: "mission-dash-source",
      binding_set_id: binding_set_id,
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "#{binding_set_id}-packet-counter",
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => metric_name,
              "flush_interval_ms" => 25
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "#{binding_set_id}-packet-counter-rule",
          capability_instance_id: "#{binding_set_id}-packet-counter",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: apid}
          },
          priority: 10,
          fanout_mode: :multi
        })
      ]
    })
  end

  def persist_source_endpoint_scope(source_endpoint_ref) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: "org-dash-source",
        mission_id: "mission-dash-source",
        display_name: "SC-001"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft("org-dash-source", spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_ref,
        organization_id: "org-dash-source",
        mission_id: "mission-dash-source",
        spacecraft_id: "sc-001",
        source_ref: "provider/#{source_endpoint_ref}"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint("org-dash-source", source_endpoint)
  end

  def metadata_errors(%Ecto.Changeset{} = changeset) do
    field_errors(changeset, :metadata)
  end

  def field_errors(%Ecto.Changeset{} = changeset, field) do
    for {^field, {message, _opts}} <- changeset.errors, do: message
  end

  def questdb_probe_exec_fun(test_pid, mode) do
    fn sql, _opts ->
      send(test_pid, {:questdb_probe_sql, sql})

      questdb_probe_response(sql, mode)
    end
  end

  def questdb_probe_exec_with_opts_fun(test_pid, mode) do
    fn sql, opts ->
      send(test_pid, {:questdb_probe_sql, sql, opts})

      questdb_probe_response(sql, mode)
    end
  end

  def questdb_probe_response("SELECT 1", :connection_error), do: {:error, :econnrefused}

  def questdb_probe_response("SELECT 1", :auth_error),
    do: {:error, {:http_error, 403, %{"error" => "forbidden", "token" => "secret-token"}}}

  def questdb_probe_response("SELECT 1", _mode),
    do: {:ok, %{"columns" => [%{"name" => "1"}], "dataset" => [[1]]}}

  def questdb_probe_response(sql, mode) do
    cond do
      mode == :schema_ok and String.contains?(sql, "FROM telemetry_observations") ->
        {:ok, %{"columns" => questdb_probe_columns(), "dataset" => []}}

      mode == :schema_missing_identity and String.contains?(sql, "FROM telemetry_observations") ->
        columns = Enum.reject(questdb_probe_columns(), &(&1["name"] == "observation_identity_id"))
        {:ok, %{"columns" => columns, "dataset" => []}}

      mode == :schema_error and String.contains?(sql, "FROM telemetry_observations") ->
        {:error, %{"error" => "table does not exist"}}
    end
  end

  def questdb_probe_columns do
    writer_columns =
      ObservationRow.columns()
      |> Enum.map(&Atom.to_string/1)

    (ObservationReader.select_columns() ++ writer_columns)
    |> Enum.uniq()
    |> Enum.map(&%{"name" => &1})
  end

  def sample(point_id, sample_id, value, receipt_time, evidence_id, overrides) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-dash-source",
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: evidence_id,
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: nil,
      receipt_time: receipt_time,
      provenance: %{}
    }
    |> struct!(overrides)
  end

  def source_request(overrides \\ []) do
    attrs = %{
      request_id: "source-request-1",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{realm: :flight},
      sampling: %{mode: :raw_series}
    }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end
end
