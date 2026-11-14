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
          optional(:workflow_kind) => binary() | nil
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

  def words(:derived_telemetry_evaluation, _context),
    do: phrases("Derived telemetry evaluation", "in its results", "record the result twice")

  def words(:telemetry_limit_evaluation, _context),
    do: phrases("Limit check", "in Limits", "record the limit events twice")

  def words(:telemetry_historical_data_workflow, context) do
    noun =
      case context[:workflow_kind] do
        "correction" -> "Correction"
        "replacement" -> "Replacement"
        _backfill -> "Backfill"
      end

    phrases(noun, "in the telemetry for that span", "write the span twice")
  end

  def words(:replay_telemetry_scope, _context),
    do: phrases("Replay", "in the replay's telemetry", "write the replay twice")

  def words(_job_type, _context),
    do: phrases("A Cadence job", "where it acts", "repeat what it did")

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
