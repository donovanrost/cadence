defmodule Cadence.Management.Commanding.ReviewAccess do
  @moduledoc "Fresh human authorization for command request review and decisions."
  alias Cadence.{Accounts, Ids, Missions}
  alias Cadence.Accounts.User
  alias Cadence.Auth.{Policy, Scope}

  def authorize(%Scope{actor_kind: :user, user: %{user_id: user_id}} = scope, mission_id) do
    with true <- is_binary(scope.organization_id) and scope.mission_id in [nil, mission_id],
         {:ok, _} <- Ids.path_segment(mission_id),
         {:ok, %User{lifecycle_state: :active} = user} <- Accounts.fetch_user(user_id),
         {:ok, membership} <- membership(scope, user),
         fresh =
           Scope.new(%{
             user: user,
             organization_id: scope.organization_id,
             organization_membership: membership,
             admin_mode?: scope.admin_mode?
           }),
         fresh = %{fresh | mission_id: scope.mission_id},
         :ok <- policy(fresh, mission_id),
         {:ok, mission} <- Missions.fetch_mission(fresh.organization_id, mission_id) do
      {:ok, fresh, mission}
    else
      _ -> {:error, :unavailable}
    end
  end

  def authorize(_, _), do: {:error, :unavailable}

  @doc """
  The console capability names (`command.request`, `command.approve`) that
  `scope` holds in its organization, from the same policy `authorize/2`
  enforces (DECISIONS #38). Requesting and reviewing share this one rule today
  (`command.abort` is `GroupAbort.capabilities/1`, DECISIONS #42);
  the two-person rule still forbids approving your own request. If one of them
  moves to its own rule, its name moves with it. The rule needs a mission, so
  for an organization-level answer it's evaluated against the organization's
  missions (held if any passes), as abort's is.
  """
  @spec capabilities(Scope.t()) :: [binary()]
  def capabilities(
        %Scope{actor_kind: :user, user: %User{lifecycle_state: :active}, organization_id: org} =
          scope
      )
      when is_binary(org) do
    missions =
      case scope.mission_id do
        nil -> org |> Missions.list_missions() |> Enum.map(& &1.mission_id)
        mission_id -> [mission_id]
      end

    if Enum.any?(missions, &(policy(scope, &1) == :ok)),
      do: ["command.request", "command.approve"],
      else: []
  end

  def capabilities(%Scope{}), do: []

  # DECISIONS #62: any mission operator may request commands and decide on them (GO, NO-GO,
  # send back), not only organization admins. Self-approval and the two-person rule are enforced
  # separately and don't change.
  # todo(authz): Cedar should decide per action (request, approve, no-go, send back, stage,
  # queue) and per command: significance, hazardous/critical flags, subsystem and target set
  # (e.g. a mission role allowed to request but not approve, or approve only non-hazardous).
  defp policy(scope, mission_id),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      })

  defp membership(scope, user) do
    case Accounts.fetch_user_membership(user.user_id, scope.organization_id) do
      {:ok, %{lifecycle_state: :active} = membership} ->
        {:ok, membership}

      _ ->
        if Scope.admin_mode?(Scope.new(%{user: user, admin_mode?: scope.admin_mode?})),
          do: {:ok, nil},
          else: {:error, :unavailable}
    end
  end
end
