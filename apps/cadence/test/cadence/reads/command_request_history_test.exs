defmodule Cadence.Reads.CommandRequestHistoryTest do
  @moduledoc "U68 R3/R4: a member's release attempts and verifiers with their matched evidence."
  use Cadence.ConfigCase, async: false

  import Cadence.GroupReleaseFixtures

  alias Cadence.{CommandGroupFixtures, CommandHistoryFixtures}
  alias Cadence.Commanding.{CommandQueueEntryRow, CommandVerifierInstanceRow}
  alias Cadence.Control.Commanding
  alias Cadence.Reads.CommandRequestHistory

  @org "org-group-release"
  @mission "mission-group-release"
  @at ~U[2026-11-14 07:20:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    alpha = persist_target!("alpha", 0)
    model = import_noop_model!()
    scope = CommandGroupFixtures.operator!(%{org: @org}, "Release Operator")
    c = %{alpha: alpha, model: model, scope: scope}

    group = armed_group!(c, [alpha])
    [entry] = group.entries
    contact = uplink_contact!(alpha)

    {:ok, %{released_entry_ids: [^entry]}} =
      Commanding.release_group_to_contact(
        scope,
        @mission,
        group.id,
        contact.realized_contact_id,
        confirm_unbooked: true,
        attempted_at: @at
      )

    request_id = Repo.get!(CommandQueueEntryRow, entry).command_request_id
    {:ok, history} = CommandRequestHistory.load(@org, @mission, request_id)
    [attempt] = history.attempts

    Map.merge(c, %{request_id: request_id, contact: contact, attempt: attempt})
  end

  test "an attempt names its contact, state and sizes", c do
    assert %{
             state: state,
             uncertain: false,
             contact: %{id: contact_id, label: label},
             path_id: path_id,
             transport_binding_id: binding_id,
             attempted_at: %DateTime{}
           } = c.attempt

    assert state in ~w(release_pending released)
    assert contact_id == c.contact.realized_contact_id
    assert label =~ "contact"
    assert is_binary(path_id) and is_binary(binding_id)
  end

  test "each verifier says how it ended and shows the record that matched it", c do
    sample = sample!()
    own = action!(c, c.attempt.attempt_id)
    other = action!(c, "another-attempt")

    verifier!(c, 1, "pending", nil, nil)
    verifier!(c, 2, "satisfied", "telemetry_sample", sample)
    verifier!(c, 3, "satisfied", "transport_action_request", own)
    verifier!(c, 4, "satisfied", "transport_action_request", other)
    verifier!(c, 5, "timed_out", nil, nil, "timed_out")
    verifier!(c, 6, "satisfied", "telemetry_sample", "missing-sample")
    capability = capability!(c)
    verifier!(c, 7, "satisfied", "transport_capability_record", capability)

    {:ok, history} = CommandRequestHistory.load(@org, @mission, c.request_id)

    assert [
             {"pending", nil},
             {"ready", telemetry},
             {"ready", transport},
             {"unavailable", nil},
             {"unmatched", nil},
             {"unavailable", nil},
             {"ready", capability_record}
           ] = Enum.map(history.verifiers, &{&1.evidence_status, &1.evidence})

    # The phase it matched at, from the record's own metadata (fe-ops correction b).
    assert %{source: "capability_record", record_id: ^capability, signal_phase: "completion"} =
             capability_record

    assert %{
             kind: "telemetry",
             sample_id: ^sample,
             quality: quality,
             raw_value_json: "17",
             engineering_value_json: "17",
             received_at: %DateTime{}
           } = telemetry

    assert quality in ~w(good suspect bad)
    assert Map.has_key?(telemetry, :unit)

    assert %{kind: "transport", source: "action_request", record_id: ^own, at: %DateTime{}} =
             transport

    assert is_binary(transport.action)

    assert %{failure_code: "timed_out", severity: "warning", verifier_id: "verifier-5"} =
             Enum.at(history.verifiers, 4)
  end

  test "an attempt's failure says its kind and a code; the raw reason stays as said" do
    assert CommandRequestHistory.failure("released", nil) == nil

    assert CommandRequestHistory.failure("release_failed", "resolved: not_sent") ==
             %{kind: "resolved", code: "not_sent"}

    assert CommandRequestHistory.failure(
             "release_failed",
             ~s(refused: {:command_window_closed, "contact-1", :ended})
           ) == %{kind: "refused", code: "command_window_closed"}

    assert CommandRequestHistory.failure("release_failed", "refused: :fop_alerted") ==
             %{kind: "refused", code: "fop_alerted"}

    assert CommandRequestHistory.failure("release_uncertain", ":send_outcome_unknown") ==
             %{kind: "uncertain", code: "send_outcome_unknown"}

    assert CommandRequestHistory.failure("release_uncertain", "%RuntimeError{}") ==
             %{kind: "uncertain", code: nil}
  end

  test "a resolved failure names who resolved it and when", c do
    log = %{
      "entries" => [
        %{"outcome" => "unknown", "actor" => %{"kind" => "service", "id" => "cadence"}},
        %{
          "outcome" => "not_sent",
          "actor" => %{"kind" => "user", "id" => c.scope.user.user_id},
          "recorded_at" => "2026-11-14T07:25:05Z"
        }
      ]
    }

    assert %{kind: "resolved", code: "not_sent", by: %{kind: "user", id: id, name: name}, at: at} =
             CommandRequestHistory.resolved_by(%{kind: "resolved", code: "not_sent"}, log)

    assert id == c.scope.user.user_id and is_binary(name)
    assert at == ~U[2026-11-14 07:25:05Z]

    service = %{
      "entries" => [
        %{"outcome" => "rejected", "actor" => %{"kind" => "service", "id" => "svc-unknown"}}
      ]
    }

    assert %{by: %{kind: "service_identity", id: "svc-unknown", name: nil}} =
             CommandRequestHistory.resolved_by(
               %{kind: "resolved", code: "rejected"},
               service,
               @org
             )

    assert %{kind: "refused", by: nil, at: nil} =
             CommandRequestHistory.resolved_by(%{kind: "refused", code: "x"}, log)
  end

  test "pages of 25 by cursor; a stale cursor or an unknown request is refused", c do
    for i <- 1..27, do: verifier!(c, i, "pending", nil, nil)

    {:ok, first} = CommandRequestHistory.load(@org, @mission, c.request_id)
    assert length(first.verifiers) == 25
    assert first.verifiers_next == List.last(first.verifiers).instance_id
    assert first.attempts_next == nil

    {:ok, second} =
      CommandRequestHistory.load(@org, @mission, c.request_id,
        verifiers_after: first.verifiers_next
      )

    assert Enum.map(second.verifiers, & &1.verifier_id) == ["verifier-26", "verifier-27"]
    assert second.verifiers_next == nil

    assert {:error, :invalid_cursor} =
             CommandRequestHistory.load(@org, @mission, c.request_id, attempts_after: "nope")

    assert {:error, :command_request_not_found} =
             CommandRequestHistory.load(@org, @mission, "unknown-request")
  end

  defp verifier!(c, i, state, kind, record_id, failure \\ nil) do
    Repo.insert!(%CommandVerifierInstanceRow{
      command_verifier_instance_id: "verifier-instance-#{String.pad_leading("#{i}", 3, "0")}",
      organization_id: @org,
      mission_id: @mission,
      command_request_id: c.request_id,
      command_release_attempt_id: c.attempt.attempt_id,
      source_endpoint_ref: c.alpha.source_endpoint_id,
      mission_model_revision_id: c.model.revision_id,
      command_id: "NOOP",
      verifier_id: "verifier-#{i}",
      verifier_name: "Check #{i}",
      phase: "completion",
      severity: "warning",
      lifecycle_state: state,
      matched_record_kind: kind,
      matched_record_id: record_id,
      failure_reason: failure,
      metadata_document: %{},
      inserted_at: DateTime.add(@at, i, :second)
    })
  end

  # Through ingest, so its packet and evidence references are real.
  defp sample! do
    CommandHistoryFixtures.sample!(%{org: @org, mission: @mission}, 17).sample_id
  end

  defp capability!(c) do
    id = "capability-" <> Integer.to_string(System.unique_integer([:positive]))

    CommandHistoryFixtures.capability!(
      %{org: @org, mission: @mission},
      id,
      c.request_id,
      c.attempt.attempt_id,
      metadata: %{"signal_phase" => "completion"}
    )

    id
  end

  # Through the transport store; `action_kind` and `signal_phase` are the fixture's.
  defp action!(c, attempt_id) do
    id = "action-" <> Integer.to_string(System.unique_integer([:positive]))
    CommandHistoryFixtures.action!(%{org: @org, mission: @mission}, id, c.request_id, attempt_id)
    id
  end
end
