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
    # #390: the shared monitor also ticks every 5 s; a tick before the append would make this
    # first reading 'rising'. Two samples at the same fill are never rising, whenever it ticked.
    # `rising` itself is pinned against an own monitor below.
    :ok = BackpressureMonitor.sample_now()
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

    # P1 from the fill alone (no live pass here). Whether it reads rising depends on whether the
    # shared monitor ticked between the append and this sample (#390), so it isn't asserted here.
    assert [%{journal_usage: %{ratio: ratio}, p1: true}] =
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

  # #390: `rising` against a monitor of the test's own (its own namespace, an hour between ticks),
  # so only sample_now samples and the shared monitor's 5 s tick can't land in between.
  @tag :tmp_dir
  test "rising: only while the fill grew since the previous sample", ctx do
    namespace = own_monitor!()
    journal = start_journal!(ctx, namespace)

    append!(journal, 82_000)
    :ok = BackpressureMonitor.sample_now(namespace)
    # The first sample has nothing to compare with.
    assert %{rising: false, ratio: first} = usage(ctx, namespace)
    assert first >= 0.8

    append!(journal, 14_000)
    :ok = BackpressureMonitor.sample_now(namespace)
    assert %{rising: true, ratio: grown} = usage(ctx, namespace)
    assert grown > first

    # Unchanged fill: not rising. #393: a fill whose ratio rounds down (96_415 -> 0.9641) once read
    # 'rising' forever (the exact ratio was compared with the rounded one). Make sure this fill
    # rounds down (domain), so the step keeps covering that whatever the journal's overhead.
    steady = rounds_down!(journal, ctx, namespace)
    assert steady.used_bytes / steady.capacity_bytes > steady.ratio
    assert steady.ratio >= grown

    :ok = BackpressureMonitor.sample_now(namespace)
    assert %{rising: false, ratio: ratio} = usage(ctx, namespace)
    assert ratio == steady.ratio
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

  defp own_monitor! do
    namespace =
      ProcessNamespace.new!(
        root_supervisor: __MODULE__.Root,
        registry: __MODULE__.Registry,
        mission_supervisor: __MODULE__.Missions,
        capability_registry: __MODULE__.Capabilities
      )

    start_supervised!({Registry, keys: :unique, name: __MODULE__.Registry})

    monitor =
      start_supervised!(
        {BackpressureMonitor, process_namespace: namespace, interval_ms: 3_600_000}
      )

    # The monitor doesn't trap exits, so its terminate/2 (which detaches) doesn't run when the
    # test stops it; detach here so no handler outlives the test (devops).
    on_exit(fn -> :telemetry.detach({BackpressureMonitor, monitor}) end)

    namespace
  end

  # Grows the fill one small append at a time (1 byte plus the journal's framing), sampling each
  # time, until its exact ratio is above the stored, rounded one; most fills already are. The
  # caller asserts on the ratio the monitor actually stored (domain).
  defp rounds_down!(journal, ctx, namespace, tries \\ 20) do
    usage = usage(ctx, namespace)

    cond do
      usage.used_bytes / usage.capacity_bytes > usage.ratio ->
        usage

      tries == 0 ->
        flunk("no fill that rounds down after 20 one-byte appends")

      true ->
        append!(journal, 1)
        :ok = BackpressureMonitor.sample_now(namespace)
        rounds_down!(journal, ctx, namespace, tries - 1)
    end
  end

  defp usage(ctx, namespace) do
    assert [usage] = BackpressureMonitor.snapshot(ctx.mission_id, namespace).near_full
    usage
  end

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

  defp start_journal!(%{tmp_dir: tmp_dir} = ctx, namespace \\ ProcessNamespace.default()) do
    key = journal_key(ctx)

    start_supervised!(
      Supervisor.child_spec(
        {IngressJournal,
         name: ProcessNamespace.via(namespace, key),
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

    ProcessNamespace.via(namespace, key)
  end

  defp append!(journal, bytes) do
    {:ok, _entry} =
      IngressJournal.append(journal, :binary.copy(<<0>>, bytes), DateTime.utc_now(), %{})
  end
end
