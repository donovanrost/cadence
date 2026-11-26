defmodule Cadence.ContactPlanning.TemplateDays do
  @moduledoc """
  One requirement per template day (DECISIONS #86, director 11-14): what a template version does
  with a day (an occurrence for one spacecraft) that an OLDER version of the same template
  already generated a requirement for.

  The day's latest older-version requirement decides:

  - none, or **active**, still in the future and not taken up by a plan: `:generate`. The new
    version generates its requirement, and supersession cancels the old one
    (`TemplateSupersession`). A draft-only plan doesn't count as taken up.
  - **canceled by supersession** (`template_versioned`, `left_template_target`): `:generate`.
  - **active and taken up** (a plan in pending_approval or later holds it) or **started** (its
    window has begun): `:kept`. No second requirement for that day; the old one stays.
  - **closed or canceled by an operator**: `:done`. An edit doesn't bring the day back; reopening
    it is a separate, explicit action.

  Materialize, the fleet start's review (`FleetStartInputs`) and the template edit preview all
  classify days with `classify/6`, so they agree.
  """

  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, ContactRequirementTemplates}

  @superseded_prefixes ["template_versioned", "left_template_target"]

  @doc false
  def superseded_prefixes, do: @superseded_prefixes

  @type outcome :: :generate | :kept | :done
  @type why :: :planned | :started | :closed | :canceled | nil

  @type prior :: %{
          occurrence: struct(),
          template_version: pos_integer(),
          requirement_id: binary(),
          requirement_version: pos_integer(),
          lifecycle_state: binary(),
          earliest_start: DateTime.t()
        }

  @type day :: %{outcome: outcome(), why: why(), prior: prior() | nil}

  @doc """
  Classifies each `{occurrence_at, spacecraft_id}` of template `template_id` for a version that
  comes after every version below `below_version` (for an edit's preview, the next version
  number; for materializing version V, V). `now` decides what has started.

  Returns `%{{occurrence_at_unix_us, spacecraft_id} => day}`, one entry per pair asked for.
  Options: `lock: true` share-locks the plans that hold the older requirements, then those
  requirements and their occurrences (plans first, the CP3 lock order).
  """
  @spec classify(
          binary(),
          binary(),
          binary(),
          pos_integer(),
          [{DateTime.t(), binary()}],
          keyword()
        ) ::
          %{{integer(), binary()} => day()}
  def classify(org, mission, template_id, below_version, days, opts \\ []) do
    now = Keyword.fetch!(opts, :now)
    lock? = Keyword.get(opts, :lock, false)
    older = latest_older(org, mission, template_id, below_version, days, lock?)
    ids = older |> Map.values() |> Enum.map(& &1.generated_contact_requirement_id)

    # Lock order, everywhere: plans, then requirements (CP3 re-review B).
    taken_up = ContactPlans.requirements_taken_up(org, mission, ids, lock: lock?)
    facts = ContactRequirements.day_facts(org, mission, ids, lock?)

    Map.new(days, fn {at, spacecraft_id} ->
      key = key(at, spacecraft_id)
      {key, decide(prior(older[key], facts), taken_up, now)}
    end)
  end

  @doc "The map key `classify/6` uses for a day."
  @spec key(DateTime.t(), binary()) :: {integer(), binary()}
  def key(%DateTime{} = at, spacecraft_id),
    do: {DateTime.to_unix(at, :microsecond), spacecraft_id}

  @doc "Pure: the outcome for a day given its latest older-version requirement."
  @spec decide(prior() | nil, MapSet.t(), DateTime.t()) :: day()
  def decide(nil, _taken_up, _now), do: day(:generate, nil, nil)

  def decide(%{lifecycle_state: "active"} = prior, taken_up, now) do
    cond do
      MapSet.member?(taken_up, prior.requirement_id) -> day(:kept, :planned, prior)
      not DateTime.after?(prior.earliest_start, now) -> day(:kept, :started, prior)
      true -> day(:generate, nil, prior)
    end
  end

  def decide(%{lifecycle_state: "canceled", lifecycle_reason: reason} = prior, _taken_up, _now) do
    if superseded?(reason), do: day(:generate, nil, prior), else: day(:done, :canceled, prior)
  end

  def decide(%{lifecycle_state: "closed"} = prior, _taken_up, _now),
    do: day(:done, :closed, prior)

  defp day(outcome, why, prior), do: %{outcome: outcome, why: why, prior: prior}

  defp superseded?(reason) when is_binary(reason),
    do: Enum.any?(@superseded_prefixes, &String.starts_with?(reason, &1))

  defp superseded?(_reason), do: false

  # The latest older-version occurrence per day.
  defp latest_older(_org, _mission, _template_id, _below, [], _lock?), do: %{}

  defp latest_older(org, mission, template_id, below_version, days, lock?) do
    ats = days |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    spacecraft_ids = days |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    org
    |> ContactRequirementTemplates.older_occurrence_rows(
      mission,
      template_id,
      below_version,
      ats,
      spacecraft_ids,
      lock?
    )
    |> Enum.group_by(&key(&1.occurrence_at, &1.spacecraft_id))
    |> Map.new(fn {key, rows} ->
      {key, Enum.max_by(rows, & &1.contact_requirement_template_version)}
    end)
  end

  defp prior(nil, _facts), do: nil

  defp prior(occurrence, facts) do
    case facts[occurrence.generated_contact_requirement_id] do
      nil ->
        nil

      fact ->
        %{
          occurrence: occurrence,
          template_version: occurrence.contact_requirement_template_version,
          requirement_id: fact.id,
          requirement_version: fact.current_version,
          lifecycle_state: fact.lifecycle_state,
          lifecycle_reason: fact.lifecycle_reason,
          earliest_start: fact.earliest_start
        }
    end
  end
end
