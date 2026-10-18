defmodule Cadence.MissionModels.CommandArgumentChoices do
  @moduledoc "Bounded enumeration choices from a command's pinned semantic revision."

  alias Cadence.Repo

  # Existing executable plans omit enumeration members. Project only the requested
  # argument types from their immutable revision; never rewrite a reviewed plan or
  # materialize the complete revision document in an authoring process.
  @query """
  SELECT choices.document
  FROM (
    SELECT jsonb_object_agg(requested.argument_id, argument_type.definition->'enumerations') AS document,
           COUNT(*) AS matched
    FROM mission_model_revisions AS revision
    CROSS JOIN unnest($4::text[]) AS requested(argument_id)
    CROSS JOIN LATERAL jsonb_array_elements(
      revision.revision_document->'value'->'declarations'->requested.argument_id->'references'
    ) AS reference
    CROSS JOIN LATERAL (
      SELECT revision.revision_document->'value'->'declarations'->(reference->>'resolved_id') AS declaration
    ) AS resolved
    CROSS JOIN LATERAL (SELECT resolved.declaration->'definition' AS definition) AS argument_type
    WHERE revision.organization_id = $1 AND revision.mission_id = $2 AND revision.revision_id = $3
      AND revision.revision_document->'value'->'declarations'->requested.argument_id->>'kind' = 'command_argument'
      AND reference->>'role' = 'type'
      AND resolved.declaration->>'kind' = 'command_argument_type'
  ) AS choices
  WHERE choices.matched = cardinality($4::text[])
    AND octet_length(choices.document::text) <= 1048576
  """

  def load(_organization_id, _mission_id, _revision_id, []), do: {:ok, %{}}

  def load(organization_id, mission_id, revision_id, argument_ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) and
             is_list(argument_ids) and length(argument_ids) <= 4096 do
    ids = Enum.uniq(argument_ids)

    with true <- Enum.all?(ids, &is_binary/1),
         {:ok, %{rows: [[document]]}} <-
           Repo.query(@query, [organization_id, mission_id, revision_id, ids]),
         true <- is_map(document) and map_size(document) == length(ids) do
      normalize(document)
    else
      _ -> {:error, :command_argument_choices_unavailable}
    end
  end

  def load(_, _, _, _), do: {:error, :command_argument_choices_unavailable}

  defp normalize(document) do
    Enum.reduce_while(document, {:ok, %{}}, fn {id, entries}, {:ok, result} ->
      if is_list(entries) and length(entries) in 1..1024 and Enum.all?(entries, &choice?/1) do
        choices =
          entries
          |> Enum.uniq_by(& &1["value"])
          |> Enum.map(&%{label: &1["label"], value: &1["value"]})

        {:cont, {:ok, Map.put(result, id, choices)}}
      else
        {:halt, {:error, :command_argument_choices_unavailable}}
      end
    end)
  end

  defp choice?(%{"label" => label, "value" => value}),
    do: is_binary(label) and byte_size(label) in 1..2000 and is_integer(value)

  defp choice?(_), do: false
end
