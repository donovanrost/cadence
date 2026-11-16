defmodule Cadence.Reads.ConfigRevisionEvents do
  @moduledoc """
  Applied configuration revisions as mission timeline entries (Timeline `config` events,
  BACKLOG §8 8d): "Applied r6 · 2 changes", or "Rolled back to r4" for a rollback revision.
  The same facts the organization Audit read lists (`Cadence.Reads.OrganizationAudit`), less
  the baseline revision.

  Revisions aren't projected into the mission-events table, so `Cadence.Reads.MissionTimeline`
  merges these in when asked (`config_revisions: true`). They're mission-wide: no spacecraft.
  """

  alias Cadence.Configuration.Status
  alias Cadence.MissionEvents.Entry

  @page 200
  @max_pages 5

  @doc """
  Applied revisions with `applied_at` in `[from_occurred_at, to_occurred_at)` (either may be
  nil), newest first. Reads at most #{@page * @max_pages} revisions back.
  """
  @spec entries(binary(), binary(), keyword()) :: [Entry.t()]
  def entries(organization_id, mission_id, opts \\ []) do
    from = Keyword.get(opts, :from_occurred_at)
    to = Keyword.get(opts, :to_occurred_at)

    organization_id
    |> revisions(mission_id, from, nil, @max_pages)
    # The baseline (r1) is written the first time anything reads the ledger, not by an apply.
    |> Enum.reject(&(to_string(&1.kind) == "baseline"))
    |> Enum.filter(&(&1.applied_at && in_window?(&1.applied_at, from, to)))
    |> Enum.map(&entry(mission_id, &1))
  end

  @doc "One applied revision's entry by its number (a Timeline permalink), else `:error`."
  @spec entry_for(binary(), binary(), pos_integer()) :: {:ok, Entry.t()} | :error
  def entry_for(organization_id, mission_id, number) when is_integer(number) and number > 0 do
    case Status.list_revisions(organization_id, mission_id, limit: 1, before: number + 1) do
      [%{revision: ^number, applied_at: %DateTime{}} = revision] ->
        if to_string(revision.kind) == "baseline",
          do: :error,
          else: {:ok, entry(mission_id, revision)}

      _other ->
        :error
    end
  end

  @doc "The operator sentence for a revision entry."
  @spec sentence(Entry.t()) :: binary()
  def sentence(%Entry{metadata: %{"rolls_back_to" => target}}) when is_integer(target),
    do: "Rolled back to r#{target}"

  def sentence(%Entry{metadata: metadata}),
    do: "Applied r#{metadata["revision"]} · #{changes(metadata["entry_count"])}"

  @doc "`refs.subject` for a revision entry: the revision page's link target."
  @spec subject(Entry.t()) :: map()
  def subject(%Entry{metadata: %{"revision" => number}}),
    do: %{kind: "config_revision", id: Integer.to_string(number), name: "r#{number}"}

  # Newest first, a page at a time, until a page reaches back past `from` or runs out.
  defp revisions(_org, _mission, _from, _before, 0), do: []

  defp revisions(org, mission, from, before, pages) do
    page = Status.list_revisions(org, mission, limit: @page, before: before)
    oldest = List.last(page)

    if length(page) < @page or reaches_back?(oldest, from),
      do: page,
      else: page ++ revisions(org, mission, from, oldest.revision, pages - 1)
  end

  defp reaches_back?(_oldest, nil), do: false
  defp reaches_back?(%{applied_at: nil}, _from), do: false
  defp reaches_back?(%{applied_at: at}, from), do: DateTime.compare(at, from) == :lt

  defp entry(mission_id, revision) do
    rollback? = is_integer(revision.rolls_back_to)

    Entry.new(%{
      mission_id: mission_id,
      source_record_kind: :config_revision,
      source_record_id: Integer.to_string(revision.revision),
      occurred_at: revision.applied_at,
      category: :operations,
      kind: if(rollback?, do: :config_revision_rolled_back, else: :config_revision_applied),
      severity: :info,
      title: "r#{revision.revision}",
      summary: revision.summary,
      subject_kind: :config_revision,
      subject_id: Integer.to_string(revision.revision),
      activation_id: revision.activation_id,
      actor: actor(revision.applied_by),
      metadata: %{
        "revision" => revision.revision,
        "entry_count" => revision.entry_count,
        "rolls_back_to" => revision.rolls_back_to,
        "change_set_id" => revision.change_set_id,
        "reason" => revision.reason
      }
    })
  end

  defp actor(%{kind: kind, id: id}), do: %{"kind" => kind, "id" => id}
  defp actor(_none), do: %{}

  defp in_window?(at, from, to),
    do:
      (is_nil(from) or DateTime.compare(at, from) != :lt) and
        (is_nil(to) or DateTime.compare(at, to) == :lt)

  defp changes(1), do: "1 change"
  defp changes(n), do: "#{n || 0} changes"
end
