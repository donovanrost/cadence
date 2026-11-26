defmodule Cadence.ContactPlanning.FleetStartMaterialization do
  @moduledoc """
  Materializes an already locked and reviewed template snapshot in database batches.

  The caller owns the transaction. Each batch inserts requirement identities, versions, and
  occurrence bindings in foreign-key order; a changed occurrence rolls the whole claim back.
  """

  alias Cadence.ContactPlanning.{
    ContactRequirement,
    ContactRequirementOccurrence,
    ContactRequirements,
    ContactRequirementTemplates,
    ContactRequirementVersion,
    RequirementSchedule,
    TemplateDays
  }

  alias Cadence.Repo

  @batch_size 500

  def materialize(scope, mission_id, template) do
    reviewed = Map.new(template.existing_occurrences, &{{&1.at, &1.spacecraft_id}, &1})

    template.occurrences
    |> Stream.flat_map(fn at -> Stream.map(template.spacecraft_ids, &{at, &1}) end)
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, []}, fn days, {:ok, batches} ->
      case materialize_batch(scope, mission_id, template.version, days, reviewed) do
        {:ok, results} -> {:cont, {:ok, [results | batches]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, batches} -> {:ok, batches |> Enum.reverse() |> List.flatten()}
      error -> error
    end
  end

  defp materialize_batch(scope, mission_id, template, days, reviewed) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {created, results} =
      Enum.reduce(days, {[], []}, fn {at, spacecraft_id}, {created, results} ->
        case Map.get(reviewed, TemplateDays.key(at, spacecraft_id)) do
          nil ->
            item = generated(scope, mission_id, template, at, spacecraft_id, now)
            {[item | created], [item.result | results]}

          %{outcome: "generate"} ->
            item = generated(scope, mission_id, template, at, spacecraft_id, now)
            {[item | created], [item.result | results]}

          %{state: "generated"} = existing ->
            result = %{
              status: :existing,
              occurrence: %{
                occurrence_at: at,
                spacecraft_id: spacecraft_id,
                generated_contact_requirement_id: existing.requirement_id,
                generated_contact_requirement_version: existing.requirement_version
              }
            }

            {created, [result | results]}

          _incomplete ->
            Repo.rollback(:contact_requirement_occurrence_not_converged)
        end
      end)

    created = Enum.reverse(created)

    with :ok <- ContactRequirements.insert_materialized_batch(created),
         :ok <- ContactRequirementTemplates.insert_materialized_occurrences(created) do
      {:ok, Enum.reverse(results)}
    end
  end

  defp generated(scope, mission_id, template, at, spacecraft_id, now) do
    actor_id = actor_id(scope)
    requirement_id = Cadence.Ids.new("contact_requirement")
    {earliest_start, latest_end} = RequirementSchedule.window(template.schedule_document, at)

    metadata =
      template.requirement_document
      |> Map.get("metadata", %{})
      |> Map.put("generation", %{
        "kind" => "contact_requirement_template",
        "contact_requirement_template_id" => template.contact_requirement_template_id,
        "contact_requirement_template_version" => template.version,
        "occurrence_at" => DateTime.to_iso8601(at)
      })

    version =
      template.requirement_document
      |> Map.merge(%{
        "contact_requirement_version_id" => Cadence.Ids.new("contact_requirement_version"),
        "contact_requirement_id" => requirement_id,
        "organization_id" => template.organization_id,
        "mission_id" => mission_id,
        "version" => 1,
        "spacecraft_id" => spacecraft_id,
        "earliest_start" => earliest_start,
        "latest_end" => latest_end,
        "metadata" => metadata,
        "created_by" => actor_id,
        "created_at" => now
      })
      |> ContactRequirementVersion.new()

    requirement =
      ContactRequirement.new(%{
        contact_requirement_id: requirement_id,
        organization_id: template.organization_id,
        mission_id: mission_id,
        created_by: actor_id,
        lifecycle_changed_by: actor_id,
        lifecycle_changed_at: now,
        lifecycle_reason: "created"
      })

    occurrence =
      ContactRequirementOccurrence.new(%{
        organization_id: template.organization_id,
        mission_id: mission_id,
        contact_requirement_template_id: template.contact_requirement_template_id,
        contact_requirement_template_version: template.version,
        spacecraft_id: spacecraft_id,
        occurrence_at: at,
        generation_state: :generated,
        generated_contact_requirement_id: requirement_id,
        generated_contact_requirement_version: 1,
        materialized_by: actor_id,
        materialized_at: now
      })

    %{
      requirement: requirement,
      version: version,
      occurrence: occurrence,
      result: %{
        status: :created,
        requirement: requirement,
        requirement_version: version,
        occurrence: occurrence
      }
    }
  end

  defp actor_id(%{actor_kind: :user, user: %{user_id: id}}) when is_binary(id), do: id

  defp actor_id(%{actor_kind: :service, service_identity: %{service_identity_id: id}})
       when is_binary(id), do: id
end
