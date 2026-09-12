defmodule Cadence.Applications.HistoricalWorkflowRequestTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.HistoricalWorkflowRequest
  alias Cadence.Applications.OpsConsole.Actions.MissionOperations
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources.Store
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow

  @workflow_keys ~w(workflow run_id realm data_source_id source_binding_id observable_id point_id point_ids source_from source_to dashboard_id dashboard_version dashboard_time_mode dashboard_replay_run_id dashboard_data_view dashboard_limit_mode comparison_review_request_event_id comparison_review_request_kind comparison_review_open_count comparison_review_open_placement_ids comparison_review_workflow_kind comparison_review_workflow_action comparison_review_workflow_selection_kind comparison_review_workflow_selection_count comparison_review_primary_data_view comparison_review_compare_data_view comparison_review_scope_kind comparison_review_scope_ids comparison_review_contact_ids comparison_review_resource_ids comparison_review_transport_ids comparison_review_source_endpoint_ids comparison_review_ground_station_ids comparison_review_scope_link_ids reason confirmed)

  setup do
    persist_mission_scope("org-one", "mission-one")
    persist_mission_scope("org-one", "other-mission")
    persist_mission_scope("foreign", "foreign-mission")

    assert {:ok, source} =
             Store.persist_data_source(%DataSource{
               data_source_id: "source-one",
               organization_id: "org-one",
               mission_id: "mission-one",
               isolation_level: :mission_isolated,
               adapter: Cadence.Dashboards.Sources.Telemetry
             })

    assert {:ok, binding} =
             Store.persist_data_binding(%DataBinding{
               binding_id: "binding-one",
               organization_id: "org-one",
               mission_id: "mission-one",
               data_source_id: source.data_source_id,
               realm: :backfill,
               logical_source: :telemetry
             })

    %{source: source, binding: binding}
  end

  test "validation normalizes exact UTC instants and captures authoritative actor and source identity without writes" do
    values =
      values()
      |> Map.put("source_from", "2026-09-08T08:00:17-06:00")
      |> Map.put("reason", String.duplicate("界", 600))

    assert {:ok, request} = HistoricalWorkflowRequest.validate(scope(), "mission-one", values)
    assert request.workflow == :backfill
    assert request.point_ids == ["HK.temp", "HK.rate"]
    assert request.attrs.source_from == ~U[2026-09-08 14:00:17Z]
    assert request.attrs.reason == String.duplicate("界", 600)
    assert request.attrs.actor_id == "service-one"
    assert request.attrs.organization_id == "org-one"
    assert request.attrs.binding_id == "binding-one"
    assert Repo.aggregate(EventRow, :count) == 0
  end

  test "validation rejects unsupported workflows, malformed times, reversed ranges and invalid UTF8" do
    for {patch, field, code} <- [
          {%{"workflow" => "delete"}, "workflow", "unsupported"},
          {%{"source_from" => "2026-09-08T14:00"}, "source_from", "invalid_timestamp"},
          {%{"source_to" => "2026-09-08T13:00:00Z"}, "source_to", "must_follow_start"},
          {%{"reason" => <<255>>}, "request", "invalid"},
          {%{"reason" => String.duplicate("界", 1_400)}, "reason", "too_large"}
        ] do
      assert {:error, [%{field: ^field, code: ^code}]} =
               HistoricalWorkflowRequest.validate(
                 scope(),
                 "mission-one",
                 Map.merge(values(), patch)
               )
    end

    assert Repo.aggregate(EventRow, :count) == 0
  end

  test "foreign and disabled source/binding contexts are unavailable", %{
    source: source,
    binding: binding
  } do
    assert {:error, _} = HistoricalWorkflowRequest.validate(scope(), "other-mission", values())

    for updated <- [
          %{source | organization_id: "foreign", mission_id: "foreign-mission"},
          %{source | status: :disabled}
        ] do
      assert {:ok, _} = Store.persist_data_source(updated)

      assert {:error, [%{field: "data_source_id", code: "unavailable"}]} =
               HistoricalWorkflowRequest.validate(scope(), "mission-one", values())
    end

    assert {:ok, _} = Store.persist_data_source(source)

    for updated <- [
          %{binding | mission_id: "other-mission"},
          %{binding | status: :disabled},
          %{binding | realm: :flight},
          %{binding | logical_source: :events},
          %{binding | active_to: ~U[2020-01-01 00:00:00Z]}
        ] do
      assert {:ok, _} = Store.persist_data_binding(updated)

      assert {:error, [%{field: "source_binding_id", code: "unavailable"}]} =
               HistoricalWorkflowRequest.validate(scope(), "mission-one", values())
    end

    assert Repo.aggregate(EventRow, :count) == 0
  end

  test "compatibility validation and submission share preflight and only confirmed valid input records requests" do
    assert {:ok, %{"valid" => true, "errors" => []}} = execute("validate-request", values())
    assert Repo.aggregate(EventRow, :count) == 0

    assert {:error, :confirmation_required} =
             execute(
               "record-historical-workflow-request",
               Map.put(values(), "confirmed", "false")
             )

    assert {:ok, %{"valid" => false}} =
             execute("validate-request", Map.put(values(), "source_binding_id", "foreign"))

    assert {:error, [%{field: "source_binding_id"}]} =
             execute(
               "record-historical-workflow-request",
               Map.put(values(), "source_binding_id", "foreign")
             )

    assert Repo.aggregate(EventRow, :count) == 0
    assert {:ok, %{"eventIds" => ids}} = execute("record-historical-workflow-request", values())
    assert length(ids) == 2
    events = Repo.all(from(row in EventRow, order_by: row.point_id))
    assert Enum.sort(Enum.map(events, & &1.backfill_lifecycle_event_id)) == Enum.sort(ids)
    assert Enum.map(events, & &1.point_id) == ["HK.rate", "HK.temp"]

    assert Enum.all?(
             events,
             &(&1.actor_id == "service-one" and &1.organization_id == "org-one" and
                 &1.mission_id == "mission-one")
           )
  end

  defp execute(action, values) do
    all_values = Map.merge(Map.new(@workflow_keys, &{&1, ""}), values)

    MissionOperations.execute(scope(), HostContext.mission("mission-one"), %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "data_operations",
      surface_version: 1,
      action_id: action,
      params: %{"historical_workflow_request" => all_values}
    })
  end

  defp values,
    do: %{
      "workflow" => "backfill",
      "run_id" => "request-one",
      "realm" => "backfill",
      "data_source_id" => "source-one",
      "source_binding_id" => "binding-one",
      "point_ids" => "HK.temp, HK.rate, HK.temp",
      "source_from" => "2026-09-08T14:00:17Z",
      "source_to" => "2026-09-08T15:00:23Z",
      "reason" => "Fill the gap",
      "confirmed" => "true"
    }

  defp scope do
    %Scope{
      actor_kind: :service,
      organization_id: "org-one",
      mission_id: "mission-one",
      capabilities: MapSet.new(),
      service_identity: %ServiceIdentity{
        service_identity_id: "service-one",
        organization_id: "org-one",
        mission_id: "mission-one",
        display_name: "Service",
        lifecycle_state: :active
      }
    }
  end
end
