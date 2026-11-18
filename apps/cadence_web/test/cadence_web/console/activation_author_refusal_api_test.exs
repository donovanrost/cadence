defmodule CadenceWeb.Console.ActivationAuthorRefusalAPITest do
  @moduledoc """
  #236 on L10: an author of a spacecraft configuration can't approve its activation, even when
  someone else submitted it. The refusal is a 403 naming the spacecraft they saved, and nothing
  is recorded; another person approves.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Governance.ActivationPolicy
  alias CadenceWeb.Console.ApproveRefusals
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)

    people =
      for name <- ["Author A", "Submitter B", "Approver C"] do
        user = TestFixtures.persist_user!(display_name: name)
        membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
        {user, scope(user, org, mission, membership)}
      end

    [{a, a_scope}, {_b, b_scope}, {approver, _}] = people

    {craft, revision, _endpoint} =
      CatalogFixtures.setup_imported_mission!(org.organization_id, mission.mission_id)

    policy = ActivationPolicy.load(org.organization_id, mission.mission_id)

    {:ok, _} =
      ActivationPolicy.save(a_scope, mission.mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })

    {:ok, mission} = Cadence.Missions.fetch_mission(org.organization_id, mission.mission_id)
    save!(a_scope, mission, craft, revision.catalog_revision_id, [42])
    save!(b_scope, mission, craft, revision.catalog_revision_id, [42])

    token = Drafts.snapshot(mission, craft).token

    {:ok, request} =
      Review.request_many(b_scope, mission.mission_id, %{craft.spacecraft_id => token})

    %{
      author: a,
      approver: approver,
      craft: craft,
      request: request,
      base: "/api/console/v1/missions/#{mission.mission_id}/activations"
    }
  end

  test "the author is refused with the spacecraft named, nothing is recorded; someone else approves",
       c do
    id = c.craft.spacecraft_id
    name = c.craft.display_name
    path = c.base <> "/#{c.request.activation_request_id}"

    assert %{
             "error" => %{
               "code" => "activation_approver_authored_content",
               "message" => message,
               "details" => %{
                 "spacecraft_ids" => [^id],
                 "spacecraft" => [%{"id" => ^id, "name" => ^name}]
               }
             }
           } =
             c.author
             |> TestFixtures.member_conn()
             |> post(path <> "/approve", %{"reason" => "Reviewed"})
             |> json_response(403)

    assert message ==
             "Not approved: you saved #{name}'s configuration in this request, so another person " <>
               "approves it. Your approval wasn't recorded."

    assert %{"state" => "approval_pending", "decision" => nil} =
             c.author |> TestFixtures.member_conn() |> get(path) |> json_response(200) |> data()

    assert %{"request" => %{"state" => "approved"}} =
             c.approver
             |> TestFixtures.member_conn()
             |> post(path <> "/approve", %{"reason" => "Reviewed"})
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "several spacecraft: up to three named, then the count (ux)" do
    named = fn names -> Enum.map(names, &%{id: &1, name: &1}) end

    line = fn ids, names ->
      build_conn()
      |> ApproveRefusals.authored(%{
        spacecraft_ids: ids,
        spacecraft: named.(names)
      })
      |> json_response(403)
      |> get_in(["error", "message"])
    end

    assert line.(~w(a b), ~w(A-1 A-2)) =~ "the configurations of A-1 and A-2 in this request"

    assert line.(~w(a b c d e), ~w(A-1 A-2 A-3 A-4 A-5)) =~
             "the configurations of A-1, A-2, A-3 and 2 more spacecraft in this request"

    assert line.(~w(a), [nil] |> Enum.map(& &1)) =~
             "you saved part of what this request activates"
  end

  defp data(%{"data" => %{"request" => request}}), do: request
  defp data(%{"data" => request}), do: request

  defp save!(scope, mission, craft, catalog, apids) do
    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
        "handled_apids" => apids
      })

    {:ok, _} =
      Drafts.save(
        scope,
        mission.mission_id,
        craft.spacecraft_id,
        Drafts.snapshot(mission, craft).token,
        document
      )
  end

  defp scope(user, org, mission, membership) do
    %Scope{
      actor_kind: :user,
      user: user,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }
  end
end
