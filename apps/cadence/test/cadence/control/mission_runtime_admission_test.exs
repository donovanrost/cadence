defmodule Cadence.Control.MissionRuntimeAdmissionTest do
  @moduledoc """
  A runtime admission failure made loud (11-17 calibration incident; lead, director, U91). The
  reconciler held `{:mission_runtime_spec_mismatch, :binding_set_content_sha256}` from 14:04:18Z,
  retrying every 30 s, with nothing logged; U38's item appeared after the 60 s debounce, but no
  push told an open Now (pinned before this fix). Now: a push when the item becomes visible, a
  warning on the first failure and on a reason change (with the detail), an info on recovery, the
  item's `reason_detail` and `next_pass`, and per-mission generation gauges.
  """
  use Cadence.DataCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Contacts.{ContactStore, ScheduledContact}
  alias Cadence.Control.{MissionRuntimeGauges, MissionRuntimeStatus}
  alias Cadence.Control.MissionRuntimeReconciler.AdmissionLog
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Reads.MissionRuntimeAttention

  @spec_mismatch {:mission_runtime_spec_mismatch, :binding_set_content_sha256}

  setup do
    suffix = System.unique_integer([:positive])
    {org, mission} = {"org-admission-#{suffix}", "mission-admission-#{suffix}"}
    persist_mission_scope(org, mission)
    %{org: org, mission: mission}
  end

  test "the item is pushed when the 60 s debounce makes it visible, not only when it changes",
       c do
    :ok = ScopedReadUpdates.subscribe(:attention_changed, c.org, c.mission)
    state = failing(c.mission, DateTime.add(DateTime.utc_now(), -59_600, :millisecond))

    :ok = MissionRuntimeStatus.record(state, nil)
    assert_receive {:attention_changed, _, _}
    assert MissionRuntimeAttention.items(c.org, c.mission) == []

    Process.sleep(600)

    # The same failure at the next poll (or the reconciler's debounce check): now visible, and
    # announced (before the fix, nothing was).
    :ok = MissionRuntimeStatus.record(state, nil)
    assert_receive {:attention_changed, _, _}

    assert [
             %{
               reason: "spec_mismatch",
               reason_detail: "binding_set_content_sha256",
               next_pass: nil,
               desired_generation: 9
             }
           ] = MissionRuntimeAttention.items(c.org, c.mission)

    # A further identical poll says nothing.
    :ok = MissionRuntimeStatus.record(state, nil)
    refute_receive {:attention_changed, _, _}, 100
  end

  test "warns on the first failure and on a reason change, with the detail; info on recovery" do
    healthy = %{failing(nil, nil) | last_error: nil, applied_generation: 9}
    first = failing("mission-log", DateTime.utc_now())

    assert capture_log(fn ->
             AdmissionLog.transition(%{healthy | mission_id: "mission-log"}, first)
           end) =~
             ~r/Mission runtime for mission-log not admitted: generation 9 \(applied none\), reason spec_mismatch \(binding_set_content_sha256\)/

    refute capture_log(fn -> AdmissionLog.transition(first, first) end) =~
             "Mission runtime for mission-log"

    crashed = %{first | last_error: {:reconcile_crashed, "boom"}}

    assert capture_log(fn -> AdmissionLog.transition(first, crashed) end) =~
             "still not admitted, for a new reason: generation 9 (applied none), reason reconcile_crashed"

    recovered = %{crashed | last_error: nil, failing_since: nil, applied_generation: 9}

    # The test config logs warnings and up; AdmissionLog logs info here, for the recovery line.
    Logger.put_module_level(AdmissionLog, :info)

    assert capture_log([level: :info], fn -> AdmissionLog.transition(crashed, recovered) end) =~
             "Mission runtime for mission-log admitted generation 9 after"

    Logger.delete_module_level(AdmissionLog)
  end

  test "next_pass names the pass in progress, and says it didn't start", c do
    now = DateTime.utc_now()

    {:ok, contact} =
      ContactStore.persist_scheduled(
        ScheduledContact.new(%{
          scheduled_contact_id: "pass-#{System.unique_integer([:positive])}",
          organization_id: c.org,
          mission_id: c.mission,
          starts_at: DateTime.add(now, -120, :second),
          ends_at: DateTime.add(now, 480, :second),
          source_endpoint_refs: []
        })
      )

    :ok = MissionRuntimeStatus.record(failing(c.mission, DateTime.add(now, -90, :second)), nil)

    assert [%{next_pass: pass}] = MissionRuntimeAttention.items(c.org, c.mission)
    id = contact.scheduled_contact_id

    assert %{
             contact_id: ^id,
             spacecraft_id: nil,
             spacecraft_name: nil,
             station: nil,
             in_progress: true,
             started: false
           } = pass
  end

  test "gauges: per active mission, desired vs applied (0 when none) and admitted", c do
    {:ok, activation} =
      Cadence.Activations.record_binding_set_activation(c.org, c.mission, "gauge-binding", 1,
        binding_set_content_sha256: String.duplicate("0", 64)
      )

    desired = activation.generation
    assert %{desired: ^desired, applied: 0, admitted: 0} = gauge(c.mission)

    :ok =
      MissionRuntimeStatus.record(
        %{failing(c.mission, nil) | last_error: nil, applied_generation: desired},
        nil
      )

    assert %{desired: ^desired, applied: ^desired, admitted: 1} = gauge(c.mission)
  end

  defp gauge(mission), do: Enum.find(MissionRuntimeGauges.read(), &(&1.mission_id == mission))

  defp failing(mission, since) do
    %{
      mission_id: mission,
      desired_generation: 9,
      applied_generation: nil,
      last_error: @spec_mismatch,
      failing_since: since,
      applied_at: nil,
      safety_poll_interval_ms: 30_000
    }
  end
end
