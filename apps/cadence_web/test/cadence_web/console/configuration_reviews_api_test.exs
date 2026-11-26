defmodule CadenceWeb.Console.ConfigurationReviewsAPITest do
  @moduledoc """
  #734: `POST /missions/:mission_id/configuration/reviews`, one review (or one direct activation)
  of any number of spacecraft: `{spacecraft: {id => token}}` or `{all_saved: true}`.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.Governance.ActivationPolicy
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    org_id = org.organization_id
    mission_id = mission.mission_id

    {first, revision, _endpoint} = CatalogFixtures.setup_imported_mission!(org_id, mission_id)
    second = CatalogFixtures.persist_spacecraft!(org_id, mission_id, display_name: "Second")

    CatalogFixtures.persist_source_endpoint!(org_id, mission_id, second.spacecraft_id,
      display_name: "Second TT&C"
    )

    scope = CatalogFixtures.user_scope(org_id, "lead")
    policy = ActivationPolicy.load(org_id, mission_id)

    {:ok, _} =
      ActivationPolicy.save(scope, mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    %{
      user: user,
      mission: mission,
      revision: revision,
      first: first,
      second: second,
      base: "/api/console/v1/missions/#{mission_id}"
    }
  end

  defp conn(c), do: TestFixtures.member_conn(c.user)
  defp path(c, craft), do: "#{c.base}/spacecraft/#{craft.spacecraft_id}/configuration/workspace"

  defp workspace(c, craft),
    do: conn(c) |> get(path(c, craft)) |> json_response(200) |> Map.fetch!("data")

  # Saves the craft's draft with the imported catalog; returns the fresh snapshot.
  defp save(c, craft) do
    data = workspace(c, craft)
    document = Map.put(data["document"], "catalog_revision_id", c.revision.catalog_revision_id)

    conn(c)
    |> put(path(c, craft) <> "/draft", %{"token" => data["token"], "document" => document})
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp policy_token(c), do: workspace(c, c.first)["approval"]["policy_token"]

  defp reviews(c, body) do
    conn(c)
    |> post(
      c.base <> "/configuration/reviews",
      Map.merge(%{"policy_token" => policy_token(c), "intent" => "activate"}, body)
    )
  end

  test "reviews and activates the spacecraft named, with their tokens", c do
    tokens =
      Map.new([c.first, c.second], fn craft ->
        {craft.spacecraft_id, save(c, craft)["token"]}
      end)

    assert %{"data" => %{"state" => "active", "execution_id" => id, "spacecraft_count" => 2}} =
             reviews(c, %{"spacecraft" => tokens}) |> json_response(200)

    assert is_binary(id)

    for craft <- [c.first, c.second] do
      assert %{"active" => %{"document" => doc}} = workspace(c, craft)
      assert doc["catalog_revision_id"] == c.revision.catalog_revision_id
    end
  end

  test "intent review asks for approval when the mission requires it", c do
    scope = CatalogFixtures.user_scope(c.mission.organization_id, "lead")
    policy = ActivationPolicy.load(c.mission.organization_id, c.mission.mission_id)

    {:ok, _} =
      ActivationPolicy.save(scope, c.mission.mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })

    tokens = %{c.first.spacecraft_id => save(c, c.first)["token"]}

    assert %{
             "data" => %{
               "state" => "approval_pending",
               "request_id" => id,
               "spacecraft_count" => 1
             }
           } =
             reviews(c, %{"spacecraft" => tokens, "intent" => "review"}) |> json_response(200)

    assert is_binary(id)
  end

  test "all_saved covers only the drafts that differ from active; none is 422 nothing_to_review",
       c do
    assert %{"error" => %{"code" => "nothing_to_review"}} =
             reviews(c, %{"all_saved" => true}) |> json_response(422)

    save(c, c.first)

    assert %{"data" => %{"state" => "active", "spacecraft_count" => 1}} =
             reviews(c, %{"all_saved" => true}) |> json_response(200)

    save(c, c.second)

    assert %{"data" => %{"state" => "active", "spacecraft_count" => 1}} =
             reviews(c, %{"all_saved" => true}) |> json_response(200)

    assert %{"error" => %{"code" => "nothing_to_review"}} =
             reviews(c, %{"all_saved" => true}) |> json_response(422)
  end

  test "a token that changed since it was read is refused, and nothing is reviewed", c do
    old = save(c, c.first)["token"]
    save(c, c.first)

    assert %{"error" => %{"code" => code}} =
             reviews(c, %{"spacecraft" => %{c.first.spacecraft_id => old}}) |> json_response(409)

    assert code == "spacecraft_configuration_changed"
    assert %{"active" => nil} = workspace(c, c.first)
  end

  test "a malformed body is refused, field-keyed", c do
    for body <- [
          %{},
          %{"spacecraft" => %{}},
          %{"spacecraft" => %{"sc-1" => 5}},
          %{"spacecraft" => %{"sc-1" => "t"}, "all_saved" => true},
          %{"all_saved" => "yes"}
        ] do
      assert %{"error" => %{"code" => "invalid_params"}} =
               reviews(c, body) |> json_response(422)
    end

    assert %{"error" => %{"code" => "invalid_params"}} =
             conn(c)
             |> post(c.base <> "/configuration/reviews", %{"all_saved" => true})
             |> json_response(422)
  end
end
