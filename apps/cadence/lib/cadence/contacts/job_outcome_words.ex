defmodule Cadence.Contacts.JobOutcomeWords do
  @moduledoc """
  The three phrases a job_outcome_unknown item needs (ux U54): the job's noun, where to check
  whether it happened, and what running it twice could do. Never a blank name: an unnamed
  provider is "the provider" (U30), and a missing source or artifact name falls back to the
  type's noun without it.
  """

  @type context :: %{
          optional(:provider_name) => binary() | nil,
          optional(:action) => binary() | nil,
          optional(:source_name) => binary() | nil,
          optional(:operation) => binary() | nil,
          optional(:artifact_name) => binary() | nil,
          optional(:workflow) => binary() | nil,
          optional(:definition_name) => binary() | nil,
          optional(:definition_count) => non_neg_integer() | nil,
          optional(:span_from) => binary() | nil,
          optional(:span_to) => binary() | nil
        }

  @spec words(atom(), context()) :: %{
          noun: binary(),
          check_place: binary(),
          consequence: binary()
        }
  def words(:contact_schedule_operation, context) do
    provider = name(context[:provider_name]) || "the provider"

    case context[:action] do
      "reserve" -> phrases("Booking at #{provider}", "with #{provider}", "book the pass twice")
      "cancel" -> phrases("Cancel at #{provider}", "with #{provider}", "send a second cancel")
      _other -> phrases("Change at #{provider}", "with #{provider}", "send the change twice")
    end
  end

  def words(:tsdb_backend_lifecycle, context) do
    source = name(context[:source_name])

    case context[:operation] do
      "deprovision" ->
        phrases(
          if(source, do: "Removing #{source}'s storage", else: "Removing a source's storage"),
          if(source, do: "in #{source}'s database", else: "in the source's database"),
          "remove it twice"
        )

      _provision ->
        phrases(
          if(source, do: "Provisioning #{source}", else: "Provisioning a source"),
          if(source, do: "in #{source}'s database", else: "in the source's database"),
          "provision it twice"
        )
    end
  end

  def words(:managed_questdb_provisioning, context) do
    source = name(context[:source_name])

    phrases(
      if(source, do: "Provisioning #{source}", else: "Provisioning a source"),
      "in Cadence's managed store",
      "provision it twice"
    )
  end

  def words(:catalog_import_run, context) do
    case name(context[:artifact_name]) do
      nil ->
        phrases("Catalog import", "in Setup › Catalog", "create a second revision")

      artifact ->
        phrases("Catalog import #{artifact}", "in Setup › Catalog", "create a second revision")
    end
  end

  # Names come from facts the job carried at enqueue (ux U54); older jobs keep the bare noun.
  def words(:derived_telemetry_evaluation, context) do
    noun =
      definitions_noun(context, "evaluation", "Derived telemetry evaluation")

    phrases(noun, "in its results", "record the result twice")
  end

  def words(:telemetry_limit_evaluation, context) do
    noun = definitions_noun(context, "limit check", "Limit check")
    phrases(noun, "in Limits", "record the limit events twice")
  end

  def words(:telemetry_historical_data_workflow, context) do
    noun = if context[:workflow] == "import", do: "Telemetry import", else: "Backfill"
    phrases(with_span(noun, context), "in the telemetry for that span", "write the span twice")
  end

  def words(:replay_telemetry_scope, context),
    do:
      phrases(
        with_span("Replay", context),
        "in the replay's telemetry",
        "write the replay twice"
      )

  def words(_job_type, _context),
    do: phrases("A Cadence job", "where it acts", "repeat what it did")

  # 'Battery margin evaluation' / 'Derived telemetry evaluation of 3 definitions'.
  defp definitions_noun(context, what, bare) do
    case {name(context[:definition_name]), context[:definition_count]} do
      {name, _count} when is_binary(name) -> "#{name} #{what}"
      {nil, count} when is_integer(count) and count > 1 -> "#{bare} of #{count} definitions"
      _none -> bare
    end
  end

  # §4: 'Backfill 11-13 02:00Z–04:00Z'; across midnight '11-13 23:00Z–11-14 01:00Z'.
  defp with_span(noun, context) do
    with {:ok, from} <- datetime(context[:span_from]),
         {:ok, to} <- datetime(context[:span_to]) do
      to_text =
        if Date.compare(DateTime.to_date(from), DateTime.to_date(to)) == :eq,
          do: clock(to),
          else: "#{day(to)} #{clock(to)}"

      "#{noun} #{day(from)} #{clock(from)}–#{to_text}"
    else
      _missing -> noun
    end
  end

  defp datetime(%DateTime{} = at), do: {:ok, at}

  defp datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> {:ok, at}
      _error -> :error
    end
  end

  defp datetime(_value), do: :error

  defp day(at), do: Calendar.strftime(at, "%m-%d")
  defp clock(at), do: Calendar.strftime(at, "%H:%MZ")

  defp phrases(noun, check_place, consequence),
    do: %{noun: noun, check_place: check_place, consequence: consequence}

  defp name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp name(_value), do: nil
end
