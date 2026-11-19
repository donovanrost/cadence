defmodule Cadence.Commanding.Drafts do
  @moduledoc """
  Compose's current draft per user per mission (director, BACKLOG ac293f6c). The document is the
  editor's state and is opaque here. A draft is inert: nothing else reads it, and submitting a
  group revalidates its own body in full. Writes are optimistic on `revision`, so a second tab
  can't silently overwrite the first. A draft idle for `@idle_days` reads as gone and is deleted
  on the next read or write.
  """

  import Ecto.Query

  alias Cadence.Commanding.Drafts.DraftRow
  alias Cadence.Repo

  @idle_days 30

  @type owner :: {String.t(), String.t(), String.t()}

  @doc "The owner's draft, or `:command_draft_not_found` (none, or idle past #{@idle_days} days)."
  @spec fetch(owner(), DateTime.t()) :: {:ok, DraftRow.t()} | {:error, :command_draft_not_found}
  def fetch(owner, now \\ DateTime.utc_now()) do
    case Repo.one(owned(owner)) do
      nil ->
        {:error, :command_draft_not_found}

      row ->
        if idle?(row, now) do
          Repo.delete_all(owned(owner))
          {:error, :command_draft_not_found}
        else
          {:ok, row}
        end
    end
  end

  @doc """
  Saves the owner's draft when `expected` is the revision stored (`nil`: there is none yet, or
  only an idle one). Otherwise `{:error, {:command_draft_changed, current}}`.
  """
  @spec put(owner(), map(), non_neg_integer() | nil, String.t() | nil, DateTime.t()) ::
          {:ok, DraftRow.t()} | {:error, {:command_draft_changed, DraftRow.t()}}
  def put({org, mission, user} = owner, document, expected, catalog_revision_id, now) do
    Repo.transaction(fn ->
      current = owner |> owned() |> lock("FOR UPDATE") |> Repo.one()
      current = if current && idle?(current, now), do: nil, else: current

      case {current, expected} do
        {nil, nil} -> :ok
        {%DraftRow{revision: revision}, revision} -> :ok
        {nil, _stale} -> Repo.rollback({:command_draft_changed, nil})
        {row, _stale} -> Repo.rollback({:command_draft_changed, row})
      end

      Repo.insert!(
        %DraftRow{
          organization_id: org,
          mission_id: mission,
          user_id: user,
          revision: ((current && current.revision) || 0) + 1,
          document: document,
          catalog_revision_id: catalog_revision_id,
          saved_at: now
        },
        on_conflict: {:replace, [:revision, :document, :catalog_revision_id, :saved_at]},
        conflict_target: [:organization_id, :mission_id, :user_id]
      )
    end)
  end

  @doc "Discards the owner's draft (idempotent)."
  @spec delete(owner()) :: :ok
  def delete(owner) do
    Repo.delete_all(owned(owner))
    :ok
  end

  @doc """
  Deletes the owner's draft only if it is still at `revision` (a submitted group's draft), so a
  newer autosave from another tab survives. Call inside the submit transaction.
  """
  @spec consume(owner(), pos_integer() | nil) :: :ok
  def consume(_owner, nil), do: :ok

  def consume(owner, revision) do
    owner |> owned() |> where([d], d.revision == ^revision) |> Repo.delete_all()
    :ok
  end

  defp owned({org, mission, user}) do
    where(
      DraftRow,
      [d],
      d.organization_id == ^org and d.mission_id == ^mission and d.user_id == ^user
    )
  end

  defp idle?(row, now), do: DateTime.diff(now, row.saved_at) > @idle_days * 86_400
end
