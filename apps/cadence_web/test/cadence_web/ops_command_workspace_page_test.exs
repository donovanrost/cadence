defmodule CadenceWeb.OpsCommandWorkspacePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Cadence.Auth.Scope
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandRequest,
    CommandRequestRow,
    CommandStage,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Control.Commanding.WorkspaceSubmission
  alias Cadence.Platform.ScopedReadUpdates, as: ReadUpdates
  alias Cadence.Repo
  alias CadenceWeb.{HostTransportTestSupport, TestFixtures}
  alias CadenceWeb.OpsCommandWorkspaceSession, as: Session

  @probe Path.expand(
           "../../../../frontend/modules/commanding/src/features/workspace/producer-consumer-probe.mjs",
           __DIR__
         )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    member = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = CommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    target = CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id)

    second =
      CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
        display_name: "Second spacecraft endpoint",
        scid: 8
      })

    {:ok, stage} =
      StageStore.persist_stage(
        org.organization_id,
        CommandStage.new(%{
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          stage_name: "Fleet preparation",
          owner: %{"user_id" => user.user_id},
          visibility: :private
        })
      )

    %{
      org: org.organization_id,
      organization: org,
      member: member,
      user: user,
      mission: mission.mission_id,
      model: model,
      target: target,
      second: second,
      stage: stage
    }
  end

  test "an uncertain write retains its own evidence while browsing and previewing continue", c do
    scope = Scope.new(%{user: c.user, organization_membership: c.member})
    command_id = c.model.commands_by_name["COMMAND_1"]

    session =
      Session.new({c.org, c.user.user_id, c.mission, path(c)}, %{
        "command" => command_id,
        "target" => c.target.source_endpoint_id
      })

    assert {:ok, data, session} = Session.load(scope, session)

    command = %{
      "expected_basis" => data.catalog["basis"]["token"],
      "source_endpoint_ref" => c.target.source_endpoint_id,
      "command_id" => command_id,
      "argument_values_json" => ~s({"amount":2,"delay_s":5}),
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }

    input = %{"expected_stage" => nil, "commands" => [command], "notes" => nil}

    assert {%{status: "previewed", queue_preview: original}, session} =
             Session.action(scope, session, "preview_targets", input)

    attempt =
      Map.take(session, [
        :stage_id,
        :creation,
        :create_input,
        :draft_preview,
        :queue_preview,
        :batch_preview
      ])

    token = session.write_token
    operation = %{status: "unconfirmed", event: "enqueue", stage_id: nil, write_token: token}
    session = %{session | operation: operation, write_attempt: attempt}

    assert {%{status: "browsed"}, session} =
             Session.action(scope, session, "browse", %{
               "kind" => "stage",
               "id" => c.stage.command_stage_id
             })

    assert session.operation.status == "unconfirmed"

    assert {%{status: "rejected"}, _} =
             Session.action(scope, session, "enqueue", %{
               "expected_write" => token,
               "expected_preview" => original["token"]
             })

    newer = %{
      input
      | "commands" => [%{command | "argument_values_json" => ~s({"amount":7,"delay_s":5})}]
    }

    assert {%{status: "previewed", queue_preview: newer_preview}, session} =
             Session.action(scope, session, "preview_targets", newer)

    assert session.write_attempt == attempt
    assert session.queue_preview != attempt.queue_preview

    # Model a write whose durable result arrives after the user has continued preparing.
    assert {:ok, receipt} =
             WorkspaceSubmission.submit(scope, c.mission, token, attempt.queue_preview, %{
               "expected_write" => token,
               "expected_preview" => original["token"]
             })

    assert {:ok, data, recovered} = Session.load(scope, session)
    assert recovered.operation.status == "completed"
    assert recovered.operation.receipt == receipt
    assert recovered.stage_id == c.stage.command_stage_id
    assert data.queue_preview["token"] == newer_preview["token"]
    assert recovered.write_token != token
    assert request_count(c) == 1
  end

  test "real workspace controls prepare two endpoints, persist drafts and submit exact reviewed requests",
       c do
    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)
    assert page["status"] == "ready"
    assert page["data"]["state"] == "prepare"

    assert page["data"]["catalog"]["selected_command"]["id"] ==
             c.model.commands_by_name["COMMAND_1"]

    %{"event" => "preview_targets", "input" => input} = probe(page, "preview_targets")
    assert length(input["commands"]) == 2

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, path, page, "preview_targets", input)

    assert length(preview["items"]) == 2
    assert draft_count(c) == 0
    assert %{"snapshot" => page} = read(view, path, page)
    %{"event" => "save_targets", "input" => save} = probe(page, "save_targets")

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, path, page, "save_targets", save)

    assert length(receipt["items"]) == 2
    assert draft_count(c) == 2
    assert request_count(c) == 0

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, path, page, "save_targets", save)

    assert %{"snapshot" => page} = read(view, path, page)
    assert page["data"]["draft_preview"] == nil
    %{"event" => "preview_batch", "input" => input} = probe(page, "preview_batch")

    assert %{"snapshot" => %{"status" => "previewed"}} =
             action(view, path, page, "preview_batch", input)

    assert %{"snapshot" => page} = read(view, path, page)
    %{"event" => "submit", "input" => input} = probe(page, "submit")

    assert %{"snapshot" => %{"status" => "completed", "receipt" => submitted}} =
             action(view, path, page, "submit", input)

    assert length(submitted["requests"]) == 2
    assert request_count(c) == 2
    assert Enum.all?(submitted["requests"], &(&1["state"] == "approval_pending"))
    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, path, page, "submit", input)
    assert request_count(c) == 2
  end

  test "real workspace controls enqueue without choosing or creating a stage", c do
    command = c.model.commands_by_name["COMMAND_2"]
    path = "/missions/#{c.mission}/ops/commands/workspace?command=#{URI.encode_www_form(command)}"
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    {:ok, peer, _} = live(TestFixtures.member_conn(c.user), "/missions/#{c.mission}/ops/commands")
    assert command_context(view)["data"]["queued_count"] == 0
    assert command_context(peer)["data"]["queued_count"] == 0
    page = page(view, c.mission)
    assert page["data"]["workbench"] == nil
    %{"input" => input} = probe(page, "preview_targets")
    assert input["expected_stage"] == nil

    assert %{
             "snapshot" => %{
               "status" => "previewed",
               "preview" => nil,
               "queue_preview" => preview
             }
           } =
             action(view, path, page, "preview_targets", input)

    assert length(preview["requests"]) == 2
    assert request_count(c) == 0
    assert %{"snapshot" => page} = read(view, path, page)
    %{"event" => "enqueue", "input" => input} = probe(page, "enqueue")

    assert %{"snapshot" => %{"status" => "completed", "stage_id" => nil, "receipt" => receipt}} =
             action(view, path, page, "enqueue", input)

    assert Enum.all?(receipt["requests"], &(&1["state"] == "queued" && &1["queue_id"]))
    assert draft_count(c) == 0
    assert request_count(c) == 2

    assert Repo.aggregate(
             from(row in CommandQueueEntryRow, where: row.mission_id == ^c.mission),
             :count
           ) == 2

    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, path, page, "enqueue", input)
    assert request_count(c) == 2
    assert %{"snapshot" => page} = read(view, path, page)
    assert page["data"]["queue_preview"] == nil
    assert page["data"]["workbench"] == nil
    assert_command_context_queued(view, 2)
    assert_command_context_queued(peer, 2)
  end

  test "catalog searches and subsequent pages preserve command selection and a held preview", c do
    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)
    %{"event" => "preview_targets", "input" => input} = probe(page, "preview_targets")

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, path, page, "preview_targets", input)

    assert %{"snapshot" => before} = read(view, path, page)

    for index <- 1..30 do
      CommandAuthoringFixtures.target!(c.org, c.mission, %{
        source_endpoint_id: "search_endpoint_#{String.pad_leading(to_string(index), 2, "0")}",
        display_name: "Search endpoint #{index}"
      })
    end

    query = Map.put(before["data"]["catalog"]["query"], "target_query", "Search endpoint")

    assert %{"snapshot" => %{"status" => "catalog_page", "catalog" => first}} =
             action(view, path, page, "catalog_page", %{"query" => query})

    assert length(first["targets"]["entries"]) == 25
    assert first["targets"]["next_after"]
    query = Map.put(query, "target_after", first["targets"]["next_after"])

    assert %{"snapshot" => %{"status" => "catalog_page", "catalog" => second}} =
             action(view, path, page, "catalog_page", %{"query" => query})

    assert length(second["targets"]["entries"]) == 5
    assert second["targets"]["next_after"] == nil
    ids = Enum.map(first["targets"]["entries"] ++ second["targets"]["entries"], & &1["id"])
    assert length(Enum.uniq(ids)) == 30

    query = Map.put(before["data"]["catalog"]["query"], "command_query", "COMMAND_2")

    assert %{"snapshot" => %{"status" => "catalog_page", "catalog" => filtered}} =
             action(view, path, page, "catalog_page", %{"query" => query})

    assert Enum.map(filtered["commands"]["entries"], & &1["name"]) == ["COMMAND_2"]
    assert filtered["selected_command"]["id"] == c.model.commands_by_name["COMMAND_1"]

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, path, page, "catalog_page", %{
               "query" => %{"command_query" => String.duplicate("x", 241)}
             })

    assert %{"snapshot" => after_search} = read(view, path, page)
    assert after_search["data"]["catalog"]["query"] == before["data"]["catalog"]["query"]
    assert after_search["data"]["write_token"] == before["data"]["write_token"]
    assert after_search["data"]["draft_preview"]["token"] == preview["token"]
    assert draft_count(c) == 0
  end

  test "inline stage creation, bounded browsing and switching stages keep the captured workspace",
       c do
    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)

    assert %{"snapshot" => %{"status" => "browsed", "data" => data}} =
             action(view, path, page, "browse", %{
               "kind" => "catalog",
               "query" => %{"command_query" => "COMMAND"}
             })

    assert data["catalog"]["query"]["command_query"] == "COMMAND"

    create = %{
      "expected_write" => data["write_token"],
      "name" => "New private pass",
      "description" => nil,
      "visibility" => "private"
    }

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, path, page, "create_stage", create)

    assert %{"snapshot" => current} = read(view, path, page)
    assert current["token"] == page["token"]
    assert current["data"]["workbench"]["stage"]["id"] == receipt["stage_id"]

    assert %{"snapshot" => %{"status" => "browsed", "data" => data}} =
             action(view, path, page, "browse", %{
               "kind" => "stage",
               "id" => c.stage.command_stage_id
             })

    assert data["workbench"]["stage"]["id"] == c.stage.command_stage_id

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, path, page, "browse", %{
               "kind" => "catalog",
               "query" => %{"command_query" => String.duplicate("x", 241)}
             })

    assert draft_count(c) == 0
  end

  test "committed stage changes wake the captured workspace and stop after departure", c do
    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)
    token = page["token"]
    updated = %{c.stage | stage_name: "Updated by another operator"}
    assert {:ok, _} = StageStore.update_stage(c.org, updated)

    assert_push_event(
      view,
      "cadence:ops-page-changed",
      %{id: "commanding.workspace", token: ^token, path: ^path},
      1_000
    )

    assert %{"snapshot" => current} = read(view, path, page)
    assert current["data"]["workbench"]["stage"]["name"] == updated.stage_name
    refute_push_event(view, "cadence:ops-page-changed", _, 300)

    send(view.pid, {:commanding_changed, c.org, "another-mission"})
    refute_push_event(view, "cadence:ops-page-changed", _, 300)
    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission}/ops/commands"})
    assert_reply(view, %{ok: true})
    assert {:ok, _} = StageStore.update_stage(c.org, %{updated | stage_name: "After departure"})
    send(view.pid, {:command_workspace_reconcile, token})
    refute_push_event(view, "cadence:ops-page-changed", _, 350)
  end

  test "rolled back stage writes do not publish changes", c do
    ReadUpdates.subscribe(:commanding_changed, c.org, c.mission)
    org = c.org
    mission = c.mission

    assert {:error, :discard} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        StageStore.update_stage(c.org, %{c.stage | stage_name: "Discarded"})

               refute_receive {:commanding_changed, ^org, ^mission}
               Repo.rollback(:discard)
             end)

    refute_receive {:commanding_changed, ^org, ^mission}
    assert {:ok, stored} = StageStore.fetch_stage(c.org, c.mission, c.stage.command_stage_id)
    assert stored.stage_name == c.stage.stage_name
  end

  test "reconciliation preserves an unchanged review and removes changed target evidence", c do
    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)
    %{"input" => input} = probe(page, "preview_targets")

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, path, page, "preview_targets", input)

    refute_push_event(view, "cadence:ops-page-changed", _, 300)
    assert %{"snapshot" => current} = read(view, path, page)
    assert current["data"]["draft_preview"]["token"] == preview["token"]

    assert %{"snapshot" => %{"status" => "completed"}} =
             action(view, path, page, "save_targets", %{
               "expected_write" => current["data"]["write_token"],
               "expected_preview" => preview["token"]
             })

    assert_push_event(view, "cadence:ops-page-changed", _, 1_000)
    assert %{"snapshot" => current} = read(view, path, page)
    %{"input" => input} = probe(current, "preview_batch")

    assert %{"snapshot" => %{"status" => "previewed", "preview" => batch}} =
             action(view, path, page, "preview_batch", input)

    refute_push_event(view, "cadence:ops-page-changed", _, 300)
    assert %{"snapshot" => current} = read(view, path, page)
    assert current["data"]["batch_preview"]["token"] == batch["token"]

    Repo.get!(Cadence.SourceEndpoints.SourceEndpointRow, c.target.source_endpoint_id)
    |> Ecto.Changeset.change(scid: 10)
    |> Repo.update!()

    send(view.pid, {:command_workspace_reconcile, page["token"]})
    assert_push_event(view, "cadence:ops-page-changed", _, 1_000)
    assert %{"snapshot" => current} = read(view, path, page)
    assert current["data"]["batch_preview"] == nil
    assert request_count(c) == 0
  end

  test "new command requests wake execution readers without a page refresh", c do
    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)
    token = page["token"]
    catalog = page["data"]["catalog"]

    request =
      CommandRequest.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        source_endpoint_ref: c.target.source_endpoint_id,
        command_id: catalog["selected_command"]["id"],
        mission_model_revision_id: catalog["basis"]["revision_id"],
        requested_by: %{"actor_kind" => "user", "user_id" => c.user.user_id},
        argument_values: %{"amount" => 2, "delay_s" => 5}
      })

    assert {:ok, saved} = Cadence.Commanding.persist_command_request(c.org, request)
    assert_push_event(view, "cadence:ops-page-changed", %{token: ^token}, 1_000)
    assert %{"snapshot" => current} = read(view, path, page)
    assert Enum.any?(current["data"]["monitor"]["rows"], &(&1["id"] == saved.command_request_id))
  end

  test "private stages, foreign page tokens and departed workspace actions fail closed", c do
    other = TestFixtures.persist_user!()

    {:ok, private} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Other operator",
          owner: %{"user_id" => other.user_id},
          visibility: :private
        })
      )

    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)

    refute Enum.any?(
             page["data"]["directory"]["stages"]["entries"],
             &(&1["id"] == private.command_stage_id)
           )

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, path, page, "browse", %{
               "kind" => "stage",
               "id" => private.command_stage_id
             })

    assert %{"ok" => false} =
             action(view, path, %{page | "token" => Ecto.UUID.generate()}, "preview_targets", %{})

    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission}/ops/commands"})
    assert_reply(view, %{ok: true})
    assert %{"ok" => false} = action(view, path, page, "save_targets", %{})
    assert draft_count(c) == 0
  end

  test "unavailable active model keeps durable stage inspection and execution available", c do
    path = path(c)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    page = page(view, c.mission)
    Repo.delete!(Repo.get!(Cadence.Activations.ActiveBindingSetRow, c.mission))
    assert %{"snapshot" => current} = read(view, path, page)
    assert current["status"] == "ready"
    assert current["data"]["catalog"] == nil
    assert current["data"]["workbench"]["stage"]["id"] == c.stage.command_stage_id
    assert current["data"]["monitor"]["mission_id"] == c.mission
  end

  test "members observe execution and fresh role changes remove preparation access", c do
    path = path(c) <> "&focus_command_id=missing-command"
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    captured = page(view, c.mission)

    Repo.get!(Cadence.Accounts.OrganizationMembershipRow, c.member.organization_membership_id)
    |> Ecto.Changeset.change(role: "member")
    |> Repo.update!()

    assert %{"snapshot" => %{"status" => "ready", "data" => data}} = read(view, path, captured)
    assert data["state"] == "observe"
    assert data["monitor"]["query"]["focus_command_id"] == "missing-command"
    refute Map.has_key?(data, "catalog")
    refute Map.has_key?(data, "workbench")

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, path, captured, "preview_targets", %{})

    assert draft_count(c) == 0
  end

  defp assert_command_context_queued(view, count, attempts \\ 40)

  defp assert_command_context_queued(view, count, 0),
    do: assert(command_context(view)["data"]["queued_count"] == count)

  defp assert_command_context_queued(view, count, attempts) do
    if command_context(view)["data"]["queued_count"] != count do
      Process.sleep(25)
      assert_command_context_queued(view, count, attempts - 1)
    end
  end

  defp command_context(view) do
    view
    |> LiveVue.Test.get_vue(id: "application-shell")
    |> Map.fetch!(:props)
    |> get_in(["snapshot", "context", "ops_context", "modules"])
    |> Enum.find(&(&1["key"] == "commands"))
  end

  defp path(c),
    do:
      "/missions/#{c.mission}/ops/commands/workspace?stage=#{c.stage.command_stage_id}&command=#{c.model.commands_by_name["COMMAND_1"]}"

  defp page(view, mission),
    do:
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => "commanding.workspace",
        "mission_id" => mission
      })["ops_page"]

  defp draft_count(c),
    do:
      Repo.aggregate(
        from(row in StagedCommandItemRow, where: row.mission_id == ^c.mission),
        :count
      )

  defp request_count(c),
    do:
      Repo.aggregate(from(row in CommandRequestRow, where: row.mission_id == ^c.mission), :count)

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp read(view, path, page) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp probe(page, mode) do
    file = Path.join(System.tmp_dir!(), "cadence-workspace-producer-#{Ecto.UUID.generate()}.json")
    File.write!(file, Jason.encode!(page))

    try do
      {output, code} = System.cmd("node", [@probe, file, mode], stderr_to_stdout: true)
      assert code == 0, output
      [_, encoded] = Regex.run(~r/COMMAND_WORKSPACE_INPUT=([A-Za-z0-9+\/=]+)/, output)
      encoded |> Base.decode64!() |> Jason.decode!()
    after
      File.rm!(file)
    end
  end
end
