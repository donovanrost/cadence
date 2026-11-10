defmodule Cadence.Control.Commanding.GroupNotes do
  @moduledoc """
  Request log notes on a command group (M19): an append-only `note` event by
  the session operator, allowed in any group state (including finished ones,
  for the shift record).
  """

  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.Platform.ScopedReadUpdates

  @max_bytes 4_000

  @spec add(Cadence.Auth.Scope.t(), binary(), binary(), binary()) :: :ok | {:error, term()}
  # todo(authz): Cedar should decide who may add notes to a group (any mission operator today).
  def add(scope, mission_id, group_id, note) do
    with {:ok, fresh, _mission} <- RequestAuthoring.authorize(scope, mission_id),
         {:ok, note} <- valid_note(note),
         {:ok, _group} <- GroupStore.fetch(fresh.organization_id, mission_id, group_id) do
      :ok =
        GroupStore.append_events([
          %{
            command_group_id: group_id,
            mission_id: mission_id,
            kind: :note,
            actor: %{"actor_kind" => "user", "user_id" => fresh.user.user_id},
            payload: %{"note" => note}
          }
        ])

      ScopedReadUpdates.publish(:commanding_changed, fresh.organization_id, mission_id)
    end
  end

  defp valid_note(note) when is_binary(note) and byte_size(note) <= @max_bytes do
    case String.trim(note) do
      "" -> {:error, :note_required}
      trimmed -> {:ok, trimmed}
    end
  end

  defp valid_note(_note), do: {:error, :note_required}
end
