defmodule Cadence.Contacts.IngressBackpressureAttentionTest do
  @moduledoc "The ingress_backpressure attention source (DECISIONS #83, ux U47)."
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Contacts.IngressBackpressureAttention, as: BackpressureAttention
  alias Cadence.Ingress.ReceiveBackpressure
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Reads.ActionQueue.AttentionItems
  alias Cadence.Runtime.IngressBackpressureMonitor, as: BackpressureMonitor
  alias Cadence.Runtime.ProcessNamespace

  setup do
    id = Integer.to_string(System.unique_integer([:positive]))

    %{
      organization_id: "org-bp-" <> id,
      mission_id: "mission-bp-" <> id,
      contact_id: "contact-bp-" <> id,
      binding_id: "binding-bp-" <> id
    }
  end

  @tag :tmp_dir
  test "a filling buffer opens at 80%, says when it's rising, and clears itself when it drains",
       ctx do
    journal = start_journal!(ctx)

    append!(journal, 82_000)
    :ok = BackpressureMonitor.sample_now()

    assert [%{conflict: "journal_near_full", state: "open"} = item] =
             BackpressureAttention.items(ctx.organization_id, ctx.mission_id)

    assert item.id == "journal_near_full:#{ctx.contact_id}:#{ctx.binding_id}"
    assert item.journal_usage.ratio >= 0.8 and item.journal_usage.ratio < 0.95
    assert item.journal_usage.capacity_bytes == 100_000
    assert item.journal_usage.rising == false
    assert item.drops == nil
    assert item.transport.provider_binding_id == ctx.binding_id
    refute item.p1

    append!(journal, 14_000)
    :ok = BackpressureMonitor.sample_now()

    assert [%{journal_usage: %{rising: true, ratio: ratio}, p1: true}] =
             BackpressureAttention.items(ctx.organization_id, ctx.mission_id)

    assert ratio >= 0.95

    assert %{open: 1, acknowledged: 0} =
             BackpressureAttention.counts(ctx.organization_id, ctx.mission_id)

    # Not acknowledgeable: it clears itself.
    scope = operator(ctx)

    assert {:error, :attention_item_not_found} =
             BackpressureAttention.acknowledge(scope, ctx.mission_id, item.id)

    # The contact ends: its journal goes away, and the item resolves as drained.
    stop_supervised!(:journal)
    :ok = BackpressureMonitor.sample_now()

    assert [] == BackpressureAttention.items(ctx.organization_id, ctx.mission_id)

    assert [%{id: id, action: "drained", resolved_by: %{"kind" => "system"}}] =
             BackpressureAttention.resolved_since(
               ctx.organization_id,
               ctx.mission_id,
               DateTime.add(DateTime.utc_now(), -60)
             )

    assert id == item.id
  end

  # qa's restart 1 dry run: a journal that has stopped can still be listed by the registry for a
  # moment (its entry is removed asynchronously). Holding the registry's partitions pins that
  # window: the stopped journal counts as gone, and its item clears as drained.
  @tag :tmp_dir
  test "a stopped journal the registry still lists clears its item", ctx do
    journal = start_journal!(ctx)
    append!(journal, 85_000)
    :ok = BackpressureMonitor.sample_now()
    assert [%{conflict: "journal_near_full"}] = items(ctx)

    partitions = registry_partitions()
    Enum.each(partitions, &:sys.suspend/1)
    on_exit(fn -> Enum.each(partitions, &resume/1) end)

    stop_supervised!(:journal)
    assert [_still_listed] = Registry.lookup(Cadence.Runtime.Registry, journal_key(ctx))

    :ok = BackpressureMonitor.sample_now()
    Enum.each(partitions, &resume/1)

    assert [] == items(ctx)

    assert [%{action: "drained"}] =
             BackpressureAttention.resolved_since(
               ctx.organization_id,
               ctx.mission_id,
               DateTime.add(DateTime.utc_now(), -60)
             )
  end

  test "dropped frames stay until acknowledged, then resolve once the contact has ended", ctx do
    for _drop <- 1..3 do
      ReceiveBackpressure.on_full(false, drop_metadata(ctx), 48)
    end

    :ok = BackpressureMonitor.sample_now()

    assert [%{conflict: "frames_dropped", state: "open"} = item] =
             BackpressureAttention.items(ctx.organization_id, ctx.mission_id)

    assert %{count: 3, bytes: 144, buffer: "executor"} = item.drops
    assert item.journal_usage == nil

    scope = operator(ctx)
    assert {:ok, acknowledged} = BackpressureAttention.acknowledge(scope, ctx.mission_id, item.id)
    assert acknowledged.state == "acknowledged"
    assert acknowledged.acknowledged_by["id"] == scope.user.user_id

    # A second acknowledgement finds nothing to acknowledge.
    assert {:error, :attention_item_not_found} =
             BackpressureAttention.acknowledge(scope, ctx.mission_id, item.id)

    # No runtime is running for this contact, so the next sample resolves it.
    :ok = BackpressureMonitor.sample_now()
    assert [] == BackpressureAttention.items(ctx.organization_id, ctx.mission_id)

    assert [%{action: "acknowledged", resolved_by: %{"kind" => "user"}}] =
             BackpressureAttention.resolved_since(
               ctx.organization_id,
               ctx.mission_id,
               DateTime.add(DateTime.utc_now(), -60)
             )
  end

  test "the action queue object carries the shared fields and the source's own", ctx do
    ReceiveBackpressure.on_full(false, drop_metadata(ctx), 10)
    :ok = BackpressureMonitor.sample_now()

    [item] = BackpressureAttention.items(ctx.organization_id, ctx.mission_id)
    names = AttentionItems.lookups(ctx.organization_id, ctx.mission_id, [item])
    object = AttentionItems.object(item, names)

    for key <- [:station, :provider, :starts_at, :provider_message, :resolution, :reservation_id] do
      assert Map.has_key?(object, key), "missing shared field #{key}"
    end

    for key <- [:transport, :journal_usage, :drops, :diagnostics, :contact_label, :ends_at] do
      assert Map.has_key?(object, key), "missing source field #{key}"
    end

    refute Map.has_key?(object, :p1)
  end

  defp operator(ctx) do
    persist_mission_scope(ctx.organization_id, ctx.mission_id)
    TelemetryDecomFixtures.user_scope(ctx.organization_id, "op")
  end

  defp drop_metadata(ctx) do
    %{
      mission_id: ctx.mission_id,
      realized_contact_id: ctx.contact_id,
      provider_binding_id: ctx.binding_id,
      buffer: :executor
    }
  end

  defp items(ctx), do: BackpressureAttention.items(ctx.organization_id, ctx.mission_id)

  defp journal_key(ctx),
    do: {:provider_ingress_journal, ctx.mission_id, ctx.contact_id, "path-bp", ctx.binding_id}

  defp registry_partitions do
    for {_id, pid, _type, [Registry.Partition]} <-
          Supervisor.which_children(Cadence.Runtime.Registry),
        is_pid(pid),
        do: pid
  end

  defp resume(pid) do
    :sys.resume(pid)
  catch
    # Already resumed, or the partition is gone.
    :exit, _reason -> :ok
  end

  defp start_journal!(%{tmp_dir: tmp_dir} = ctx) do
    key = journal_key(ctx)

    start_supervised!(
      Supervisor.child_spec(
        {IngressJournal,
         name: ProcessNamespace.via(ProcessNamespace.default(), key),
         mission_id: ctx.mission_id,
         realized_contact_id: ctx.contact_id,
         path_id: "path-bp",
         provider_binding_id: ctx.binding_id,
         base_path: tmp_dir,
         durability: :page_cache,
         max_bytes: 100_000,
         segment_bytes: 200_000,
         checkpoint_interval_ms: 60_000},
        id: :journal
      )
    )

    ProcessNamespace.via(ProcessNamespace.default(), key)
  end

  defp append!(journal, bytes) do
    {:ok, _entry} =
      IngressJournal.append(journal, :binary.copy(<<0>>, bytes), DateTime.utc_now(), %{})
  end
end
