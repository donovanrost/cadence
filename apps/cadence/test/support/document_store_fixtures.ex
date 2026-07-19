defmodule Cadence.Dashboards.DocumentStoreFixtures do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataSource,
    DataSources,
    Document,
    Engine,
    RuntimeInvalidation
  }

  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.Dashboards.DocumentStore.VersionRow, as: DashboardVersionRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @fixture_dir Path.expand("../fixtures/dashboards", __DIR__)

  def load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  def scope_document(%Document{} = document, organization_id, mission_id, dashboard_id) do
    %Document{
      document
      | organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: dashboard_id
    }
  end

  def persist_publish_source!(
        organization_id,
        mission_id,
        logical_source,
        data_source_id,
        binding_id,
        adapter,
        capabilities
      ) do
    assert {:ok, %DataSource{}} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :projection,
               adapter: adapter,
               organization_id: organization_id,
               mission_id: mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    assert {:ok, %DataBinding{}} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: organization_id,
               mission_id: mission_id,
               realm: :flight,
               logical_source: logical_source,
               data_source_id: data_source_id,
               dataset: Atom.to_string(logical_source),
               priority: 0
             })
  end

  def health_snapshot do
    %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => "dashboard_health_snapshot_abc123",
      "organization_id" => "org-doc-health-snapshot",
      "mission_id" => "mission-doc-health-snapshot",
      "dashboard_id" => "dashboard-doc-health-snapshot",
      "state" => "blocked",
      "severity" => "error",
      "counts" => %{
        "widgets" => 2,
        "ready" => 1,
        "degraded" => 0,
        "stale" => 0,
        "blocked" => 1,
        "affected" => 1
      },
      "placement_ids" => %{
        "affected" => ["blocked-placement"],
        "blocked" => ["blocked-placement"],
        "stale" => [],
        "degraded" => []
      }
    }
  end

  def insert_raw_dashboard_row!(organization_id, mission_id, dashboard_id, raw_document) do
    encoded_document = JsonDocument.encode(raw_document)

    Repo.insert!(%OpsDashboardRow{
      dashboard_id: dashboard_id,
      organization_id: organization_id,
      mission_id: mission_id,
      name: raw_document["name"],
      description: raw_document["description"],
      document: encoded_document,
      latest_version: 1,
      draft_version: 1,
      lifecycle_state: "active"
    })

    Repo.insert!(%DashboardVersionRow{
      dashboard_version_id: "#{dashboard_id}-version-1",
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: dashboard_id,
      version: 1,
      document: encoded_document,
      snapshot_kind: :draft_save,
      schema_version: 1
    })
  end

  def plan_cache_status(%Document{} = document) do
    document
    |> resolve_request()
    |> Engine.plan()
    |> get_in([Access.key!(:plan_metadata), Access.key!(:cache), Access.key!(:plan_cache)])
    |> Map.fetch!(:status)
  end

  def attach_runtime_invalidation_telemetry(test_pid) do
    handler_id = "document-store-runtime-invalidation-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [RuntimeInvalidation.telemetry_event()],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:runtime_invalidation_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  def resolve_request(%Document{} = document) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{
        placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}
      }
    }
  end
end
