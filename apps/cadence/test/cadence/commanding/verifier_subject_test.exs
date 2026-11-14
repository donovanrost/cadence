defmodule Cadence.Commanding.VerifierSubjectTest do
  @moduledoc """
  A mission-model verifier names its parameter's semantic id; decom samples carry it in
  `semantic_id` (P9CS on EARENDIL-001, 11-14: 'Mode applied' timed out although every sample in
  its window read SCIENCE). Samples and windows below are that pass's.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.Command.Compiler.VerifierPlan
  alias Cadence.Catalog.Command.MatchCriteria

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance,
    ReleaseArtifacts,
    VerifierEvaluation,
    VerifierWorkflow
  }

  alias Cadence.Telemetry.Sample

  @organization_id "org-verifier-subject"
  @mission_id "mission-verifier-subject"
  @spacecraft_id "spacecraft-earendil-001"
  @mode_parameter "semantic:parameter:09d9d79c3edb2d7b9c44164db362009b8b007a41273992ad01a951a86dfd910b"
  @released_at ~U[2026-11-14 00:35:05.169827Z]
  @ids %{
    mission_id: @mission_id,
    source_endpoint_ref: "endpoint-001-uplink",
    mission_model_revision_id: "revision-earendil",
    command_id: "command:set_mode",
    command_request_id: "request-p9cs",
    command_queue_entry_id: "entry-p9cs",
    queue_lane_key: "lane",
    realized_contact_id: "contact-39GI9"
  }

  describe "a semantic-parameter subject" do
    test "matches the first in-window sample whose semantic id it names (tonight's P9CS)" do
      verifier = mode_applied(@mode_parameter)

      # The session-start burst (stamped 00:35:01.302857Z, some of it SCIENCE) came before the
      # release: with no plan delay the window opens at the release, so it never verifies.
      assert verifier.delay_until == @released_at
      backlog = sample("backlog", ~U[2026-11-14 00:35:01.302857Z], 4)
      assert VerifierEvaluation.evaluate_samples(verifier, [backlog]) == nil

      applied = sample("applied", ~U[2026-11-14 00:35:09.751692Z], 4)

      assert %CommandVerifierInstance{
               lifecycle_state: :satisfied,
               matched_record_kind: :telemetry_sample,
               matched_record_id: "sample-applied",
               matched_at: ~U[2026-11-14 00:35:09.751692Z]
             } = VerifierEvaluation.evaluate_samples(verifier, [backlog, applied])
    end

    test "another parameter's semantic id doesn't match; the verifier then times out" do
      verifier = mode_applied("semantic:parameter:other")

      in_window = sample("applied", ~U[2026-11-14 00:35:09.751692Z], 4)
      assert VerifierEvaluation.evaluate_samples(verifier, [in_window]) == nil

      late = sample("late", ~U[2026-11-14 00:36:06Z], 4)

      assert %CommandVerifierInstance{lifecycle_state: :timed_out, matched_record_id: nil} =
               VerifierEvaluation.evaluate_samples(verifier, [in_window, late])
    end

    test "the commanded value still decides: SAFE (2) in the window doesn't satisfy SCIENCE (4)" do
      verifier = mode_applied(@mode_parameter)

      assert VerifierEvaluation.evaluate_samples(verifier, [
               sample("safe", ~U[2026-11-14 00:35:09.751692Z], 2)
             ]) == nil
    end

    test "a point subject still matches, with or without the telemetry: prefix" do
      for subject <- ["telemetry:HK.sc_mode", "HK.sc_mode"] do
        assert %CommandVerifierInstance{lifecycle_state: :satisfied} =
                 VerifierEvaluation.evaluate_samples(mode_applied(subject), [
                   sample("applied", ~U[2026-11-14 00:35:09.751692Z], 4)
                 ])
      end
    end
  end

  describe "the workflow (#38)" do
    setup do
      persist_mission_scope(@organization_id, @mission_id)
      :ok
    end

    test "another spacecraft's sample of the same parameter verifies nothing" do
      verifier = mode_applied(@mode_parameter)
      fetch_pending = fn @organization_id, @mission_id -> [{:entry, verifier}] end
      persist = fn updates -> {:ok, Enum.map(updates, &elem(&1, 1))} end

      spacecraft_of = fn @organization_id, @mission_id, "endpoint-001-uplink" ->
        @spacecraft_id
      end

      other = %{sample("other", ~U[2026-11-14 00:35:09.751692Z], 4) | spacecraft_id: "other"}

      assert {:ok, []} =
               VerifierWorkflow.evaluate_telemetry([other], fetch_pending, persist, spacecraft_of)

      own = sample("applied", ~U[2026-11-14 00:35:09.751692Z], 4)

      assert {:ok, [%CommandVerifierInstance{lifecycle_state: :satisfied}]} =
               VerifierWorkflow.evaluate_telemetry([own], fetch_pending, persist, spacecraft_of)
    end
  end

  # DOVW1 as the release built it: released 00:35:05.169827Z, no plan delay, a 60 s timeout,
  # equal to SCIENCE (4; this branch has no value_from_argument binding, so a literal), raw.
  defp mode_applied(subject_ref) do
    request =
      CommandRequest.new(
        Map.merge(@ids, %{command_name: "SET_MODE", resolved_argument_values: %{"mode" => "4"}})
      )

    plan =
      VerifierPlan.new(%{
        command_id: "command:set_mode",
        verifier_id: "verifier:mode_applied",
        name: "Mode applied",
        phase: :completion,
        timeout_ms: 60_000,
        success_criteria:
          MatchCriteria.new(%{
            criteria_type: :comparison,
            subject_ref: subject_ref,
            comparison: :equal,
            value: 4,
            use_calibrated: false
          })
      })

    [instance] =
      ReleaseArtifacts.verifier_instances(
        CommandQueueEntry.new(Map.put(@ids, :organization_id, @organization_id)),
        request,
        CommandReleaseAttempt.new(Map.put(@ids, :command_release_attempt_id, "attempt-p9cs")),
        [plan],
        @released_at
      )

    instance
  end

  # A decom sample as the definition-bound handler builds it: the point is PACKET.field, the
  # parameter's semantic id rides in semantic_id, and generation time equals receipt time.
  defp sample(id, at, mode) do
    %Sample{
      sample_id: "sample-" <> id,
      mission_id: @mission_id,
      spacecraft_id: @spacecraft_id,
      point_id: "HK.sc_mode",
      point_name: "HK.sc_mode",
      semantic_id: @mode_parameter,
      qualified_name: "/EARENDIL/HK/sc_mode",
      producer_kind: :container,
      packet_definition_id: "packet-hk",
      packet_definition_version: 1,
      packet_id: "packet-" <> id,
      evidence_id: "evidence-" <> id,
      raw_value: mode,
      engineering_value: mode,
      quality_state: :good,
      generation_time: at,
      receipt_time: at
    }
  end
end
