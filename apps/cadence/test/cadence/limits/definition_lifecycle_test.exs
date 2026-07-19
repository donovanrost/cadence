defmodule Cadence.Limits.DefinitionLifecycleTest do
  use Cadence.DataCase, async: false

  alias Cadence.Limits
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Limits.DefinitionLifecycle

  @organization_id "org-limit-lifecycle"
  @mission_id "mission-limit-lifecycle"

  test "persisted limit definitions write lifecycle events and active projection" do
    persist_mission_scope(@organization_id, @mission_id)

    first_definition = limit_definition(version: 1, yellow_high: 10)
    replacement_definition = limit_definition(version: 2, yellow_high: 20)

    assert {:ok, ^first_definition} = Cadence.persist_limit_definition(first_definition)
    assert {:ok, ^first_definition} = Cadence.persist_limit_definition(first_definition)

    assert {:ok, ^replacement_definition} =
             Cadence.persist_limit_definition(replacement_definition)

    events =
      DefinitionLifecycle.list_definition_lifecycle_events(@organization_id, @mission_id,
        point_id: "HK.counter"
      )

    assert Enum.map(events, & &1.event_type) == [:activated, :registered]

    activated_event = hd(events)

    assert {:ok, ^activated_event} =
             DefinitionLifecycle.fetch_definition_lifecycle_event(
               @organization_id,
               @mission_id,
               activated_event.limit_definition_lifecycle_event_id
             )

    assert {:ok, ^activated_event} =
             DefinitionLifecycle.fetch_latest_definition_lifecycle_event(
               @organization_id,
               @mission_id,
               activated_event.definition_activation_key
             )

    assert [operational_event] =
             Cadence.OperationalEvents.list_events(
               @organization_id,
               @mission_id,
               category: :limits,
               kind: :limit_definition_activated,
               source_record_kind: :limit_definition_lifecycle_event,
               source_record_id: activated_event.limit_definition_lifecycle_event_id
             )

    assert operational_event.event_id ==
             "operational_event:limit_definition_lifecycle_event:#{activated_event.limit_definition_lifecycle_event_id}"

    assert operational_event.subject == %{kind: :limit_definition, id: "counter-limits"}
    assert operational_event.effective_at == activated_event.active_from
    assert operational_event.causality.source_record_kind == :limit_definition_lifecycle_event

    assert operational_event.causality.source_record_id ==
             activated_event.limit_definition_lifecycle_event_id

    assert operational_event.payload["point_id"] == "HK.counter"
    assert operational_event.payload["limit_set_name"] == "ops"
    assert operational_event.payload["limit_definition_id"] == "counter-limits"
    assert operational_event.payload["limit_definition_version"] == 2
    assert operational_event.current["limit_definition_version"] == 2

    assert [active_status] =
             DefinitionLifecycle.list_active_statuses(@organization_id, @mission_id,
               point_id: "HK.counter"
             )

    assert active_status.limit_definition_id == "counter-limits"
    assert active_status.limit_definition_version == 2
    assert active_status.previous_limit_definition_id == "counter-limits"
    assert active_status.previous_limit_definition_version == 1
    assert active_status.transition_count == 2

    assert [active_definition] =
             DefinitionLifecycle.list_active_definitions(@organization_id, @mission_id, [])

    assert active_definition.version == 2

    assert active_definition.metadata["limit_activation_event_id"] ==
             active_status.limit_definition_lifecycle_event_id

    assert {:ok, [limit_event]} =
             Limits.evaluate_source_samples([source_sample(25)], [active_definition])

    assert limit_event.limit_definition_version == 2

    assert limit_event.provenance["limit_activation_event_id"] ==
             active_status.limit_definition_lifecycle_event_id

    assert limit_event.provenance["definition_activation_key"] ==
             active_status.definition_activation_key
  end

  defp limit_definition(opts) do
    LimitDefinition.new(%{
      mission_id: @mission_id,
      limit_definition_id: "counter-limits",
      point_id: "HK.counter",
      version: Keyword.fetch!(opts, :version),
      limit_set_name: "ops",
      thresholds: %{"yellow_high" => Keyword.fetch!(opts, :yellow_high)}
    })
  end

  defp source_sample(value) do
    %{
      source_sample_type: :telemetry_sample,
      sample_id: "sample-counter-1",
      mission_id: @mission_id,
      spacecraft_id: nil,
      point_id: "HK.counter",
      point_name: "HK.counter",
      value: value,
      generation_time: ~U[2026-06-21 12:00:00Z],
      receipt_time: ~U[2026-06-21 12:00:01Z],
      provenance: %{}
    }
  end
end
