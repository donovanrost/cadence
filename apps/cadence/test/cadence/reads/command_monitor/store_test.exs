defmodule Cadence.Reads.CommandMonitor.StoreTest do
  use Cadence.DataCase, async: false
  alias Cadence.CommandMonitorFixtures, as: Fixtures
  alias Cadence.CommandReviewFixtures
  alias Cadence.Reads.{CommandMonitor, CommandMonitorProjection, Commands}
  alias Cadence.Reads.CommandMonitor.Search

  @now ~U[2026-09-10 12:00:00.000000Z]
  setup do
    CommandReviewFixtures.scope!()
  end

  test "uncertain release is counted and filterable as indeterminate while its lane remains held",
       c do
    request = Fixtures.request!(c, "held-request", %{lifecycle_state: :queued})
    queue = Fixtures.queue!(c, request, %{lifecycle_state: :release_pending})

    Fixtures.release!(c, request, queue, "uncertain-attempt", %{
      lifecycle_state: :release_uncertain,
      verification_state: nil,
      released_at: nil
    })

    model =
      assert_matches(c, %{"status" => "indeterminate", "focus_command_id" => "held-request"})

    assert model.total == 1
    assert model.summary.indeterminate_count == 1
    assert model.summary.release_pending_count == 0
    assert model.focus.row.status == "indeterminate"
    assert model.focus.row.release.state == "release_uncertain"
    assert model.focus.row.release.released_at == nil
    assert model.focus.row.queue.state == "release_pending"
    assert model.focus.row.verifier_total == 0
  end

  test "the database projection matches canonical status precedence and complete verifier aggregates",
       c do
    for state <- [
          :draft,
          :validated,
          :approval_pending,
          :approved,
          :rejected,
          :queued,
          :released,
          :canceled
        ] do
      Fixtures.request!(c, "request-#{state}", %{lifecycle_state: state})
    end

    for state <- [:pending, :release_pending, :released, :canceled] do
      request = Fixtures.request!(c, "queue-#{state}")
      Fixtures.queue!(c, request, %{lifecycle_state: state})
    end

    for state <- [:release_pending, :released, :release_failed, :release_uncertain, :canceled],
        verification <- [nil, :not_required, :pending, :satisfied, :failed, :timed_out] do
      id = "release-#{state}-#{verification}"
      request = Fixtures.request!(c, id)
      queue = Fixtures.queue!(c, request)

      Fixtures.release!(c, request, queue, id, %{
        lifecycle_state: state,
        verification_state: verification
      })
    end

    request = Fixtures.request!(c, "all-verifiers")
    queue = Fixtures.queue!(c, request)
    older = Fixtures.release!(c, request, queue, "release-a")
    latest = Fixtures.release!(c, request, queue, "release-z")

    for n <- 1..20 do
      Fixtures.verifier!(
        c,
        request,
        latest,
        "preview-#{String.pad_leading(to_string(n), 2, "0")}"
      )
    end

    Fixtures.verifier!(c, request, older, "unseen-failure", %{
      lifecycle_state: :failed,
      timeout_at: ~U[2027-01-01 00:00:00.000000Z]
    })

    for query <- [
          %{},
          %{"page" => "2"},
          %{"page" => "999"},
          %{"status" => "failed", "focus_command_id" => "request-approved"},
          %{"status" => "approved", "focus_command_id" => "all-verifiers"}
        ] do
      assert_matches(c, query)
    end

    assert {:ok, data} =
             CommandMonitor.load(c.scope, c.mission, %{"focus_command_id" => "all-verifiers"})

    assert data.focus.row.status == "failed"
    assert data.focus.row.verification_state == "failed"
    assert data.focus.row.release.id == "release-z"
    assert data.focus.row.verifier_total == 21
    assert length(data.focus.row.verifiers) == 20
    assert Enum.all?(data.focus.row.verifiers, &(&1.state == "satisfied"))
    assert data.focus.row.occurred_at == "2027-01-01T00:00:00.000000Z"
  end

  test "persisted state normalization matches the canonical stores even outside verifier previews",
       c do
    request = Fixtures.request!(c, "normalized")
    queue = Fixtures.queue!(c, request)
    release = Fixtures.release!(c, request, queue, "normalized-release")

    for n <- 1..21 do
      Fixtures.verifier!(
        c,
        request,
        release,
        "normalized-#{String.pad_leading(to_string(n), 2, "0")}"
      )
    end

    Repo.query!(
      "UPDATE command_verifier_instances SET lifecycle_state = 'legacy-unknown', matched_record_kind = 'legacy-kind' WHERE command_verifier_instance_id = $1",
      ["normalized-21"]
    )

    data = assert_matches(c, %{})
    assert hd(data.rows).status == "in_flight"
    assert hd(data.rows).verification_state == "pending"

    Repo.query!(
      "UPDATE command_requests SET lifecycle_state = 'legacy-unknown', verification_state = 'legacy-unknown' WHERE command_request_id = $1",
      ["normalized"]
    )

    Repo.query!(
      "UPDATE command_queue_entries SET lifecycle_state = 'legacy-unknown' WHERE command_queue_entry_id = $1",
      [queue.command_queue_entry_id]
    )

    Repo.query!(
      "UPDATE command_release_attempts SET lifecycle_state = 'legacy-unknown', verification_state = 'legacy-unknown' WHERE command_release_attempt_id = $1",
      [release.command_release_attempt_id]
    )

    data = assert_matches(c, %{})
    assert hd(data.rows).status == "release_pending"
    assert hd(data.rows).request_state == "draft"
  end

  test "literal search preserves the application's Unicode conversion and byte ordering", c do
    for {id, name, actor} <- [
          {"a", "100%_Complete\\", %{display_name: "ÉLODIE"}},
          {"A", "İSTANBUL ΣΣ", %{email: "ΣΣ@example.test"}},
          {"ä", "ẞtraße", %{user_id: "ÜSER"}},
          {"z", "OTHER", %{display_name: false, email: "Fallback"}}
        ] do
      Fixtures.request!(c, id, %{
        command_name: name,
        requested_by: actor,
        source_endpoint_ref: "endpoint-#{id}"
      })
    end

    for term <- [
          "%",
          "_",
          "\\",
          "élodie",
          "i̇stanbul",
          "σσ",
          "σς",
          "ßtraße",
          "sstrasse",
          "üser",
          "fallback",
          ""
        ] do
      assert_matches(c, %{"query" => term})
    end

    # Exercise all translated scalar mappings in one actual database query, plus
    # context-sensitive traps which default String.downcase intentionally ignores.
    [upper | _] = Search.parameters()
    input = upper <> " İIΣΣΟΣ ẞStraße éÉ 😃 %_\\"
    sql = "SELECT #{Search.expression("$1::text", 2)}"
    assert %{rows: [[actual]]} = Repo.query!(sql, [input | Search.parameters()])
    assert actual == String.downcase(input)
  end

  test "targets, page clamping and independent focus agree with the full canonical read", c do
    for n <- 1..203 do
      id = "target-#{String.pad_leading(to_string(n), 3, "0")}"
      Fixtures.request!(c, id, %{source_endpoint_ref: id})
    end

    for query <- [
          %{},
          %{"page" => "999"},
          %{"target" => "target-201"},
          %{"query" => "missing", "focus_command_id" => "target-203"}
        ] do
      data = assert_matches(c, query)
      assert length(data.targets) == 200
      assert data.targets_limited
    end
  end

  test "one bounded result excludes large persisted arguments, payloads, criteria and metadata",
       c do
    private = String.duplicate("must-not-materialize-", 20_000)

    for n <- 1..27 do
      payload = if n == 9, do: private, else: "must-not-materialize"

      request =
        Fixtures.request!(c, "request-#{n}", %{
          argument_values: %{"secret" => payload},
          metadata: %{"secret" => payload}
        })

      queue = Fixtures.queue!(c, request)

      release =
        Fixtures.release!(c, request, queue, "release-#{n}", %{
          encoded_binary_base64: payload,
          metadata: %{"secret" => payload}
        })

      for v <- 1..21 do
        Fixtures.verifier!(c, request, release, "verifier-#{n}-#{v}", %{
          metadata: %{"secret" => payload}
        })
      end
    end

    parent = self()

    execute = fn sql, params ->
      result = Repo.query!(sql, params)
      send(parent, {:monitor_result, result, sql})
      result
    end

    assert {:ok, data} =
             CommandMonitor.load(c.scope, c.mission, %{"focus_command_id" => "request-9"},
               query: execute
             )

    assert length(data.rows) == 25
    assert data.focus.row.verifier_total == 21
    assert_received {:monitor_result, %{num_rows: 1, rows: [[result]]}, sql}
    refute_received {:monitor_result, _, _}
    assert length(result["rows"]) == 25
    assert length(result["focus"]["verifier_instances"]) == 20
    assert Enum.all?(result["rows"], &(length(&1["verifier_instances"]) == 20))
    refute Jason.encode!(result) =~ "must-not-materialize"
    assert byte_size(Jason.encode!(result)) < 524_288

    for field <- [
          "argument_values_document",
          "metadata_document",
          "encoded_binary_base64",
          "success_criteria_document",
          "failure_criteria_document"
        ] do
      refute sql =~ field
    end
  end

  test "oversize selected evidence is unavailable without sending its value from PostgreSQL", c do
    huge = String.duplicate("huge-name-", 20_000)
    Fixtures.request!(c, "oversize", %{requested_by: %{display_name: huge}})
    parent = self()

    execute = fn sql, params ->
      result = Repo.query!(sql, params)
      send(parent, {:raw, result})
      result
    end

    assert {:error, :unavailable} = CommandMonitor.load(c.scope, c.mission, %{}, query: execute)
    assert_received {:raw, %{rows: [[result]]}}
    assert result["rows"] == [%{"invalid" => true}]
    refute Jason.encode!(result) =~ "huge-name"
  end

  defp assert_matches(c, params) do
    assert {:ok, query} = CommandMonitor.admit_query(params)
    snapshot = Commands.snapshot(c.org, c.mission, filters: query, observed_at: fn -> @now end)
    total = length(snapshot.rows)
    pages = max(1, ceil(total / 25))
    page = min(String.to_integer(query["page"]), pages)
    project = &CommandMonitorProjection.row(&1, c.org, c.mission)
    rows = snapshot.rows |> Enum.slice((page - 1) * 25, 25) |> Enum.map(project)

    expected_focus =
      if query["focus_command_id"] do
        case Enum.find(
               snapshot.summary.rows,
               &(&1.command_request_id == query["focus_command_id"])
             ) do
          nil -> %{status: "not_found", row: nil}
          row -> %{status: "ready", row: project.(row)}
        end
      else
        %{status: "not_selected", row: nil}
      end

    assert {:ok, actual} =
             CommandMonitor.load(c.scope, c.mission, params, observed_at: fn -> @now end)

    assert actual.rows == rows
    assert actual.focus == expected_focus

    assert actual.total == total and actual.pages == pages and
             actual.query["page"] == to_string(page)

    assert actual.summary ==
             Map.drop(snapshot.summary, [
               :mission_id,
               :observed_at,
               :latest_transition_at,
               :freshness,
               :status,
               :rows
             ])

    assert actual.targets == Enum.take(snapshot.targets, 200)
    assert actual.targets_limited == length(snapshot.targets) > 200
    actual
  end
end
