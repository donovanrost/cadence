defmodule Mix.Tasks.Cadence.Config.LiftRouting do
  @moduledoc """
  Stages a change set that lifts a mission's per-spacecraft routing rules into profile routing
  rules (`docs/apogee/domain/profile-routing.md` §6B). Nothing changes until someone reviews
  and applies the change set in Setup › Changes; the preview shows every route it renames,
  creates or retires.

      mix cadence.config.lift_routing --mission-id MISSION --user-email EMAIL [--dry-run]

  The change is staged as EMAIL, who must be a member of the mission's organization.
  `--dry-run` prints the plan and the preview verdict without staging.
  """

  use Mix.Task

  alias Cadence.Accounts
  alias Cadence.Auth.Scope
  alias Cadence.Comms.RoutingLift
  alias Cadence.Control.Configuration
  alias Cadence.Missions

  @shortdoc "Stage a change set lifting per-spacecraft routing rules into profile rules"

  @impl true
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [mission_id: :string, user_email: :string, dry_run: :boolean]
      )

    if invalid != [] or is_nil(opts[:mission_id]) or is_nil(opts[:user_email]),
      do:
        Mix.raise(
          "usage: mix cadence.config.lift_routing --mission-id ID --user-email EMAIL [--dry-run]"
        )

    Mix.Task.run("app.start")

    with {:ok, scope, organization_id} <- scope(opts[:mission_id], opts[:user_email]),
         {:ok, %{ops: ops, summary: summary}} <-
           RoutingLift.ops(organization_id, opts[:mission_id]) do
      Mix.shell().info(
        "Lift plan: #{summary.rules} rule(s) on #{summary.profiles} profile(s), #{summary.overrides} override(s)."
      )

      stage(scope, opts[:mission_id], ops, opts[:dry_run])
    else
      {:error, reason} -> Mix.raise("lift_routing failed: #{inspect(reason)}")
    end
  end

  defp stage(_scope, _mission_id, [], _dry_run), do: Mix.shell().info("Nothing to lift.")

  defp stage(scope, mission_id, ops, true) do
    case Configuration.preview(scope, mission_id, {:ops, ops}) do
      {:ok, preview} ->
        Mix.shell().info("Dry run: preview verdict #{preview.verdict}. Nothing staged.")

      {:error, reason} ->
        Mix.raise("preview failed: #{inspect(reason)}")
    end
  end

  defp stage(scope, mission_id, ops, _dry_run) do
    attrs = %{
      summary: "Lift per-spacecraft routing rules into profile rules",
      source: %{"tool" => "cadence.config.lift_routing"}
    }

    case Configuration.stage(scope, mission_id, attrs, ops) do
      {:ok, staged} ->
        Mix.shell().info(
          "Staged change #{staged.change_id} in change set #{staged.change_set_id} " <>
            "(base r#{staged.base_revision}). Review and apply it in Setup › Changes."
        )

      {:error, reason} ->
        Mix.raise("staging failed: #{inspect(reason)}")
    end
  end

  defp scope(mission_id, email) do
    with organization_id when is_binary(organization_id) <-
           Missions.organization_id_for_mission(mission_id),
         {:ok, user} <- Accounts.fetch_user_by_email(email),
         {:ok, membership} <- Accounts.fetch_user_membership(user.user_id, organization_id) do
      {:ok,
       Scope.new(%{
         user: user,
         organization_membership: membership,
         organization_id: organization_id
       }), organization_id}
    else
      nil -> {:error, :mission_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
