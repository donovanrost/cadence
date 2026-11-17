defmodule Cadence.Contacts.ReplayConflictAttentionTest do
  # #99 follow-up / ux U84 'Stuck processing': the attention source over the durable records.
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Contacts.ReplayConflictAttention
  alias Cadence.Reads.ActionQueue.AttentionItems
  alias Cadence.Runtime.ReplayConflicts
  alias Cadence.Runtime.ReplayConflicts.Recorder

  setup do
    id = Integer.to_string(System.unique_integer([:positive]))
    %{organization_id: "org-rc-" <> id, mission_id: "mission-rc-" <> id}
  end

  defp trip(unit, kind \\ :alarm_event, effect \\ "aev_1"),
    do: Recorder.track({:error, {:replay_id_conflict, kind, effect}}, unit, :clear)

  defp stream(ctx, path \\ :storage),
    do: Recorder.stream_unit(path, ctx.mission_id, "contact-1", "path-1", "binding-1")

  defp items(ctx), do: ReplayConflictAttention.items(ctx.organization_id, ctx.mission_id)

  defp operator(ctx) do
    persist_mission_scope(ctx.organization_id, ctx.mission_id)
    TelemetryDecomFixtures.user_scope(ctx.organization_id, "op")
  end

  test "one item per stalled unit, in the agreed shape", ctx do
    trip(stream(ctx))
    trip(stream(ctx), :alarm_episode, "aep_2")
    trip(stream(ctx), :alarm_episode, "aep_2")

    trip(
      Recorder.partition_unit(ctx.mission_id, "source_endpoint:a", "starting"),
      :managed_action_request,
      "mar_1"
    )

    assert [storage, timer] = items(ctx)

    assert %{
             source: "replay_conflict",
             conflict: "replay_id_conflict",
             state: "open",
             path: "storage",
             effect_kind: "alarm_effect",
             effect_id: "aev_1",
             effect_count: 2,
             occurrences: 3,
             partition_id: nil,
             partition_stopped: false,
             realized_contact_id: "contact-1",
             path_id: "path-1",
             stream_key: "contact-1:path-1:binding-1",
             buffer: nil,
             dropping: false,
             reraised: false
           } = storage

    assert %{
             path: "timer",
             effect_kind: "managed_action_request",
             partition_id: "source_endpoint:a",
             partition_stopped: true,
             stopped_while: "starting",
             realized_contact_id: nil,
             stream_key: nil,
             spacecraft_ids: [],
             spacecraft_count: 0
           } = timer

    assert ReplayConflictAttention.counts(ctx.organization_id, ctx.mission_id) == %{
             open: 2,
             acknowledged: 0
           }
  end

  test "on the wire: buffer (not journal), spacecraft refs, no pass on a timer, critical while dropping",
       ctx do
    trip(Recorder.partition_unit(ctx.mission_id, "source_endpoint:a"))
    trip(stream(ctx))
    [stream_row] = Enum.filter(ReplayConflicts.open(ctx.mission_id), & &1.stream_key)

    Recorder.put_buffer(stream_row.id, %{
      buffer_retained_bytes: 8_000,
      buffer_max_bytes: 8_000,
      dropping_since: DateTime.utc_now()
    })

    [timer, storage] = items(ctx) |> Enum.sort_by(& &1.path, :desc)
    names = AttentionItems.lookups(ctx.organization_id, ctx.mission_id, [timer, storage])
    wire = AttentionItems.object(storage, names)

    assert %{buffer: %{used_bytes: 8_000, max_bytes: 8_000}, dropping: true} = wire
    refute Map.has_key?(wire, :journal)
    # Its contact has no booking here: no pass to label, so contact is null, not a half object.
    assert %{affected_spacecraft: [], contact: nil} = wire

    assert %{contact: nil, affected_spacecraft: [], buffer: nil} =
             AttentionItems.object(timer, names)

    assert {1, _due} = AttentionItems.rank(storage, DateTime.utc_now())
    assert {2, _due} = AttentionItems.rank(timer, DateTime.utc_now())
  end

  test "acknowledge takes an optional note, newest only; a bad note is refused", ctx do
    scope = operator(ctx)
    trip(stream(ctx))
    [%{id: id}] = items(ctx)

    assert {:error, :invalid_note} =
             ReplayConflictAttention.acknowledge(
               scope,
               ctx.mission_id,
               id,
               String.duplicate("x", 501)
             )

    assert {:error, :invalid_note} =
             ReplayConflictAttention.acknowledge(scope, ctx.mission_id, id, 7)

    assert {:ok, %{state: "acknowledged", acknowledged_note: "told domain at 03:18Z"} = item} =
             ReplayConflictAttention.acknowledge(
               scope,
               ctx.mission_id,
               id,
               " told domain at 03:18Z "
             )

    assert %{"kind" => "user", "id" => _} = item.acknowledged_by

    assert {:ok, %{acknowledged_note: nil}} =
             ReplayConflictAttention.acknowledge(scope, ctx.mission_id, id)

    assert ReplayConflictAttention.counts(ctx.organization_id, ctx.mission_id) == %{
             open: 0,
             acknowledged: 1
           }

    assert {:error, :attention_item_not_found} =
             ReplayConflictAttention.acknowledge(
               scope,
               ctx.mission_id,
               "replay_id_conflict_missing"
             )

    assert {:error, :attention_item_not_found} =
             ReplayConflictAttention.resolve(scope, ctx.mission_id, id, "fixed")
  end

  test "dropping after the acknowledgement re-raises it, keeping the earlier ack", ctx do
    scope = operator(ctx)
    trip(stream(ctx))
    [%{id: id}] = items(ctx)
    {:ok, acked} = ReplayConflictAttention.acknowledge(scope, ctx.mission_id, id, "told domain")

    # New telemetry started being lost just after the acknowledgement.
    Recorder.put_buffer(id, %{
      dropping_since: DateTime.add(acked.acknowledged_at, 1, :millisecond)
    })

    Process.sleep(5)

    assert [%{state: "open", reraised: true, acknowledged_note: "told domain", dropping: true}] =
             items(ctx)

    {:ok, %{state: "acknowledged", reraised: false}} =
      ReplayConflictAttention.acknowledge(scope, ctx.mission_id, id, "told domain again")
  end

  test "a resolved unit fades out as resumed by the system", ctx do
    since = DateTime.utc_now()
    trip(stream(ctx))
    [%{id: id}] = items(ctx)
    Recorder.track(:ok, stream(ctx), :open)

    assert items(ctx) == []

    assert [
             %{
               id: ^id,
               path: "storage",
               action: "resumed",
               resolved_by: %{kind: "system", id: nil, name: nil},
               resolved_at: %DateTime{}
             }
           ] = ReplayConflictAttention.resolved_since(ctx.organization_id, ctx.mission_id, since)
  end
end
