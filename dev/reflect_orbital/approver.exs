defmodule Cadence.Dev.ReflectOrbital.Approver do
  @moduledoc """
  A second, synthetic Reflect Orbital organization admin. It approves seeded mission-model
  revisions and route change sets through the same functions as the Console, including
  authorization and separation of duties.

  User decision 11-25 (#250, #727): dev seeds may approve, execute and activate, through public
  domain functions as seeded dev accounts. No bypass flags, no system actors, no row inserts.
  The account joins through an ordinary invitation. Its password is random per seed run and
  never printed: nobody signs in as it.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Control.Configuration
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.Reads.MissionModelApprovals

  @email "earendil-approver@example.com"
  @display_name "Earendil approver (dev seed)"

  @doc "The approver's scope, inviting and joining it on first use. `inviter` is an org admin."
  def scope(inviter) do
    user = ensure_member(inviter)
    {:ok, organization} = Cadence.Organizations.fetch_organization(F.organization_id())

    {:ok, membership} =
      Cadence.Accounts.fetch_user_membership(user.user_id, F.organization_id())

    Scope.new(%{user: user, organization: organization, organization_membership: membership})
  end

  @doc "Compares and approves every candidate mission-model revision of Earendil."
  def approve_candidates(scope) do
    F.organization_id()
    |> Cadence.MissionModels.list_revisions(F.mission_id(), status: :candidate)
    |> Enum.map(fn revision ->
      id = revision.revision_id

      {:ok, %{report_id: report_id, passed: true}} =
        MissionModelApprovals.compare(scope, F.mission_id(), id)

      {:ok, _approved} =
        MissionModelApprovals.approve(scope, F.mission_id(), id, report_id, "dev-seed-#{id}")

      id
    end)
  end

  def approve_route_changes(:applied, %Scope{}, _mission_id), do: :applied

  def approve_route_changes({:in_review, id, version}, %Scope{} = scope, mission_id) do
    # TODO(#745, #752): review through a second admin's REST session from the dev invitation.
    case Configuration.review(scope, mission_id, id, :approve, %{
           comment: "Approve the seeded extra routes",
           expected_version: version
         }) do
      {:ok, %{state: :applied}} ->
        IO.puts("Mission #{mission_id}: the seeded second admin approved route change set #{id}.")
        :applied

      result ->
        raise "Could not approve route change set #{id} for mission #{mission_id}: #{inspect(result)}"
    end
  end

  defp ensure_member(inviter) do
    case Cadence.Accounts.fetch_user_by_email(@email) do
      {:ok, user} ->
        case Cadence.Accounts.fetch_user_membership(user.user_id, F.organization_id()) do
          {:ok, _membership} -> user
          {:error, :not_found} -> grant(user, inviter)
        end

      {:error, _not_found} ->
        invite_and_join(inviter)
    end
  end

  defp grant(user, inviter) do
    {:ok, %{mode: :granted}} =
      Cadence.Accounts.establish_organization_access(@email, F.organization_id(),
        membership_role: :organization_admin,
        invited_by_user_id: inviter.user_id
      )

    user
  end

  defp invite_and_join(inviter) do
    {:ok, %{mode: :invited, invitation_token: token}} =
      Cadence.Accounts.establish_organization_access(@email, F.organization_id(),
        membership_role: :organization_admin,
        invited_by_user_id: inviter.user_id,
        display_name: @display_name,
        force_invitation: true
      )

    {:ok, %{user: user}} =
      Cadence.Accounts.accept_organization_invitation(token, %{
        "display_name" => @display_name,
        "password" => Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      })

    user
  end
end
