defmodule Cadence.MissionModels.Selection do
  @moduledoc """
  Which revision a pinned composition runs (D3, #544; design §3's selection rule, agreed on #559
  by api-ops and mms-security): the newest APPROVED, RUNNABLE revision linked to the composition
  with no authored head, its **base**. A craft runs that base compiled at the mission's authored
  head (P3 M1, #451; `Compositions.effective_revision/5`), whose approval is the base's
  (`MissionModels.effective_statuses/3`), so selection itself never looks at heads.

  - **Runnable** is `runnable/0`: an explicit list, in code, of the compiler versions whose plans
    this server executes (api-ops). A revision of any other version is never selected. A test
    holds every listed version to a stored revision that `MissionModelPlanDecoder` decodes, so the
    list can't claim more than the runtime runs (domain).
  - **Newest** is a fixed order on the link rows: the version's position in `runnable/0`
    (never string order: '10' is newer than '9'), then link time, then revision id. It never
    depends on caller input or row order (mms-security).
  - An older runnable approval keeps running while a newer compile waits for its own approval;
    approval never transfers between compiler versions.

  `select/4` is a read. Staging records its result; the apply and the activation select again,
  under their locks, and refuse a different answer ("re-stage needed").
  """

  import Ecto.Query

  alias Cadence.MissionModels.{EffectiveRevisionRow, RevisionRow}
  alias Cadence.Repo

  # Oldest to newest. A version is added when this server runs its plans and removed (a release
  # note, docs/how-to/release-checklist.md item 5) when it no longer does.
  @runnable ["2"]

  @doc "The compiler versions whose plans this server runs, oldest to newest."
  @spec runnable() :: [binary()]
  def runnable, do: @runnable

  @spec runnable?(binary()) :: boolean()
  def runnable?(compiler_version), do: compiler_version in @runnable

  @doc """
  The revision `composition_id` runs: `{:ok, revision_id}`; `{:error, :reapproval_needed}` when
  only revisions this server can't run are approved; `{:error, :withdrawn}` when none is approved
  and one's approval was withdrawn (E2, #546); else `{:error, :not_approved}`. It's the first
  approved, runnable link of `ranked/3`, so withdrawing the newest approval falls back to an older
  approved, runnable revision of the same composition, which staging then records and shows.

  `opts[:assume_approved]` treats that one revision as approved (#577's "what the next staging
  would select once it's approved"), in the same pass, so a read can't disagree with staging.
  `opts[:runnable]` replaces the list (tests only).
  """
  @spec select(binary(), binary(), binary(), keyword()) ::
          {:ok, binary()} | {:error, :not_approved | :reapproval_needed | :withdrawn}
  def select(organization_id, mission_id, composition_id, opts \\ []) do
    links =
      organization_id
      |> ranked(mission_id, composition_id, opts)
      |> assume_approved(Keyword.get(opts, :assume_approved))

    case Enum.find(links, &(&1.status == "approved" and &1.runnable)) do
      %{revision_id: revision_id} ->
        {:ok, revision_id}

      nil ->
        cond do
          Enum.any?(links, &(&1.status == "approved")) -> {:error, :reapproval_needed}
          # E2 (#546): the composition's own approval was taken back (§5's narrow "superseded").
          Enum.any?(links, &(&1.status == "withdrawn")) -> {:error, :withdrawn}
          true -> {:error, :not_approved}
        end
    end
  end

  defp assume_approved(links, nil), do: links

  defp assume_approved(links, revision_id),
    do:
      Enum.map(links, fn
        %{revision_id: ^revision_id} = link -> %{link | status: "approved"}
        link -> link
      end)

  @doc """
  Every link of `composition_id` (NULL head), newest first in the selection's own order, with its
  revision's status and whether this server runs it: a reader (#577's "a newer compile awaits
  approval") finds the candidate in the same order `select/4` picks from. Runnable versions come
  by list position, unrunnable ones after them.
  """
  @spec ranked(binary(), binary(), binary(), keyword()) :: [
          %{
            revision_id: binary(),
            compiler_version: binary(),
            linked_at: DateTime.t(),
            status: binary(),
            runnable: boolean()
          }
        ]
  def ranked(organization_id, mission_id, composition_id, opts \\ []) do
    runnable = Keyword.get(opts, :runnable, @runnable)

    organization_id
    |> links(mission_id, composition_id)
    |> Enum.map(&Map.put(&1, :runnable, &1.compiler_version in runnable))
    |> Enum.sort_by(&order(&1, runnable), :desc)
  end

  # Larger is newer: list position (unrunnable: -1), then link time, then revision id (total).
  defp order(link, runnable),
    do:
      {Enum.find_index(runnable, &(&1 == link.compiler_version)) || -1,
       DateTime.to_unix(link.linked_at, :microsecond), link.revision_id}

  defp links(organization_id, mission_id, composition_id) do
    from(link in EffectiveRevisionRow,
      join: revision in RevisionRow,
      on:
        revision.organization_id == link.organization_id and
          revision.mission_id == link.mission_id and revision.revision_id == link.revision_id,
      where:
        link.organization_id == ^organization_id and link.mission_id == ^mission_id and
          link.composition_id == ^composition_id and is_nil(link.authored_head),
      select: %{
        revision_id: link.revision_id,
        compiler_version: link.compiler_version,
        linked_at: link.inserted_at,
        status: revision.status
      }
    )
    |> Repo.all()
  end
end
