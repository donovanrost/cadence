defmodule CadenceWeb.CommandMonitorReadTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow
  }

  alias Cadence.Reads.CommandMonitor
  alias Cadence.Repo
  alias CadenceWeb.{HostTransportTestSupport, OpsCommandPage, TestFixtures}

  @checker Path.expand(
             "../../../../frontend/modules/commanding/src/features/mission-commands/producer-contract-check.mjs",
             __DIR__
           )
  @now ~U[2026-09-08 12:05:00.123456Z]
  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    %{
      org: org.organization_id,
      mission: mission.mission_id,
      user: user,
      scope: scope,
      opts: [observed_at: fn -> @now end]
    }
  end

  test "persisted evidence reaches the real Vue entry without command arguments or encoded bytes",
       c do
    persist(c, "request-a", true)
    before = counts()
    assert {:ok, model} = CommandMonitor.load(c.scope, c.mission, %{}, c.opts)
    assert model.version == 1 and model.status == "ready"
    assert [row] = model.rows
    assert row.status == "in_flight"
    assert row.queue.id == "queue-request-a"
    assert row.release.id == "release-request-a"
    assert row.release.queue_entry_id == row.queue.id
    assert row.release.contact_id == "contact-a"
    assert [verifier] = row.verifiers
    assert verifier.id == "verifier-request-a-1"
    assert verifier.release_attempt_id == row.release.id
    assert row.requested_at == "2026-09-08T12:00:00.123456Z"
    refute Jason.encode!(model) =~ "must-not-reach-browser"

    assert {:ok, focused} =
             CommandMonitor.load(
               c.scope,
               c.mission,
               %{"status" => "failed", "focus_command_id" => "request-a"},
               c.opts
             )

    assert focused.rows == [] and focused.status == "empty"
    assert focused.focus == %{status: "ready", row: row}

    assert {:ok, missing} =
             CommandMonitor.load(c.scope, c.mission, %{"focus_command_id" => "missing"}, c.opts)

    assert missing.focus == %{status: "not_found", row: nil}
    assert counts() == before

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!([model, focused, missing])],
               stderr_to_stdout: true
             )

    assert output =~ "Vue renderer contract passed"
  end

  test "pages and verifier lists are bounded without confusing partial display with empty", c do
    for i <- 1..27, do: persist(c, "request-#{i}", false)
    persist(c, "request-evidence", true, 21)
    assert {:ok, first} = CommandMonitor.load(c.scope, c.mission, %{}, c.opts)
    assert first.total == 28 and first.pages == 2 and first.page_size == 25
    assert length(first.rows) == 25

    assert {:ok, last} =
             CommandMonitor.load(
               c.scope,
               c.mission,
               %{"page" => "999", "focus_command_id" => "request-evidence"},
               c.opts
             )

    assert last.query["page"] == "2" and length(last.rows) == 3
    assert last.focus.row.verifier_total == 21
    assert length(last.focus.row.verifiers) == 20
    assert Enum.map(first.rows ++ last.rows, & &1.id) |> Enum.uniq() |> length() == 28

    assert {:ok, filtered} =
             CommandMonitor.load(c.scope, c.mission, %{"query" => "CMD-request-27"}, c.opts)

    assert Enum.map(filtered.rows, & &1.id) == ["request-27"]

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!([first, last, filtered])],
               stderr_to_stdout: true
             )

    assert output =~ "Vue renderer contract passed"
  end

  test "authorization and query rejection precede command reads, including refresh", c do
    parent = self()

    denied_read = fn _, _ ->
      send(parent, :unexpected_command_read)
      raise "unexpected read"
    end

    opts = Keyword.put(c.opts, :query, denied_read)
    foreign_org = TestFixtures.persist_org!()
    foreign_mission = TestFixtures.persist_mission!(foreign_org)

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: foreign_mission.mission_id},
          %{c.scope | organization_id: foreign_org.organization_id}
        ] do
      assert {:error, :unavailable} = CommandMonitor.load(scope, c.mission, %{}, opts)
    end

    for query <- [
          %{"unknown" => "x"},
          %{"status" => "launch"},
          %{"page" => "0"},
          %{"page" => "1x"},
          %{"query" => "x\n"},
          %{"focus_command_id" => ""},
          %{"query" => String.duplicate("x", 257)}
        ] do
      assert {:error, :invalid_command_query} =
               CommandMonitor.load(c.scope, c.mission, query, opts)
    end

    refute_received :unexpected_command_read
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: c.scope}}
    info = %{route: "/missions/:mission_id/ops/commands", params: %{"mission_id" => c.mission}}
    ready = OpsCommandPage.prepare(socket, info, "/commands", c.opts)
    assert ready.assigns.ops_page.status == "ready"
    refute Map.has_key?(ready.assigns.ops_page, :token)

    revoked =
      Phoenix.Component.assign(ready, :current_scope, %{c.scope | organization_membership: nil})

    unavailable = OpsCommandPage.prepare(revoked, info, "/commands", opts)
    assert unavailable.assigns.ops_page.status == "unavailable"
    refute Map.has_key?(unavailable.assigns.ops_page, :data)
    refute_received :unexpected_command_read
  end

  test "source errors are unavailable, not empty; foreign focused records do not leak", c do
    assert {:ok, empty} = CommandMonitor.load(c.scope, c.mission, %{}, c.opts)
    assert empty.status == "empty" and empty.total == 0

    assert {:error, :unavailable} =
             CommandMonitor.load(
               c.scope,
               c.mission,
               %{},
               Keyword.put(c.opts, :query, fn _, _ -> raise "must-not-reach-browser" end)
             )

    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)
    persist(%{org: org.organization_id, mission: mission.mission_id}, "foreign-request", true)

    assert {:ok, model} =
             CommandMonitor.load(
               c.scope,
               c.mission,
               %{"focus_command_id" => "foreign-request"},
               c.opts
             )

    assert model.status == "empty" and model.focus == %{status: "not_found", row: nil}
  end

  test "the authenticated mission route composes commands without a frontend installation", c do
    persist(c, "request-a", true)
    path = "/missions/#{c.mission}/ops/commands?focus_command_id=request-a"
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => "commanding.monitor",
        "mission_id" => c.mission,
        "query_params" => %{"focus_command_id" => "request-a"}
      })

    assert snapshot["ops_page"]["data"]["focus"]["row"]["id"] == "request-a"
    assert snapshot["ops_page"]["id"] == "commanding.monitor"
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path)
  end

  # Direct persisted fixtures isolate read projection from approval/release effects.
  defp persist(c, id, evidence?, verifiers \\ 1) do
    request = %CommandRequest{
      command_request_id: id,
      organization_id: c.org,
      mission_id: c.mission,
      source_endpoint_ref: "endpoint-a",
      mission_model_revision_id: "revision-a",
      command_id: "CMD-#{id}",
      command_name: "NOOP",
      requested_by: %{display_name: "Operator"},
      requested_at: ~U[2026-09-08 12:00:00.123456Z],
      lifecycle_state: if(evidence?, do: :released, else: :approved),
      verification_state: if(evidence?, do: :pending, else: nil),
      argument_values: %{"secret" => "must-not-reach-browser"},
      metadata: %{secret: "must-not-reach-browser"}
    }

    Repo.insert!(CommandRequestRow.changeset(request))

    if evidence? do
      queue = %CommandQueueEntry{
        command_queue_entry_id: "queue-#{id}",
        organization_id: c.org,
        mission_id: c.mission,
        command_request_id: id,
        source_endpoint_ref: "endpoint-a",
        queue_lane_key: "endpoint-a",
        queue_sequence: 1,
        lifecycle_state: :released,
        enqueued_at: ~U[2026-09-08 12:01:00Z]
      }

      Repo.insert!(CommandQueueEntryRow.changeset(queue))

      release = %CommandReleaseAttempt{
        command_release_attempt_id: "release-#{id}",
        organization_id: c.org,
        mission_id: c.mission,
        command_queue_entry_id: "queue-#{id}",
        command_request_id: id,
        source_endpoint_ref: "endpoint-a",
        realized_contact_id: "contact-a",
        mission_model_revision_id: "revision-a",
        command_id: "CMD-#{id}",
        lifecycle_state: :released,
        verification_state: :pending,
        attempted_at: ~U[2026-09-08 12:02:00Z],
        released_at: ~U[2026-09-08 12:03:00Z],
        encoded_binary_base64: "must-not-reach-browser",
        metadata: %{secret: "must-not-reach-browser"}
      }

      Repo.insert!(CommandReleaseAttemptRow.changeset(release))

      for i <- 1..verifiers do
        verifier = %CommandVerifierInstance{
          command_verifier_instance_id: "verifier-#{id}-#{i}",
          organization_id: c.org,
          mission_id: c.mission,
          command_request_id: id,
          command_release_attempt_id: "release-#{id}",
          source_endpoint_ref: "endpoint-a",
          mission_model_revision_id: "revision-a",
          command_id: "CMD-#{id}",
          verifier_id: "completion-#{i}",
          verifier_name: "Completion #{i}",
          phase: :completion,
          lifecycle_state: :pending,
          timeout_at: ~U[2026-09-08 12:04:00Z],
          metadata: %{secret: "must-not-reach-browser"}
        }

        Repo.insert!(CommandVerifierInstanceRow.changeset(verifier))
      end
    end
  end

  defp counts,
    do:
      Enum.map(
        [
          CommandRequestRow,
          CommandQueueEntryRow,
          CommandReleaseAttemptRow,
          CommandVerifierInstanceRow
        ],
        &Repo.aggregate(&1, :count)
      )
end
