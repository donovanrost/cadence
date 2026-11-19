defmodule CadenceWeb.Console.ActivationAuthorRefusalAPITest do
  @moduledoc """
  #236 on L10: an author of a spacecraft configuration can't approve its activation, even when
  someone else submitted it. The refusal is a 403 naming the spacecraft they saved, and nothing
  is recorded; another person approves.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceAccountableRow, ServiceIdentity}
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.ActivationRequests.Refusals
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Repo
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
      org: org,
      mission: mission,
      author_scope: a_scope,
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

  test "authors that can't be determined fail closed: a 403 naming the craft, in ux's words", c do
    id = c.craft.spacecraft_id
    name = c.craft.display_name

    assert {:error,
            {:activation_approver_authors_unknown,
             %{spacecraft_ids: [^id], spacecraft: [%{id: ^id, name: ^name}], service: nil} =
               details}} =
             Refusals.explain(
               {:error, {:activation_approver_authors_unknown, [id]}},
               c.request.organization_id,
               c.request.mission_id,
               c.request
             )

    # ux U100: the code's details always carry `service`, null when no service is involved.
    assert %{
             "error" => %{
               "code" => "activation_approver_authors_unknown",
               "message" => "Not approved: Cadence can't tell who saved this configuration" <> _,
               "details" => %{"service" => nil, "spacecraft_ids" => [^id]}
             }
           } =
             build_conn()
             |> ApproveRefusals.authors_unknown(details)
             |> json_response(403)
  end

  # #280 (mms-security's #435) under the same code (ux U100): a service with nobody recorded as
  # accountable for it requested the review, so nobody may approve it. details.service names it,
  # and so does the line: U100's, never U94's configuration line and never the service's id.
  test "a service with nobody on record requested it: a 403 naming the service (#280, U100)", c do
    {:ok, %{service_identity: service}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: c.org.organization_id,
          mission_id: c.mission.mission_id,
          display_name: "Rollout bot",
          capabilities: [:mission_admin]
        }),
        c.author_scope
      )

    service_scope =
      Scope.new(%{
        organization_id: c.org.organization_id,
        organization: c.org,
        service_identity: service
      })

    # A service may request a binding-set activation (a spacecraft configuration review needs a
    # person), so this one is the service's.
    binding_set =
      BindingSet.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        binding_set_id: "binding-set-service-#{System.unique_integer([:positive])}",
        version: 1
      })

    {:ok, _} = Cadence.Governance.persist_binding_set(c.org.organization_id, binding_set)

    {:ok, request} =
      ManagementActivations.request(
        service_scope,
        c.mission.mission_id,
        binding_set.binding_set_id,
        binding_set.version
      )

    forget_accountables!(service.service_identity_id)

    id = service.service_identity_id
    path = c.base <> "/#{request.activation_request_id}"

    assert %{
             "error" => %{
               "code" => "activation_approver_authors_unknown",
               "message" => message,
               "details" => %{"service" => %{"id" => ^id, "name" => "Rollout bot"}}
             }
           } =
             c.approver
             |> TestFixtures.member_conn()
             |> post(path <> "/approve", %{"reason" => "Reviewed"})
             |> json_response(403)

    assert message ==
             "Not approved: Rollout bot has no one recorded as accountable for it, so this can't " <>
               "be approved yet. An org admin records who's accountable in People › Service " <>
               "identities. Your approval wasn't recorded."

    assert %{"state" => "approval_pending", "decision" => nil} =
             c.approver |> TestFixtures.member_conn() |> get(path) |> json_response(200) |> data()

    # A service whose name can't be read is never shown by its id (U25).
    assert %{
             "error" => %{
               "message" => "Not approved: a service identity involved in this request" <> _
             }
           } =
             build_conn()
             |> ApproveRefusals.authors_unknown(%{service: %{id: id, name: nil}})
             |> json_response(403)
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

  # The accountables table is append-only (#436): #116's test-only purge, on for the delete only.
  defp forget_accountables!(service_identity_id) do
    Repo.query!("SET LOCAL cadence.decision_record_test_purge = 'on'")

    Repo.delete_all(
      from(row in ServiceAccountableRow, where: row.service_identity_id == ^service_identity_id)
    )

    Repo.query!("SET LOCAL cadence.decision_record_test_purge = 'off'")
  end
end
