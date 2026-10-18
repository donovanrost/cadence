defmodule Cadence.Reads.DataSourceInventoryTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.Scope
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Jobs
  alias Cadence.Jobs.BackgroundJobRow
  alias Cadence.Management.DataSources, as: Definitions
  alias Cadence.Projections.DataSources.{Health, Watermarks}
  alias Cadence.Reads.ApplicationSurfaces.DataOperations.Sources, as: Read

  @org "org-source-inventory"
  @mission "mission-source-inventory"
  @time ~U[2026-09-09 01:02:03.123456Z]

  setup do
    %{organization: org} = persist_mission_scope(@org, @mission)
    %{reader: scope(org, :member), admin: scope(org, :organization_admin)}
  end

  test "real mission and shared sources are visible, with scope and management admission", c do
    source("owned")
    source("shared", organization_id: nil, mission_id: nil, isolation_level: :shared)
    persist_mission_scope(@org, "other-mission")
    source("foreign", mission_id: "other-mission")
    assert {:ok, model, _} = Read.load(c.reader, @mission, "reader", %{})
    assert Enum.find(model.sources.entries, &(&1.id == "owned")).editable
    refute Enum.find(model.sources.entries, &(&1.id == "shared")).editable
    refute Enum.any?(model.sources.entries, &(&1.id == "foreign"))
    refute model.permissions.manage

    assert {:error, :forbidden} =
             Read.load(c.reader, @mission, "settings", %{"data_source_id" => "owned"})

    assert {:error, :forbidden} = Read.load(c.reader, @mission, "registration", %{})

    assert {:error, :source_unavailable} =
             Read.load(c.admin, @mission, "reader", %{"data_source_id" => "foreign"})

    assert {:ok, registration, _} = Read.load(c.admin, @mission, "registration", %{})
    assert registration.permissions.manage
    assert "telemetry" in registration.adapters
    assert {:ok, _, _} = Read.load(c.admin, @mission, "settings", %{"data_source_id" => "owned"})
  end

  test "source directory and binding pages are independent and do not lose late records", c do
    for n <- 1..52, do: source("000-source-#{String.pad_leading(to_string(n), 3, "0")}")
    source = source("selected")

    for n <- 1..27,
        do: binding("binding-#{String.pad_leading(to_string(n), 3, "0")}", source.data_source_id)

    assert {:ok, model, _} =
             Read.load(c.reader, @mission, "reader", %{
               "page" => "3",
               "data_source_id" => "selected",
               "bindings_page" => "2"
             })

    assert model.sources.page == 3
    assert Enum.any?(model.sources.entries, &(&1.id == "000-source-052"))
    assert length(model.bindings.entries) == 2
    refute model.bindings.has_next
    assert model.selected.source.id == "selected"

    assert {:ok, first, _} =
             Read.load(c.reader, @mission, "reader", %{"data_source_id" => "selected"})

    assert length(first.sources.entries) == 25 and first.sources.has_next
    assert length(first.bindings.entries) == 25 and first.bindings.has_next

    assert MapSet.disjoint?(
             MapSet.new(first.bindings.entries, & &1.id),
             MapSet.new(model.bindings.entries, & &1.id)
           )
  end

  test "immutable source and binding history is paged with exact identity and changed evidence",
       c do
    source = source("reviewed")
    binding = binding("reviewed-binding", source.data_source_id)
    params = %{"data_source_id" => source.data_source_id, "binding_id" => binding.binding_id}
    assert {:ok, before, review} = Read.load(c.admin, @mission, "settings", params)

    for n <- 1..27 do
      assert {:ok, _} =
               Definitions.persist_data_source(%{source | metadata: %{iteration: n}},
                 actor_id: "writer",
                 occurred_at: @time
               )

      assert {:ok, _} =
               Definitions.persist_data_binding(%{binding | priority: n},
                 actor_id: "writer",
                 occurred_at: @time
               )
    end

    assert {:ok, after_change, _} = Read.load(c.admin, @mission, "settings", params)
    refute before.selected.source.evidence == after_change.selected.source.evidence
    refute before.selected.binding.evidence == after_change.selected.binding.evidence
    assert Read.source_evidence(review.source) == before.selected.source.evidence
    assert after_change.selected.events.has_next
    assert after_change.selected.binding_events.has_next
    assert length(after_change.selected.events.entries) == 25

    assert {:ok, second, _} =
             Read.load(
               c.admin,
               @mission,
               "settings",
               Map.merge(params, %{"events_page" => "2", "binding_events_page" => "2"})
             )

    assert length(second.selected.events.entries) == 3
    assert length(second.selected.binding_events.entries) == 3
    refute second.selected.events.has_next

    assert MapSet.disjoint?(
             MapSet.new(after_change.selected.events.entries, & &1.id),
             MapSet.new(second.selected.events.entries, & &1.id)
           )

    assert Enum.any?(after_change.selected.events.entries, &(&1.actor_id == "writer"))
  end

  test "observed health and watermarks preserve source identity and timestamps without raw payloads",
       c do
    source("observed")

    for n <- 1..27 do
      attrs = %{
        organization_id: @org,
        mission_id: @mission,
        logical_source: :telemetry,
        data_source_id: "observed",
        source_binding_id: "observation-#{n}",
        realm: :backfill,
        dataset: "archive",
        observed_at: @time,
        reason: "private connection detail: token=secret",
        payload: %{secret_sentinel: "must-not-render"}
      }

      assert {:ok, _, _} =
               Health.record_source_health(Map.put(attrs, :source_health, :degraded),
                 invalidate_runtime_cache?: false
               )

      assert {:ok, _, _} =
               Watermarks.record_source_watermark(
                 Map.merge(attrs, %{
                   complete_through: @time,
                   confidence: :authoritative,
                   sample_count: n
                 }),
                 invalidate_runtime_cache?: false
               )
    end

    assert {:ok, model, _} =
             Read.load(c.reader, @mission, "reader", %{"data_source_id" => "observed"})

    assert length(model.selected.health.entries) == 25 and model.selected.health.has_next
    assert length(model.selected.watermarks.entries) == 25 and model.selected.watermarks.has_next

    assert Enum.all?(
             model.selected.health.entries,
             &(&1.state == "degraded" and &1.reason == "details_withheld")
           )

    assert Enum.all?(
             model.selected.watermarks.entries,
             &(&1.complete_through == DateTime.to_iso8601(@time))
           )

    assert {:ok, json} = JSONBoundary.safe_workflow_output(model)
    encoded = Jason.encode!(json)
    refute encoded =~ "must-not-render"
    refute encoded =~ "token=secret"

    assert {:ok, second, _} =
             Read.load(c.reader, @mission, "reader", %{
               "data_source_id" => "observed",
               "health_page" => "2",
               "watermarks_page" => "2",
               "health_events_page" => "2"
             })

    assert length(second.selected.health.entries) == 2
    assert length(second.selected.health_events.entries) == 2
    assert length(second.selected.watermarks.entries) == 2

    assert MapSet.disjoint?(
             MapSet.new(model.selected.health_events.entries, & &1.id),
             MapSet.new(second.selected.health_events.entries, & &1.id)
           )

    assert length(Cadence.Reads.DataSources.list_source_health_statuses(@org, @mission)) == 27
    assert length(Cadence.Reads.DataSources.list_source_watermark_statuses(@org, @mission)) == 27
  end

  test "exact event reads preserve domain values and organization and mission boundaries" do
    source("event-source")
    binding("event-binding", "event-source")
    [binding_event] = Definitions.list_data_binding_events("event-binding")

    attrs = %{
      organization_id: @org,
      mission_id: @mission,
      logical_source: :telemetry,
      data_source_id: "event-source",
      source_binding_id: "event-binding",
      realm: :flight,
      observed_at: @time
    }

    assert {:ok, health_event, _} =
             Health.record_source_health(Map.put(attrs, :source_health, :degraded),
               invalidate_runtime_cache?: false
             )

    assert {:ok, watermark_event, _} =
             Watermarks.record_source_watermark(
               Map.merge(attrs, %{
                 complete_through: @time,
                 confidence: :authoritative,
                 sample_count: 1
               }),
               invalidate_runtime_cache?: false
             )

    cases = [
      {&Cadence.Reads.DataSources.fetch_data_binding_event/3, binding_event,
       Cadence.Management.DataSources.Store.DataBindingEventRow, :data_binding_event_id,
       :data_binding_event_not_found},
      {&Cadence.Reads.DataSources.fetch_source_health_event/3, health_event, Health.EventRow,
       :source_health_event_id, :source_health_event_not_found},
      {&Cadence.Reads.DataSources.fetch_source_watermark_event/3, watermark_event,
       Watermarks.EventRow, :source_watermark_event_id, :source_watermark_event_not_found}
    ]

    for {fetch, event, row_module, id_field, missing} <- cases do
      id = Map.fetch!(event, id_field)
      assert {:ok, ^event} = fetch.(@org, @mission, id)
      refute Map.has_key?(event, :__meta__)
      assert {:error, ^missing} = fetch.("foreign-org", @mission, id)
      assert {:error, ^missing} = fetch.(@org, "foreign-mission", id)
      assert {:error, ^missing} = fetch.(@org, @mission, "missing-event")

      # Existing organization-neutral events remain visible only within their mission.
      assert {1, _} =
               Repo.update_all(from(row in row_module, where: field(row, ^id_field) == ^id),
                 set: [organization_id: nil]
               )

      neutral_event = %{event | organization_id: nil}
      assert {:ok, ^neutral_event} = fetch.(@org, @mission, id)
      assert {:ok, ^neutral_event} = fetch.("another-org", @mission, id)
      assert {:error, ^missing} = fetch.(@org, "foreign-mission", id)
    end
  end

  test "deployment source and payload scope are filtered before paging", c do
    source("job-source")

    for n <- 1..27,
        do:
          Jobs.enqueue(:tsdb_backend_lifecycle, @mission, "selected-run-#{n}", %{
            data_source_id: "job-source",
            organization_id: @org,
            mission_id: @mission,
            operation: "provision"
          })

    for n <- 1..35,
        do:
          Jobs.enqueue(:tsdb_backend_lifecycle, @mission, "unrelated-run-#{n}", %{
            data_source_id: "other-source",
            organization_id: @org
          })

    Jobs.enqueue(:tsdb_backend_lifecycle, @mission, "wrong-org", %{
      data_source_id: "job-source",
      organization_id: "foreign"
    })

    Jobs.enqueue(:tsdb_backend_lifecycle, @mission, "wrong-payload-mission", %{
      data_source_id: "job-source",
      mission_id: "foreign"
    })

    Jobs.enqueue(:replay_telemetry_scope, @mission, "wrong-type", %{data_source_id: "job-source"})

    assert {:ok, legacy} = Jobs.fetch_job_for_run(:tsdb_backend_lifecycle, "selected-run-1")

    Repo.update_all(from(row in BackgroundJobRow, where: row.job_id == ^legacy.job_id),
      set: [payload: legacy.payload]
    )

    assert {:ok, first, _} =
             Read.load(c.admin, @mission, "settings", %{"data_source_id" => "job-source"})

    assert length(first.selected.jobs.entries) == 25 and first.selected.jobs.has_next

    assert Enum.all?(
             first.selected.jobs.entries,
             &String.starts_with?(&1.run_id, "selected-run-")
           )

    assert {:ok, second, _} =
             Read.load(c.admin, @mission, "settings", %{
               "data_source_id" => "job-source",
               "jobs_page" => "2"
             })

    assert length(second.selected.jobs.entries) == 2
    refute second.selected.jobs.has_next
    [entry | _] = first.selected.jobs.entries
    assert {:ok, job} = Jobs.fetch_job(entry.id)
    assert entry.evidence == Read.job_evidence(job)
    assert Jobs.claim_jobs(100) != []
    assert {:ok, changed} = Jobs.fetch_job(entry.id)
    refute entry.evidence == Read.job_evidence(changed)
  end

  test "malformed queries, unrelated bindings and missing selected evidence fail closed", c do
    source("selected")
    source("different")
    binding("different-binding", "different")

    for query <- [
          %{"page" => "0"},
          %{"page" => "999999999999999999"},
          %{"organization_id" => "foreign"},
          %{"data_source_id" => ["selected"]}
        ] do
      assert {:error, :invalid_source_query} = Read.load(c.reader, @mission, "reader", query)
    end

    assert {:error, :source_required} = Read.load(c.admin, @mission, "settings", %{})

    assert {:error, :source_unavailable} =
             Read.load(c.reader, @mission, "reader", %{"data_source_id" => "missing"})

    assert {:error, :binding_unavailable} =
             Read.load(c.reader, @mission, "reader", %{
               "data_source_id" => "selected",
               "binding_id" => "different-binding"
             })

    assert {:error, :unexpected_source} =
             Read.load(c.admin, @mission, "registration", %{"data_source_id" => "selected"})
  end

  defp source(id, attrs \\ []) do
    value =
      struct!(
        %DataSource{
          data_source_id: id,
          organization_id: @org,
          mission_id: @mission,
          isolation_level: :mission_isolated,
          adapter: :telemetry
        },
        attrs
      )

    assert {:ok, source} = Definitions.persist_data_source(value)
    source
  end

  defp binding(id, source) do
    assert {:ok, binding} =
             Definitions.persist_data_binding(%DataBinding{
               binding_id: id,
               organization_id: @org,
               mission_id: @mission,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: source
             })

    binding
  end

  defp scope(org, role) do
    user =
      User.new(%{
        user_id: "source-user-#{role}",
        email: "#{role}@example.test",
        display_name: "Source operator"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: org.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization: org,
      organization_id: org.organization_id,
      organization_membership: membership
    })
  end
end
