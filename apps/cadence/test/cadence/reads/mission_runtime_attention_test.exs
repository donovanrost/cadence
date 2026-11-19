defmodule Cadence.Reads.MissionRuntimeAttentionTest do
  @moduledoc "2026-11-12: an unapplied active generation is a P1 attention item until applied."
  use ExUnit.Case, async: true

  alias Cadence.Control.MissionRuntimeStatus
  alias Cadence.Reads.MissionRuntimeAttention

  test "opens once not_applied, then resolves as applied when the runtime recovers" do
    mission = "mission-runtime-attention-#{System.unique_integer([:positive])}"
    failing_since = DateTime.add(DateTime.utc_now(), -120, :second)
    activated_at = DateTime.add(failing_since, -5, :second)
    activation = %{activated_at: activated_at, metadata: %{"change_set" => %{"id" => "cs-9"}}}

    :ok =
      MissionRuntimeStatus.record(
        state(mission,
          applied_generation: nil,
          last_error: {:mission_runtime_spec_mismatch, :binding_set_content_sha256},
          failing_since: failing_since
        ),
        activation
      )

    assert [item] = MissionRuntimeAttention.items("org", mission)

    assert %{
             id: ^mission,
             source: "mission_runtime",
             conflict: "generation_not_applied",
             reason: "spec_mismatch",
             desired_generation: 8,
             applied_generation: nil,
             since: ^failing_since,
             activated_at: ^activated_at,
             change_set_id: "cs-9",
             starts_at: nil,
             contact_id: nil
           } = item

    assert MissionRuntimeAttention.resolved_since("org", mission, failing_since) == []

    applied_at = DateTime.utc_now()

    :ok =
      MissionRuntimeStatus.record(
        state(mission, applied_generation: 8, applied_at: applied_at),
        nil
      )

    assert MissionRuntimeAttention.items("org", mission) == []

    assert [%{id: ^mission, action: "applied", resolved_by: %{"kind" => "system"}}] =
             MissionRuntimeAttention.resolved_since("org", mission, failing_since)

    assert %{open: 0, acknowledged: 0} = MissionRuntimeAttention.counts("org", mission)
  end

  test "a generation that applies without ever failing is not a resolution" do
    mission = "mission-runtime-attention-#{System.unique_integer([:positive])}"
    :ok = MissionRuntimeStatus.record(state(mission, applied_generation: 3), nil)

    assert MissionRuntimeAttention.items("org", mission) == []

    assert MissionRuntimeAttention.resolved_since(
             "org",
             mission,
             DateTime.add(DateTime.utc_now(), -60)
           ) == []
  end

  defp state(mission, fields) do
    Map.merge(
      %{
        mission_id: mission,
        desired_generation: 8,
        applied_generation: nil,
        last_error: nil,
        failing_since: nil,
        applied_at: nil
      },
      Map.new(fields)
    )
  end
end
