defmodule Cadence.Control.Commanding.CommandDrafts do
  @moduledoc """
  Compose's current draft (director, BACKLOG ac293f6c; contract commanding.md §Compose draft):
  one per user per mission, overwritten by autosave, visible only to its author. It's inert, and
  submitting a group revalidates the group body in full; nothing is trusted from a draft.

  The document is the editor's state (raw argument text included, so invalid values survive a
  reload). It is checked only for shape (`schema_version` 1, a `stack` of `command_id`s) and
  size. The read adds a catalog block: the catalog revision the draft was saved against, the
  current one, and the stacked commands the current catalog no longer has.
  """

  alias Cadence.Commanding.Drafts
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.Reads.MissionModels.ActiveBasis

  @max_bytes 256 * 1024
  @max_stack 500

  @spec fetch(Cadence.Auth.Scope.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(scope, mission_id) do
    with {:ok, owner} <- owner(scope, mission_id),
         {:ok, row} <- Drafts.fetch(owner) do
      {:ok, view(row, catalog(owner, row))}
    end
  end

  @doc "Saves the caller's draft at `expected_revision` (nil for the first save)."
  @spec put(Cadence.Auth.Scope.t(), String.t(), term(), term()) ::
          {:ok, map()} | {:error, term()}
  def put(scope, mission_id, document, expected_revision) do
    with {:ok, owner} <- owner(scope, mission_id),
         :ok <- revision(expected_revision),
         :ok <- shape(document) do
      {org, mission, _user} = owner
      catalog_revision_id = current_catalog(org, mission)[:revision_id]

      case Drafts.put(owner, document, expected_revision, catalog_revision_id, DateTime.utc_now()) do
        {:ok, row} -> {:ok, %{revision: row.revision, saved_at: row.saved_at}}
        {:error, {:command_draft_changed, row}} -> {:error, {:command_draft_changed, saved(row)}}
      end
    end
  end

  @spec delete(Cadence.Auth.Scope.t(), String.t()) :: :ok | {:error, term()}
  def delete(scope, mission_id) do
    with {:ok, owner} <- owner(scope, mission_id), do: Drafts.delete(owner)
  end

  # todo(authz): Cedar should decide who may keep a command draft; today it's whoever may
  # request commands for the mission (DECISIONS #62), and only for their own draft.
  defp owner(scope, mission_id) do
    case RequestAuthoring.authorize(scope, mission_id) do
      {:ok, fresh, _mission} -> {:ok, {fresh.organization_id, mission_id, fresh.user.user_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revision(nil), do: :ok
  defp revision(n) when is_integer(n) and n > 0, do: :ok

  defp revision(_other),
    do:
      {:error, {:invalid_params, %{"expected_revision" => "must be null or a positive integer"}}}

  defp shape(%{"schema_version" => 1, "stack" => stack} = document) when is_list(stack) do
    cond do
      byte_size(Jason.encode!(document)) > @max_bytes ->
        {:error, {:invalid_params, %{"document" => "must be at most #{@max_bytes} bytes"}}}

      length(stack) > @max_stack or not Enum.all?(stack, &stack_item?/1) ->
        {:error,
         {:invalid_params,
          %{"document.stack" => "must be up to #{@max_stack} items, each with a command_id"}}}

      true ->
        :ok
    end
  end

  defp shape(_document),
    do:
      {:error,
       {:invalid_params, %{"document" => "must be an object with schema_version 1 and a stack"}}}

  defp stack_item?(%{"command_id" => id}) when is_binary(id) and id != "", do: true
  defp stack_item?(_item), do: false

  defp view(row, catalog) do
    %{revision: row.revision, saved_at: row.saved_at, document: row.document, catalog: catalog}
  end

  defp saved(nil), do: %{revision: nil, saved_at: nil}
  defp saved(row), do: %{revision: row.revision, saved_at: row.saved_at}

  defp catalog({org, mission, _user}, row) do
    current = current_catalog(org, mission)
    known = Map.get(current, :command_ids)

    stacked =
      for %{"command_id" => id} <- row.document["stack"] || [], uniq: true, do: id

    %{
      revision_saved: row.catalog_revision_id,
      revision_now: Map.get(current, :revision_id),
      # Unknown (no active catalog) reads as nothing known missing; Compose's catalog says why.
      missing_command_ids:
        if(known, do: Enum.reject(stacked, &MapSet.member?(known, &1)), else: [])
    }
  end

  # The active command catalog's mission-model revision and its command ids, or %{} when none is
  # active. Read without the activation lock (as preflight does).
  defp current_catalog(org, mission) do
    case ActiveBasis.command_catalog_snapshot(org, mission) do
      {:ok, snapshot} ->
        %{
          revision_id: snapshot.basis.mission_model_revision_id,
          command_ids: MapSet.new(snapshot.catalog.runtime_definitions, & &1.command_id)
        }

      _unavailable ->
        %{}
    end
  end
end
