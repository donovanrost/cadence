defmodule Cadence.Reads.CommandGroups.Page do
  @moduledoc """
  A command group's targets and events, paged (#795): a group of thousands of targets is never
  sent whole. Pure over a group view (`CommandGroups.get/4`), so a page and the summary it comes
  with are read from the same moment.

  - **Targets** are in target order (`index`), filterable by `stage` (a comma list of member
    stages, the target's own) and `q` (case-insensitive substring of the name or spacecraft id).
  - **Events** are chronological. The view carries the latest page, and a cursor walks back to
    older ones.

  A cursor is opaque and bound to the mission, the group and the sort it pages, so one from
  another group, mission or list is `{:error, :invalid_cursor}`.
  """

  alias Cadence.Commanding.Groups.CommandGroupEventRow

  @default_targets 100
  @max_targets 500
  @default_events 50
  @max_events 200
  @max_q 100
  # What "Needs you" lists: a target whose delivery failed or can't be told, and one whose lane is
  # held by a release of unknown outcome (`blocked`, which sits on a waiting target).
  @needs_you_stages ~w(verify_failed release_failed indeterminate)a
  @stages ~w(awaiting_go queued_for_contact radiating executed verified no_verifier verify_failed
             release_failed indeterminate canceled rejected excluded)

  @type error :: :invalid_cursor | {:invalid_params, map()}

  @doc "The view with its first pages: the first targets and the latest events, with their totals."
  @spec first(map()) :: map()
  def first(view) do
    {:ok, targets} = targets(view, %{})
    {:ok, events} = events(view, %{})

    view
    |> Map.put(:targets, targets.targets)
    |> Map.put(:targets_page, %{
      total: targets.total,
      revision: revision(view.targets),
      next_cursor: targets.next_cursor
    })
    |> Map.put(:events, events.events)
    |> Map.put(:events_page, %{total: events.total, next_cursor: events.next_cursor})
  end

  # Changes whenever any target, as a page shows it, does: a live client refetches its pages then.
  # It covers everything a page of targets shows (stage, `blocked`, each member's times, reasons and
  # release refusal), not just the stage, so a change a client would see on a page it holds moves it.
  defp revision(targets), do: :erlang.phash2(targets)

  @doc "A page of targets. `params`: `limit`, `cursor`, `stage`, `q` (strings, as on the wire)."
  @spec targets(map(), map()) ::
          {:ok, %{targets: [map()], total: non_neg_integer(), next_cursor: binary() | nil}}
          | {:error, error()}
  def targets(view, params) do
    with {:ok, limit} <- limit(params, @default_targets, @max_targets),
         {:ok, stages} <- stages(params["stage"]),
         {:ok, q} <- query(params["q"]),
         {:ok, needs_you} <- flag(params["needs_you"], "needs_you"),
         {:ok, after_index} <- cursor(view, params["cursor"], "targets") do
      matching =
        Enum.filter(
          view.targets,
          &(stage?(&1, stages) and named?(&1, q) and needs_you?(&1, needs_you))
        )

      remaining = Enum.filter(matching, &(after_index == nil or &1.index > after_index))
      page = Enum.take(remaining, limit)

      {:ok,
       %{
         targets: page,
         total: length(matching),
         next_cursor:
           if(length(remaining) > limit, do: encode(view, "targets", List.last(page).index))
       }}
    end
  end

  @doc """
  A page of events, newest last, optionally only of some `kind`s (a comma list). A cursor is the
  page before the one it came from.
  """
  @spec events(map(), map()) ::
          {:ok, %{events: [map()], total: non_neg_integer(), next_cursor: binary() | nil}}
          | {:error, error()}
  def events(view, params) do
    with {:ok, limit} <- limit(params, @default_events, @max_events),
         {:ok, kinds} <- kinds(params["kind"]),
         {:ok, before_key} <- cursor(view, params["cursor"], "events") do
      matching = Enum.filter(view.events, &(kinds == nil or to_string(&1.kind) in kinds))
      keyed = Enum.map(matching, &{key(&1), &1})
      older = Enum.filter(keyed, fn {k, _event} -> before_key == nil or k < before_key end)
      page = Enum.take(older, -limit)

      {:ok,
       %{
         events: Enum.map(page, &elem(&1, 1)),
         total: length(matching),
         next_cursor: if(length(older) > limit, do: encode(view, "events", elem(hd(page), 0)))
       }}
    end
  end

  defp key(%{at: at, id: id}), do: [DateTime.to_unix(at, :microsecond), id]

  defp limit(params, default, max) do
    case params["limit"] do
      nil ->
        {:ok, default}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {n, ""} when n in 1..max//1 -> {:ok, n}
          _other -> invalid("limit", "must be an integer from 1 to #{max}")
        end

      value when is_integer(value) and value in 1..max//1 ->
        {:ok, value}

      _other ->
        invalid("limit", "must be an integer from 1 to #{max}")
    end
  end

  defp stages(nil), do: {:ok, nil}

  defp stages(value) when is_binary(value) do
    stages = String.split(value, ",", trim: true)

    if stages != [] and Enum.all?(stages, &(&1 in @stages)),
      do: {:ok, MapSet.new(stages)},
      else: invalid("stage", "must be a comma list of #{Enum.join(@stages, " | ")}")
  end

  defp stages(_value), do: invalid("stage", "must be a comma list of target stages")

  defp kinds(nil), do: {:ok, nil}

  defp kinds(value) when is_binary(value) do
    kinds = String.split(value, ",", trim: true)

    if kinds != [] and Enum.all?(kinds, &(&1 in CommandGroupEventRow.kinds())),
      do: {:ok, kinds},
      else:
        invalid(
          "kind",
          "must be a comma list of #{Enum.join(CommandGroupEventRow.kinds(), " | ")}"
        )
  end

  defp kinds(_value), do: invalid("kind", "must be a comma list of event kinds")

  defp flag(nil, _field), do: {:ok, false}
  defp flag("true", _field), do: {:ok, true}
  defp flag("false", _field), do: {:ok, false}
  defp flag(_value, field), do: invalid(field, "must be true or false")

  defp needs_you?(_target, false), do: true

  defp needs_you?(target, true),
    do: target.stage in @needs_you_stages or not is_nil(target.blocked)

  defp query(nil), do: {:ok, nil}

  defp query(value) when is_binary(value) and byte_size(value) <= @max_q,
    do: {:ok, String.downcase(String.trim(value))}

  defp query(_value), do: invalid("q", "must be text of at most #{@max_q} characters")

  defp stage?(_target, nil), do: true
  defp stage?(target, stages), do: Atom.to_string(target.stage) in stages

  defp named?(_target, nil), do: true
  defp named?(_target, ""), do: true

  defp named?(target, q) do
    [target.name, target.spacecraft_id]
    |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), q)))
  end

  defp encode(view, sort, key) do
    %{"m" => view.group.mission_id, "g" => view.group.command_group_id, "s" => sort, "k" => key}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp cursor(_view, nil, _sort), do: {:ok, nil}

  defp cursor(view, cursor, sort) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"m" => mission, "g" => group, "s" => ^sort, "k" => key}} <- Jason.decode(raw),
         true <- mission == view.group.mission_id and group == view.group.command_group_id,
         true <- valid_key?(sort, key) do
      {:ok, key}
    else
      _foreign_or_malformed -> {:error, :invalid_cursor}
    end
  end

  defp cursor(_view, _cursor, _sort), do: {:error, :invalid_cursor}

  defp valid_key?("targets", key), do: is_integer(key)
  defp valid_key?("events", [at, id]), do: is_integer(at) and is_binary(id)
  defp valid_key?(_sort, _key), do: false

  defp invalid(field, message), do: {:error, {:invalid_params, %{field => message}}}
end
