defmodule Cadence.MissionModels.Selection do
  @moduledoc """
  Which revision a pinned composition runs (D3, #544; design §3's selection rule, agreed on #559
  by api-ops and mms-security): the newest APPROVED, RUNNABLE revision linked to the composition
  at the mission's authored head (nil until phase 3).

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
  only revisions this server can't run are approved; else `{:error, :not_approved}`.

  `opts[:runnable]` replaces the list (tests only).
  """
  @spec select(binary(), binary(), binary(), keyword()) ::
          {:ok, binary()} | {:error, :not_approved | :reapproval_needed}
  def select(organization_id, mission_id, composition_id, opts \\ []) do
    runnable = Keyword.get(opts, :runnable, @runnable)
    approved = approved_links(organization_id, mission_id, composition_id)

    case Enum.filter(approved, &(&1.compiler_version in runnable)) do
      [] when approved != [] ->
        {:error, :reapproval_needed}

      [] ->
        {:error, :not_approved}

      candidates ->
        {:ok, candidates |> Enum.max_by(&order(&1, runnable)) |> Map.fetch!(:revision_id)}
    end
  end

  # Larger is newer: list position, then link time, then revision id (a total order).
  defp order(link, runnable),
    do:
      {Enum.find_index(runnable, &(&1 == link.compiler_version)),
       DateTime.to_unix(link.inserted_at, :microsecond), link.revision_id}

  defp approved_links(organization_id, mission_id, composition_id) do
    from(link in EffectiveRevisionRow,
      join: revision in RevisionRow,
      on:
        revision.organization_id == link.organization_id and
          revision.mission_id == link.mission_id and revision.revision_id == link.revision_id,
      where:
        link.organization_id == ^organization_id and link.mission_id == ^mission_id and
          link.composition_id == ^composition_id and is_nil(link.authored_head) and
          revision.status == "approved",
      select: %{
        revision_id: link.revision_id,
        compiler_version: link.compiler_version,
        inserted_at: link.inserted_at
      }
    )
    |> Repo.all()
  end
end
