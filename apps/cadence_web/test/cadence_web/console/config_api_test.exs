defmodule CadenceWeb.Console.ConfigAPITest do
  # Mutates :activation_governance application env.
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    alice = TestFixtures.persist_user!(display_name: "Alice")
    bob = TestFixtures.persist_user!(display_name: "Bob")
    TestFixtures.grant_membership!(alice, org)
    TestFixtures.grant_membership!(bob, org)
    mission = TestFixtures.persist_mission!(org)

    previous = Application.get_env(:cadence, :activation_governance, [])
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    %{
      alice: alice,
      bob: bob,
      org: org,
      mission: mission,
      base: "/api/console/v1/missions/#{mission.mission_id}/config"
    }
  end

  defp approval_required(required?),
    do: Application.put_env(:cadence, :activation_governance, approval_required: required?)

  defp station_op(name),
    do: %{
      "kind" => "ground_station",
      "action" => "create",
      "document" => %{"display_name" => name, "region" => "Arctic"}
    }

  defp call(user, method, path, body \\ nil) do
    conn = TestFixtures.member_conn(user)

    case method do
      :get -> get(conn, path)
      :post -> post(conn, path, body || %{})
    end
  end

  defp stage!(c, user, name) do
    c
    |> then(
      &call(user, :post, &1.base <> "/stage", %{
        "summary" => "Add #{name}",
        "ops" => [station_op(name)]
      })
    )
    |> json_response(201)
    |> Map.fetch!("data")
  end

  test "stage, read the bar, preview and submit (direct approval)", c do
    approval_required(false)

    bar = c.alice |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert %{"head" => %{"revision" => 1, "kind" => "baseline"}, "change_set" => nil} = bar
    assert "config.stage" in bar["permissions"]

    staged = stage!(c, c.alice, "Svalbard")

    assert %{
             "staged_count" => 1,
             "base_revision" => 1,
             "change_set_id" => set_id,
             "version" => version
           } = staged

    bar = c.alice |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert %{"state" => "open", "staged_count" => 1} = bar["change_set"]

    assert [%{"summary" => "Add Svalbard", "author" => %{"name" => "Alice"}}] =
             bar["change_set"]["changes"]

    preview =
      c.alice
      |> call(:post, "#{c.base}/change-sets/#{set_id}/preview")
      |> json_response(200)
      |> Map.fetch!("data")

    assert preview["verdict"] == "go"
    # ux U93: nothing has been activated on this mission, so applying starts nothing.
    assert preview["has_active_configuration"] == false

    applied =
      c.alice
      |> call(:post, "#{c.base}/change-sets/#{set_id}/submit", %{
        "reason" => "Add the Svalbard station",
        "expected_version" => version
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{
             "state" => "applied",
             "revision" => 2,
             "runtime" => "not_applicable",
             "has_active_configuration" => false
           } = applied

    revisions =
      c.alice
      |> call(:get, c.base <> "/revisions")
      |> json_response(200)
      |> get_in(["data", "revisions"])

    assert Enum.map(revisions, & &1["revision"]) == [2, 1]

    revision =
      c.alice |> call(:get, c.base <> "/revisions/2") |> json_response(200) |> Map.fetch!("data")

    assert [%{"kind" => "ground_station", "op" => "create", "before" => nil}] =
             revision["entries"]

    compare = c.alice |> call(:get, c.base <> "/compare?from=1&to=2") |> json_response(200)
    assert %{"from" => 1, "to" => 2, "entries" => [_ | _]} = compare["data"]

    # The same display fields as revision entries (fe-setup): the entity's name, field labels.
    [entry | _] = compare["data"]["entries"]
    assert Map.has_key?(entry, "entity_name")
    assert Enum.all?(entry["fields"], &Map.has_key?(&1, "label"))
  end

  defp apply!(c, name) do
    %{"change_set_id" => set_id, "version" => version} = stage!(c, c.alice, name)

    c.alice
    |> call(:post, "#{c.base}/change-sets/#{set_id}/submit", %{
      "reason" => "Add #{name}",
      "expected_version" => version
    })
    |> json_response(200)
    |> Map.fetch!("data")
  end

  test "U93: the preview says the mission has an active configuration once it has one", c do
    {:ok, _} =
      Cadence.Activations.record_binding_set_activation(
        c.org.organization_id,
        c.mission.mission_id,
        "u93-binding",
        1,
        binding_set_content_sha256: String.duplicate("0", 64)
      )

    %{"change_set_id" => set_id} = stage!(c, c.alice, "Kiruna")

    assert %{"has_active_configuration" => true} =
             c.alice
             |> call(:post, "#{c.base}/change-sets/#{set_id}/preview")
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "revisions by entity: only the revisions that touch it, with its labelled entries", c do
    approval_required(false)
    assert %{"revision" => 2} = apply!(c, "Svalbard")
    assert %{"revision" => 3} = apply!(c, "Kiruna")

    [%{"entity_id" => svalbard}] =
      c.alice
      |> call(:get, c.base <> "/revisions/2")
      |> json_response(200)
      |> get_in(["data", "entries"])

    revisions =
      c.alice
      |> call(:get, c.base <> "/revisions?entity_kind=ground_station&entity_id=#{svalbard}")
      |> json_response(200)
      |> get_in(["data", "revisions"])

    assert [%{"revision" => 2, "entries" => [entry]}] = revisions
    assert %{"entity_id" => ^svalbard, "op" => "create", "entity_name" => "Svalbard"} = entry
    assert Enum.all?(entry["fields"], &Map.has_key?(&1, "label"))

    conn = call(c.alice, :get, c.base <> "/revisions?entity_kind=nope&entity_id=x")
    assert %{"entity_kind" => _} = json_response(conn, 422)["error"]["details"]
  end

  test "independent approval: the author can't review; another member approves", c do
    approval_required(true)
    staged = stage!(c, c.alice, "Inuvik")
    set_path = "#{c.base}/change-sets/#{staged["change_set_id"]}"

    in_review =
      c.alice
      |> call(:post, set_path <> "/submit", %{
        "reason" => "Add the Inuvik station",
        "expected_version" => staged["version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"state" => "in_review", "version" => version} = in_review

    conn =
      call(c.alice, :post, c.base <> "/stage", %{
        "summary" => "More",
        "ops" => [station_op("Troll")]
      })

    assert json_response(conn, 409)["error"]["code"] == "frozen_in_review"

    conn =
      call(c.alice, :post, set_path <> "/review", %{
        "decision" => "approve",
        "comment" => "ok",
        "expected_version" => version
      })

    assert json_response(conn, 409)["error"]["code"] == "reviewer_is_author"

    approved =
      c.bob
      |> call(:post, set_path <> "/review", %{
        "decision" => "approve",
        "comment" => "Looks right",
        "expected_version" => version
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"state" => "applied", "revision" => 2} = approved
  end

  test "facade errors keep their codes and details", c do
    approval_required(false)

    conn =
      call(c.alice, :post, c.base <> "/stage", %{
        "summary" => "Bad",
        "ops" => [%{"kind" => "nope", "action" => "create"}]
      })

    assert %{"code" => "invalid_op", "details" => %{"index" => 0, "errors" => [_ | _]}} =
             json_response(conn, 422)["error"]

    staged = stage!(c, c.alice, "Kiruna")
    set_path = "#{c.base}/change-sets/#{staged["change_set_id"]}"

    conn =
      call(c.alice, :post, set_path <> "/submit", %{
        "reason" => "short",
        "expected_version" => staged["version"]
      })

    assert json_response(conn, 422)["error"]["code"] == "reason_required"

    conn =
      call(c.alice, :post, set_path <> "/submit", %{
        "reason" => "A long enough reason",
        "expected_version" => staged["version"] - 1
      })

    assert json_response(conn, 409)["error"]["code"] == "change_set_changed"

    conn = call(c.alice, :post, set_path <> "/submit", %{"reason" => "A long enough reason"})

    assert %{"code" => "invalid_params", "details" => %{"expected_version" => _}} =
             json_response(conn, 422)["error"]

    conn = call(c.alice, :get, c.base <> "/change-sets/nope")
    assert json_response(conn, 404)["error"]["code"] == "change_set_not_found"

    conn = call(c.alice, :get, c.base <> "/revisions/99")
    assert json_response(conn, 404)["error"]["code"] == "revision_not_found"
  end

  test "previewing a batch of spacecraft creates catches a SCID duplicated within the batch", c do
    approval_required(false)

    sc = fn name, scid ->
      %{
        "kind" => "spacecraft",
        "action" => "create",
        "document" => %{"display_name" => name, "scid" => scid}
      }
    end

    preview =
      c.alice
      |> call(:post, c.base <> "/preview", %{
        "ops" => [sc.("A", 101), sc.("B", 102), sc.("C", 101)]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert preview["verdict"] == "no_go"
    validation = Enum.find(preview["checks"], &(&1["key"] == "validation"))
    assert [%{"errors" => [%{"path" => "scid"} | _]}] = validation["items"]

    ok =
      c.alice
      |> call(:post, c.base <> "/preview", %{"ops" => [sc.("A", 101), sc.("B", 102)]})
      |> json_response(200)

    assert ok["data"]["verdict"] == "go"
  end

  test "previews unstaged ops and withdraws a staged change", c do
    approval_required(false)

    preview =
      c.alice
      |> call(:post, c.base <> "/preview", %{"ops" => [station_op("Awarua")]})
      |> json_response(200)
      |> Map.fetch!("data")

    assert preview["verdict"] in ["go", "hold", "no_go"]

    staged = stage!(c, c.alice, "Awarua")
    bar = c.alice |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    [change] = bar["change_set"]["changes"]

    withdrawn =
      c.alice |> call(:post, "#{c.base}/changes/#{change["id"]}/withdraw") |> json_response(200)

    assert withdrawn["data"]["change_set_id"] == staged["change_set_id"]
  end
end
