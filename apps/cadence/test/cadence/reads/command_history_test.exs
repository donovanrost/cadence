defmodule Cadence.Reads.CommandHistoryTest do
  use Cadence.DataCase, async: false
  alias Cadence.CommandMonitorFixtures, as: Fixtures
  alias Cadence.CommandReviewFixtures
  alias Cadence.Reads.CommandHistory
  alias Cadence.Reads.CommandHistory.Query

  setup do
    c = CommandReviewFixtures.scope!()
    request = Fixtures.request!(c, "history-request")
    queue = Fixtures.queue!(c, request)
    Map.merge(c, %{request: request, queue: queue})
  end

  test "an uncertain release keeps its identity and absence of completion in the selected and paged views",
       c do
    Fixtures.release!(c, c.request, c.queue, "uncertain-release", %{
      lifecycle_state: :release_uncertain,
      verification_state: nil,
      released_at: nil
    })

    assert {:ok, model} = load(c, %{"release" => "uncertain-release"})
    assert model["selection"]["release"]["state"] == "release_uncertain"
    assert model["selection"]["release"]["released_at"] == nil
    assert model["selection"]["release"]["id"] == "uncertain-release"
    assert [model["selection"]["release"]] == model["releases"]["entries"]
    assert model["verifiers"]["entries"] == []
  end

  test "both ledgers traverse beyond the monitor previews with independent pinned selections",
       c do
    for n <- 1..28 do
      id = String.pad_leading(to_string(n), 2, "0")
      release = Fixtures.release!(c, c.request, c.queue, "release-#{id}")

      Fixtures.verifier!(c, c.request, release, "verifier-#{id}", %{
        lifecycle_state: if(n == 28, do: :failed, else: :satisfied),
        failure_reason: if(n == 28, do: "failure_criteria_matched")
      })
    end

    # Exercise the actual SQL directly so a SQL failure cannot be hidden by the
    # public unavailable envelope while developing this producer.
    assert %{rows: [[%{"valid" => true}]], num_rows: 1} =
             Repo.query!(Query.statement(), [c.org, c.mission, "history-request", "", "", "", ""])

    assert {:ok, first} = load(c)
    assert length(first["releases"]["entries"]) == 25
    assert first["releases"]["next_after"] == "release-04"
    assert first["verifiers"]["next_after"] == "verifier-25"
    assert first["evidence"] == %{"status" => "not_selected", "record" => nil}

    assert {:ok, last} =
             load(c, %{"release_after" => "release-04", "verifier_after" => "verifier-25"})

    assert Enum.map(last["releases"]["entries"], & &1["id"]) ==
             ~w(release-03 release-02 release-01)

    assert Enum.map(last["verifiers"]["entries"], & &1["id"]) ==
             ~w(verifier-26 verifier-27 verifier-28)

    assert last["verifiers"]["next_after"] == nil
    assert List.last(last["verifiers"]["entries"])["failure_code"] == "failure_criteria_matched"

    query = %{
      "release" => "release-01",
      "release_after" => "release-04",
      "verifier" => "verifier-01"
    }

    assert {:ok, pinned} = load(c, query)
    assert pinned["selection"]["release"]["id"] == "release-01"
    assert pinned["selection"]["release"]["encoded_size_bytes"] == nil
    assert length(pinned["verifiers"]["entries"]) == 1
    assert pinned["evidence"]["status"] == "unmatched"

    Fixtures.release!(c, c.request, c.queue, "release-new", %{
      attempted_at: ~U[2026-09-11 00:00:00.000000Z]
    })

    assert {:ok, refreshed} = load(c, query)
    assert refreshed["selection"] == pinned["selection"]
    assert refreshed["query"] == pinned["query"]
  end

  test "release-filtered verifier paging includes every older failure", c do
    release = Fixtures.release!(c, c.request, c.queue, "older-release")

    for n <- 1..28 do
      Fixtures.verifier!(
        c,
        c.request,
        release,
        "verifier-#{String.pad_leading(to_string(n), 2, "0")}",
        %{
          lifecycle_state: if(n == 28, do: :failed, else: :satisfied)
        }
      )
    end

    assert {:ok, first} = load(c, %{"release" => "older-release"})

    assert {:ok, last} =
             load(c, %{
               "release" => "older-release",
               "verifier_after" => first["verifiers"]["next_after"],
               "verifier" => "verifier-01"
             })

    assert length(last["verifiers"]["entries"]) == 3
    assert List.last(last["verifiers"]["entries"])["state"] == "failed"
    assert last["selection"]["verifier"]["id"] == "verifier-01"
  end

  test "unknown and foreign cursors and selections never substitute newer evidence", c do
    own = Fixtures.release!(c, c.request, c.queue, "own-release")
    Fixtures.verifier!(c, c.request, own, "own-verifier")
    other = Fixtures.request!(c, "other-request")
    queue = Fixtures.queue!(c, other)
    foreign = Fixtures.release!(c, other, queue, "other-release")
    Fixtures.verifier!(c, other, foreign, "other-verifier")

    for query <- [
          %{"release" => "missing"},
          %{"release_after" => "other-release"},
          %{"release" => "other-release"},
          %{"verifier_after" => "other-verifier"},
          %{"release" => "own-release", "verifier" => "other-verifier"},
          %{"release" => "own-release", "verifier_after" => "other-verifier"}
        ] do
      assert {:error, :unavailable} = load(c, query)
    end

    foreign_scope = CommandReviewFixtures.scope!()

    assert {:error, :unavailable} =
             CommandHistory.load(foreign_scope.scope, foreign_scope.mission, "history-request")

    assert {:error, :unavailable} =
             CommandHistory.load(c.scope, foreign_scope.mission, "history-request")
  end

  test "query and authorization admission run before the history statement", c do
    parent = self()

    unexpected = fn _, _ ->
      send(parent, :unexpected_read)
      raise "unexpected"
    end

    for query <- [
          %{"verifier" => "own"},
          %{"release" => nil},
          %{"unknown" => "x"},
          %{"release_after" => "bad\n"},
          %{"release" => String.duplicate("é", 129)}
        ] do
      assert {:error, :unavailable} =
               CommandHistory.load(c.scope, c.mission, "history-request", query,
                 query: unexpected
               )
    end

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"}
        ] do
      assert {:error, :unavailable} =
               CommandHistory.load(scope, c.mission, "history-request", %{}, query: unexpected)
    end

    refute_received :unexpected_read
  end

  test "missing backing evidence is local while private command documents never cross the read",
       c do
    secret = String.duplicate("private-command-payload", 40_000)

    release =
      Fixtures.release!(c, c.request, c.queue, "release-private", %{
        encoded_binary_base64: secret,
        metadata: %{"private" => secret}
      })

    Fixtures.verifier!(c, c.request, release, "verifier-private", %{
      matched_record_kind: :telemetry_sample,
      matched_record_id: "missing-sample",
      failure_reason: secret
    })

    parent = self()

    query = fn sql, args ->
      result = Repo.query!(sql, args)
      send(parent, {:materialized, result})
      result
    end

    assert {:ok, data} =
             CommandHistory.load(
               c.scope,
               c.mission,
               "history-request",
               %{"release" => "release-private", "verifier" => "verifier-private"},
               query: query
             )

    assert data["evidence"] == %{"status" => "unavailable", "record" => nil}
    assert data["selection"]["verifier"]["failure_code"] == nil
    assert_received {:materialized, %{rows: [[raw]], num_rows: 1}}
    assert byte_size(Jason.encode!(raw)) < 10_000
    refute Jason.encode!(raw) =~ "private-command-payload"
  end

  test "matched telemetry preserves unsigned64 JSON text and excludes provenance", c do
    sample = Cadence.CommandHistoryFixtures.sample!(c)
    release = Fixtures.release!(c, c.request, c.queue, "sample-release")

    Fixtures.verifier!(c, c.request, release, "sample-verifier", %{
      matched_record_kind: :telemetry_sample,
      matched_record_id: sample.sample_id
    })

    query = %{"release" => "sample-release", "verifier" => "sample-verifier"}
    assert {:ok, data} = load(c, query)
    assert data["evidence"]["status"] == "ready"
    assert data["evidence"]["record"]["raw_value_json"] == "18446744073709551615"
    assert data["evidence"]["record"]["engineering_value_json"] == "18446744073709551615"
    assert data["evidence"]["record"]["id"] == sample.sample_id
    refute Jason.encode!(data) =~ "private-provenance"

    Repo.query!("UPDATE telemetry_samples SET raw_value = $1 WHERE sample_id = $2", [
      %{"value" => String.duplicate("wide", 30_000)},
      sample.sample_id
    ])

    assert {:ok, oversize} = load(c, query)
    assert oversize["evidence"]["status"] == "unavailable"
    assert oversize["selection"]["verifier"]["id"] == "sample-verifier"
    foreign_scope = CommandReviewFixtures.scope!()
    foreign_sample = Cadence.CommandHistoryFixtures.sample!(foreign_scope, 42)

    Repo.query!(
      "UPDATE command_verifier_instances SET matched_record_id = $1 WHERE command_verifier_instance_id = 'sample-verifier'",
      [foreign_sample.sample_id]
    )

    assert {:ok, foreign} = load(c, query)
    assert foreign["evidence"]["status"] == "unavailable"
  end

  test "transport matches require exact request and release correlation", c do
    release = Fixtures.release!(c, c.request, c.queue, "transport-release")

    for {kind, id} <- [
          {:transport_action_request, "action-record"},
          {:transport_capability_record, "capability-record"}
        ] do
      if kind == :transport_action_request,
        do: Cadence.CommandHistoryFixtures.action!(c, id, "history-request", "transport-release"),
        else:
          Cadence.CommandHistoryFixtures.capability!(
            c,
            id,
            "history-request",
            "transport-release"
          )

      Fixtures.verifier!(c, c.request, release, "verifier-#{id}", %{
        matched_record_kind: kind,
        matched_record_id: id
      })

      assert {:ok, data} =
               load(c, %{"release" => "transport-release", "verifier" => "verifier-#{id}"})

      assert data["evidence"]["status"] == "ready"
      assert data["evidence"]["record"]["request_id"] == "history-request"
      assert data["evidence"]["record"]["release_attempt_id"] == "transport-release"
      refute Jason.encode!(data) =~ "private-"
    end

    Repo.query!(
      "UPDATE transport_action_requests SET signal_phase = 'unknown-phase' WHERE action_request_id = 'action-record'"
    )

    assert {:ok, malformed} =
             load(c, %{"release" => "transport-release", "verifier" => "verifier-action-record"})

    assert malformed["evidence"]["status"] == "unavailable"

    Repo.query!(
      "UPDATE transport_action_requests SET command_request_id = 'different-request' WHERE action_request_id = 'action-record'"
    )

    Repo.query!(
      "UPDATE transport_capability_records SET state_snapshot = $1 WHERE transport_record_id = 'capability-record'",
      [
        %{
          "value" => %{
            "last_command_request_id" => "history-request",
            "last_release_attempt_id" => "different-release"
          }
        }
      ]
    )

    for id <- ~w(action-record capability-record) do
      assert {:ok, data} =
               load(c, %{"release" => "transport-release", "verifier" => "verifier-#{id}"})

      assert data["evidence"]["status"] == "unavailable"
    end
  end

  test "capability correlation honors wrapped documents and native false/null fallback", c do
    release = Fixtures.release!(c, c.request, c.queue, "fallback-release")

    cases = [
      {%{"last_command_request_id" => false, "last_release_attempt_id" => nil}, "ready"},
      {%{"last_command_request_id" => "", "last_release_attempt_id" => "fallback-release"},
       "unavailable"},
      {%{"last_command_request_id" => 42, "last_release_attempt_id" => "fallback-release"},
       "unavailable"}
    ]

    for {{state, expected}, n} <- Enum.with_index(cases) do
      id = "capability-#{n}"

      Cadence.CommandHistoryFixtures.capability!(c, id, "history-request", "fallback-release",
        state: state,
        metadata: %{
          "value" => %{
            "command_request_id" => "history-request",
            "command_release_attempt_id" => "fallback-release"
          }
        }
      )

      Fixtures.verifier!(c, c.request, release, "verifier-#{n}", %{
        matched_record_kind: :transport_capability_record,
        matched_record_id: id
      })

      assert {:ok, data} =
               load(c, %{"release" => "fallback-release", "verifier" => "verifier-#{n}"})

      assert data["evidence"]["status"] == expected
    end
  end

  defp load(c, query \\ %{}),
    do: CommandHistory.load(c.scope, c.mission, "history-request", query)
end
