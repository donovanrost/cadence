defmodule Cadence.Control.Commanding.GroupCreation do
  @moduledoc """
  Creates a command group from a draft: the one path for the console and for REST (a command is
  always a group, one target and one command being a group of one, #708).

  DECISIONS #60: HOLDs hold. Every HOLD in the current preflight is either acknowledged (key and
  hold_basis match, with a note) or refuses the submit. A replay of a known operation skips this,
  so it still answers `duplicate_operation` (U20).
  """

  alias Cadence.Auth.Scope
  alias Cadence.Commanding.Groups.CommandGroup
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.{CommandGroups, CommandPreflight}

  @doc """
  Options: `:preflight_digest`, `:operation_id`, `:draft_revision`, `:acknowledged_holds`.
  """
  @spec create(Scope.t(), binary(), map(), keyword()) ::
          {:ok, CommandGroup.t()} | {:error, term()}
  def create(%Scope{} = scope, mission_id, draft, opts) do
    operation_id = Keyword.get(opts, :operation_id)

    with {:ok, org, actor} <- GroupSubmission.requester(scope, mission_id),
         {:ok, accepted} <-
           holds_satisfied(
             org,
             mission_id,
             actor,
             draft,
             Keyword.get(opts, :acknowledged_holds, []),
             operation_id
           ) do
      GroupSubmission.submit(scope, mission_id, draft,
        preflight_digest: Keyword.get(opts, :preflight_digest),
        operation_id: operation_id,
        hold_acks: accepted,
        draft_revision: Keyword.get(opts, :draft_revision)
      )
    end
  end

  defp holds_satisfied(org, mission, actor, draft, acks, operation_id) do
    with :new <- replay(org, mission, operation_id),
         {:ok, preflight} <- CommandPreflight.run(org, mission, actor, draft) do
      case CommandPreflight.holds(preflight, acks) do
        %{unsatisfied: [], accepted: accepted} ->
          {:ok, Enum.map(accepted, &Map.put(&1, :preflight_digest, preflight.digest))}

        %{unsatisfied: holds} ->
          {:error, {:holds_unacknowledged, holds}}
      end
    else
      :replay -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay(_org, _mission, nil), do: :new

  defp replay(org, mission, operation_id) do
    case CommandGroups.fetch_by_operation(org, mission, operation_id) do
      {:ok, _group} -> :replay
      {:error, _none} -> :new
    end
  end
end
