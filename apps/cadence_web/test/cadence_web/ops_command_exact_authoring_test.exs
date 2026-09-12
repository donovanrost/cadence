defmodule CadenceWeb.OpsCommandExactAuthoringTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandStage,
    StageStore
  }

  alias Cadence.ExactCommandAuthoringFixtures
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  @maximum 18_446_744_073_709_551_615
  @authoring_probe Path.expand(
                     "../../../../frontend/modules/commanding/src/features/command-authoring/producer-consumer-probe.mjs",
                     __DIR__
                   )
  @stage_probe Path.expand(
                 "../../../../frontend/modules/commanding/src/shared/stages/producer-consumer-probe.mjs",
                 __DIR__
               )
  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    target = CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id)

    %{
      org: org.organization_id,
      user: user,
      mission: mission.mission_id,
      model: model,
      target: target
    }
  end

  @tag timeout: 120_000
  test "real producer and mounted Vue preserve default, explicit, signed and typed enum values through Phoenix create",
       c do
    for {command, inputs, native} <- [
          {"SET_COUNTER", %{"amount" => "2"}, %{"amount" => 2}},
          {"SET_COUNTER", %{"amount" => "2", "counter" => Integer.to_string(@maximum)},
           %{"amount" => 2, "counter" => @maximum}},
          {"SET_SIGNED", %{"counter" => "-9223372036854775808"},
           %{"counter" => -9_223_372_036_854_775_808}},
          {"SET_ENUM", %{"counter" => Integer.to_string(@maximum)}, %{"counter" => @maximum}},
          {"SET_ENUM", %{"counter" => Jason.encode!(Integer.to_string(@maximum))},
           %{"counter" => Integer.to_string(@maximum)}}
        ] do
      path =
        "/missions/#{c.mission}/ops/commands/new?" <>
          URI.encode_query(%{
            "command" => c.model.commands_by_name[command],
            "target" => c.target.source_endpoint_id
          })

      {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
      p = page(view)
      assert p["status"] == "ready"
      input = authoring_probe(p, inputs)
      assert Jason.decode!(input["argument_values_json"]) == native

      assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
               action(view, path, p, "preview", input)

      expected =
        if command == "SET_COUNTER", do: Map.put_new(native, "counter", @maximum), else: native

      assert Jason.decode!(preview["resolved_argument_values_json"]) == expected
      assert %{"snapshot" => refreshed} = read(view, path, p)
      create = authoring_probe(refreshed, %{})

      assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
               action(view, path, p, "create", create)

      request =
        Repo.get!(CommandRequestRow, receipt["request_id"]) |> CommandRequestRow.to_domain()

      assert request.argument_values == native
      assert request.resolved_argument_values == expected
      assert request.requested_by["user_id"] == c.user.user_id
    end

    assert Repo.aggregate(CommandRequestRow, :count) == 5
    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
    assert Repo.aggregate(CommandReleaseAttemptRow, :count) == 0
  end

  @tag timeout: 120_000
  test "actual stage producer and Vue retain wide draft values through saved-item read and batch submission",
       c do
    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Exact values",
          owner: %{"user_id" => c.user.user_id},
          visibility: :private
        })
      )

    base = "/missions/#{c.mission}/ops/commands/stages/#{stage.command_stage_id}"

    path =
      base <>
        "?" <>
        URI.encode_query(%{
          "command" => c.model.commands_by_name["SET_COUNTER"],
          "target" => c.target.source_endpoint_id
        })

    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    p = page(view)
    inputs = %{"amount" => "2", "counter" => Integer.to_string(@maximum)}
    %{"event" => "preview_item", "input" => input} = stage_probe(p, "preview_item", inputs)
    assert Jason.decode!(input["command"]["argument_values_json"])["counter"] == @maximum

    assert %{"snapshot" => %{"status" => "previewed"}} =
             action(view, path, p, "preview_item", input)

    assert %{"snapshot" => p} = read(view, path, p)
    %{"event" => "save_item", "input" => input} = stage_probe(p, "save_item")

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, path, p, "save_item", input)

    assert Repo.aggregate(CommandRequestRow, :count) == 0
    selected_path = path <> "&item=" <> URI.encode_www_form(receipt["item_id"])
    p = navigate(view, selected_path)

    assert Jason.decode!(p["data"]["workbench"]["selected_item"]["argument_values_json"])[
             "counter"
           ] == @maximum

    %{"event" => "preview_batch", "input" => input} = stage_probe(p, "preview_batch")

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, selected_path, p, "preview_batch", input)

    assert [request_preview] = preview["requests"]
    assert Jason.decode!(request_preview["resolved_argument_values_json"])["counter"] == @maximum
    assert %{"snapshot" => p} = read(view, selected_path, p)
    %{"event" => "submit", "input" => input} = stage_probe(p, "submit")

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, selected_path, p, "submit", input)

    assert [request] = receipt["requests"]
    stored = Repo.get!(CommandRequestRow, request["request_id"]) |> CommandRequestRow.to_domain()
    assert stored.argument_values == %{"amount" => 2, "counter" => @maximum}
    assert stored.resolved_argument_values == stored.argument_values
    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
    assert Repo.aggregate(CommandReleaseAttemptRow, :count) == 0
  end

  defp authoring_probe(p, values) do
    {output, status} =
      System.cmd("node", [@authoring_probe, Jason.encode!(p)],
        env: [{"CADENCE_COMMAND_AUTHORING_EXACT_INPUT", Jason.encode!(values)}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    decode(output, ~r/COMMAND_AUTHORING_INPUT=([A-Za-z0-9+\/=]+)/)
  end

  defp stage_probe(p, mode, values \\ %{}) do
    path = Path.join(System.tmp_dir!(), "exact-stage-#{Ecto.UUID.generate()}.json")
    File.write!(path, Jason.encode!(p))

    try do
      {output, status} =
        System.cmd("node", [@stage_probe, path, mode],
          env: [{"CADENCE_COMMAND_STAGES_EXACT_INPUT", Jason.encode!(values)}],
          stderr_to_stdout: true
        )

      assert status == 0, output
      decode(output, ~r/COMMAND_STAGE_INPUT=([A-Za-z0-9+\/=]+)/)
    after
      File.rm!(path)
    end
  end

  defp decode(output, regex) do
    [_, encoded] = Regex.run(regex, output)
    encoded |> Base.decode64!() |> Jason.decode!()
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp navigate(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true, snapshot: snapshot})
    Jason.decode!(Jason.encode!(snapshot))["ops_page"]
  end

  defp action(view, path, p, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    Jason.decode!(Jason.encode!(reply))
  end

  defp read(view, path, p) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"]
    })

    assert_reply(view, reply)
    Jason.decode!(Jason.encode!(reply))
  end
end
