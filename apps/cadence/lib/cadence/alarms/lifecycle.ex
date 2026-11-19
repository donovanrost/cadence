defmodule Cadence.Alarms.Lifecycle do
  @moduledoc """
  Operator actions on alarm episodes: acknowledge, assign, hand off, note. Callers resolve and
  authorize first (`Cadence.Control.Alarms`); an assignee arrives as `%{"id", "name"}`, already
  checked to be a member.

  Each runs under `SELECT … FOR UPDATE` on the episode, so it serializes with a concurrent
  escalation or auto-clear. Acting on a cleared episode returns `{:error, :episode_cleared}`;
  notes are allowed on cleared episodes (post-mortems).
  """

  import Ecto.Query

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow}
  alias Cadence.Ids
  alias Cadence.Repo

  @note_bytes 1..2_000

  @spec acknowledge(String.t(), String.t(), map(), String.t() | nil) ::
          {:ok, EpisodeRow.t()} | {:error, term()}
  def acknowledge(mission_id, episode_id, actor, note) do
    with {:ok, note} <- optional_note(note),
         do: locked(mission_id, episode_id, &acknowledge_active(&1, actor, note))
  end

  @spec assign(String.t(), String.t(), map(), map() | nil, String.t() | nil) ::
          {:ok, EpisodeRow.t()} | {:error, term()}
  def assign(mission_id, episode_id, actor, assignee, note) do
    with {:ok, note} <- optional_note(note),
         do: locked(mission_id, episode_id, &assign_active(&1, actor, assignee, note, nil))
  end

  @spec hand_off(String.t(), String.t(), map(), map() | nil, String.t()) ::
          {:ok, EpisodeRow.t()} | {:error, term()}
  def hand_off(mission_id, episode_id, actor, assignee, note) do
    with {:ok, note} <- required_note(note),
         do: locked(mission_id, episode_id, &assign_active(&1, actor, assignee, nil, note))
  end

  @spec add_note(String.t(), String.t(), map(), String.t()) ::
          {:ok, EpisodeRow.t()} | {:error, term()}
  def add_note(mission_id, episode_id, actor, note) do
    with {:ok, note} <- required_note(note) do
      locked(mission_id, episode_id, fn episode ->
        event(episode, "note", actor, %{"note" => note})
        {:ok, episode}
      end)
    end
  end

  defp acknowledge_active(episode, actor, note) do
    with :ok <- active(episode), do: acknowledge_locked(episode, actor, note)
  end

  defp assign_active(episode, actor, assignee, note, handoff_note) do
    with :ok <- active(episode),
         do: assign_locked(episode, actor, assignee, note, handoff_note)
  end

  defp acknowledge_locked(%EpisodeRow{acknowledged_at: %DateTime{}} = episode, actor, note) do
    if note, do: event(episode, "note", actor, %{"note" => note})
    {:ok, episode}
  end

  defp acknowledge_locked(episode, actor, note) do
    now = DateTime.utc_now()
    event(episode, "acknowledged", actor, %{"note" => note})

    episode
    |> Ecto.Changeset.change(acknowledged_at: now, acknowledged_by: actor)
    |> Repo.update()
  end

  defp assign_locked(episode, actor, assignee, note, handoff_note) do
    kind =
      cond do
        handoff_note -> "handed_off"
        is_nil(assignee) -> "unassigned"
        true -> "assigned"
      end

    event(episode, kind, actor, %{
      "from" => episode.assignee,
      "to" => assignee,
      "note" => handoff_note || note
    })

    episode
    |> Ecto.Changeset.change(
      assignee: assignee,
      assigned_at: if(assignee, do: DateTime.utc_now())
    )
    |> Repo.update()
  end

  defp locked(mission_id, episode_id, fun) do
    Repo.transaction(fn ->
      EpisodeRow
      |> where([e], e.mission_id == ^mission_id and e.episode_id == ^episode_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> case do
        nil -> Repo.rollback(:episode_not_found)
        episode -> unwrap(fun.(episode))
      end
    end)
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: Repo.rollback(reason)

  defp active(%EpisodeRow{state: "active"}), do: :ok
  defp active(%EpisodeRow{}), do: {:error, :episode_cleared}

  defp event(episode, kind, actor, payload) do
    Repo.insert!(%EpisodeEventRow{
      event_id: Ids.new("alarm_event"),
      episode_id: episode.episode_id,
      organization_id: episode.organization_id,
      mission_id: episode.mission_id,
      kind: kind,
      actor: actor,
      at: DateTime.utc_now(),
      payload: payload
    })
  end

  defp optional_note(nil), do: {:ok, nil}
  defp optional_note(note), do: required_note(note)

  defp required_note(note) when is_binary(note) do
    trimmed = String.trim(note)
    if byte_size(trimmed) in @note_bytes, do: {:ok, trimmed}, else: {:error, :note_required}
  end

  defp required_note(_note), do: {:error, :note_required}
end
