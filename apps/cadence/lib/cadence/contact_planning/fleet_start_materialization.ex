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
    actor = actor_id(scope)

    template.occurrences
    |> Stream.flat_map(fn at ->
      version_attrs = occurrence_version_attrs(template.version, mission_id, at, actor)
      Stream.map(template.spacecraft_ids, &{at, &1, version_attrs})
    end)
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, [], 0}, fn days, {:ok, batches, occurrence_count} ->
      case materialize_batch(template.version, days, reviewed) do
        {:ok, pairs} -> {:cont, {:ok, [pairs | batches], occurrence_count + length(days)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, batches, count} -> {:ok, batches |> Enum.reverse() |> List.flatten(), count}
      error -> error
    end
  end

  defp materialize_batch(template, days, reviewed) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    created =
      Enum.reduce(days, [], fn {at, spacecraft_id, version_attrs}, created ->
        case Map.get(reviewed, TemplateDays.key(at, spacecraft_id)) do
          nil ->
            [generated(template, at, spacecraft_id, version_attrs, now) | created]

          %{outcome: "generate"} ->
            [generated(template, at, spacecraft_id, version_attrs, now) | created]

          %{state: "generated"} ->
            created

          _incomplete ->
            Repo.rollback(:contact_requirement_occurrence_not_converged)
        end
      end)

    created = Enum.reverse(created)

    with :ok <- ContactRequirements.insert_materialized_batch(created),
         :ok <- ContactRequirementTemplates.insert_materialized_occurrences(created) do
      {:ok, Enum.map(created, &{&1.requirement, &1.version})}
    end
  end

  defp occurrence_version_attrs(template, mission_id, at, actor) do
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

    template.requirement_document
    |> Map.delete("contact_requirement_version_id")
    |> Map.merge(%{
      "organization_id" => template.organization_id,
      "mission_id" => mission_id,
      "version" => 1,
      "earliest_start" => earliest_start,
      "latest_end" => latest_end,
      "metadata" => metadata,
      "created_by" => actor
    })
  end

  defp generated(template, at, spacecraft_id, version_attrs, now) do
    requirement_id = Cadence.Ids.new("contact_requirement")

    version =
      version_attrs
      |> Map.merge(%{
        "contact_requirement_id" => requirement_id,
        "spacecraft_id" => spacecraft_id,
        "created_at" => now
      })
      |> ContactRequirementVersion.new()

    requirement =
      ContactRequirement.new(%{
        contact_requirement_id: requirement_id,
        organization_id: template.organization_id,
        mission_id: version.mission_id,
        created_by: version.created_by,
        lifecycle_changed_by: version.created_by,
        lifecycle_changed_at: now,
        lifecycle_reason: "created"
      })

    occurrence =
      ContactRequirementOccurrence.new(%{
        organization_id: template.organization_id,
        mission_id: version.mission_id,
        contact_requirement_template_id: template.contact_requirement_template_id,
        contact_requirement_template_version: template.version,
        spacecraft_id: spacecraft_id,
        occurrence_at: at,
        generation_state: :generated,
        generated_contact_requirement_id: requirement_id,
        generated_contact_requirement_version: 1,
        materialized_by: version.created_by,
        materialized_at: now
      })

    %{requirement: requirement, version: version, occurrence: occurrence}
  end

  defp actor_id(%{actor_kind: :user, user: %{user_id: id}}) when is_binary(id), do: id

  defp actor_id(%{actor_kind: :service, service_identity: %{service_identity_id: id}})
       when is_binary(id), do: id
end
