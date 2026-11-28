defmodule CadenceWeb.Console.SourceEndpointRelayAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.SpacecraftStore
  alias CadenceWeb.{MissionReadModelFixtures, TestFixtures}

  @path "relay.origin_spacecraft_ids"

  setup do
    org = TestFixtures.persist_org!()
    author = TestFixtures.persist_user!()
    reviewer = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(author, org, role: :organization_admin)
    TestFixtures.grant_membership!(reviewer, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    config = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, config) end)

    context = %{
      org: org.organization_id,
      mission: mission.mission_id,
      author: author,
      reviewer: reviewer,
      base: "/api/v1/missions/#{mission.mission_id}"
    }

    delivery = spacecraft!(context, "Relay spacecraft", 10)
    origin = spacecraft!(context, "Origin spacecraft", 20)
    endpoint = create!(context, delivery, "Relay receiver")

    Map.merge(context, %{delivery: delivery, origin: origin, endpoint: endpoint})
  end

  test "a reviewed declaration is persisted and its comparison names each origin and SCID", c do
    schema =
      c.author
      |> TestFixtures.member_conn()
      |> get(c.base <> "/config/kinds/source_endpoint/schema")
      |> json_response(200)

    assert [%{"path" => @path, "label" => "Relay origin spacecraft"}] = schema["data"]["fields"]

    staged = stage!(c, op(c.endpoint, @path, [c.origin, c.delivery, c.origin]))
    assert read(c)["relay"] == nil

    preview = request(c.author, set_path(c, staged) <> "/preview", %{}, 200)
    assert preview["verdict"] == "go"

    assert [
             %{
               "entity_name" => "Relay receiver",
               "fields" => [
                 %{
                   "path" => @path,
                   "label" => "Relay origin spacecraft",
                   "before_label" => "No relay origins",
                   "after_label" => "Origin spacecraft (SCID 20)"
                 }
               ]
             }
           ] = preview["diffs"]

    approve!(c, staged)
    assert read(c)["relay"] == %{"origin_spacecraft_ids" => [c.origin]}

    approve!(c, stage!(c, op(c.endpoint, @path, [])))
    assert read(c)["relay"] == nil

    approve!(c, stage!(c, op(c.endpoint, @path, [c.origin])))
    approve!(c, stage!(c, op(c.endpoint, "relay", nil)))
    assert read(c)["relay"] == nil
  end

  test "preview refuses unknown origins and origins in another organization", c do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)
    foreign = spacecraft!(%{org: org.organization_id, mission: mission.mission_id}, "Foreign", 30)

    for id <- ["unknown-spacecraft", foreign] do
      assert_error(c, [c.origin, id], "relay_origin_not_in_mission")
    end
  end

  test "preview and approval refuse a relay origin without a SCID", c do
    no_scid = spacecraft!(c, "Unconfigured origin", nil)
    assert_error(c, [c.origin, no_scid], "relay_origin_without_scid")

    staged = stage!(c, op(c.endpoint, @path, [c.origin]))
    version = submit!(c, staged)

    assert {:ok, origin} = SpacecraftStore.fetch_spacecraft(c.org, c.mission, c.origin)
    assert {:ok, %{scid: nil}} = SpacecraftStore.update_spacecraft(c.org, %{origin | scid: nil})

    review = %{"decision" => "approve", "expected_version" => version}
    result = request(c.reviewer, set_path(c, staged) <> "/review", review, 422)
    assert %{"error" => %{"code" => "checks_failed", "details" => preview}} = result
    assert_preview_error(preview, "relay_origin_without_scid")
    assert read(c)["relay"] == nil
  end

  test "relay is unavailable on direct creation, and the change-set kind edits relay alone", c do
    params = %{
      "source_endpoint" => %{
        "source_ref" => "no-direct-relay",
        "relay" => %{"origin_spacecraft_ids" => [c.origin]}
      }
    }

    result = request(c.author, c.base <> "/source-endpoints", params, 422)
    assert result["error"]["details"] == %{"field" => "relay", "reason" => "requires_change_set"}

    create = %{"action" => "create", "kind" => "source_endpoint", "document" => %{}}
    delete = %{"action" => "delete", "kind" => "source_endpoint", "entity_id" => c.endpoint}

    for invalid <- [create, delete, op(c.endpoint, "display_name", "Other name")] do
      assert %{"error" => %{"details" => %{"errors" => [_ | _]}}} =
               request(
                 c.author,
                 c.base <> "/config/stage",
                 %{"summary" => "Invalid", "ops" => [invalid]},
                 422
               )
    end
  end

  defp assert_error(c, origins, code) do
    preview =
      request(
        c.author,
        c.base <> "/config/preview",
        %{"ops" => [op(c.endpoint, @path, origins)]},
        200
      )

    assert_preview_error(preview, code)
    assert read(c)["relay"] == nil
  end

  defp assert_preview_error(preview, code) do
    assert preview["verdict"] == "no_go"
    validation = Enum.find(preview["checks"], &(&1["key"] == "validation"))
    assert [%{"errors" => [%{"path" => @path, "code" => ^code}]}] = validation["items"]
  end

  defp spacecraft!(c, name, scid) do
    MissionReadModelFixtures.persist_api_spacecraft!(c.org, c.mission, %{
      display_name: name,
      scid: scid
    }).spacecraft_id
  end

  defp create!(c, craft, label) do
    request(
      c.author,
      c.base <> "/spacecraft/#{craft}/source-endpoints",
      %{"source_endpoint" => %{"source_ref" => "relay-rx", "display_name" => label}},
      201
    )["source_endpoint_id"]
  end

  defp read(c) do
    c.author
    |> TestFixtures.member_conn()
    |> get(c.base <> "/source-endpoints/" <> c.endpoint)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp op(endpoint, path, value) do
    %{
      "kind" => "source_endpoint",
      "action" => "update",
      "entity_id" => endpoint,
      "changes" => [%{"path" => path, "value" => value}]
    }
  end

  defp stage!(c, op) do
    request(
      c.author,
      c.base <> "/config/stage",
      %{"summary" => "Declare relay", "ops" => [op]},
      201
    )
  end

  defp approve!(c, staged) do
    version = submit!(c, staged)
    review = %{"decision" => "approve", "expected_version" => version}

    assert %{"state" => "applied"} =
             request(c.reviewer, set_path(c, staged) <> "/review", review, 200)
  end

  defp submit!(c, staged) do
    path = set_path(c, staged)
    submit = %{"reason" => "Review relay declaration", "expected_version" => staged["version"]}

    assert %{"state" => "in_review", "version" => version} =
             request(c.author, path <> "/submit", submit, 200)

    version
  end

  defp set_path(c, staged), do: c.base <> "/config/change-sets/" <> staged["change_set_id"]

  defp request(user, path, body, status) do
    response = user |> TestFixtures.member_conn() |> post(path, body) |> json_response(status)
    Map.get(response, "data", response)
  end
end
