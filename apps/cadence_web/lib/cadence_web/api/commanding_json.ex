defmodule CadenceWeb.API.CommandingJSON do
  @moduledoc "Commanding response serialization boundary."

  alias Cadence.Commanding.{CommandStage, StagedCommandItem}

  alias Cadence.Persistence.JsonDocument
  alias CadenceWeb.API.ActorDocument

  @doc """
  #465: the actor names a response's records need, loaded once (`ActorDocument.names/2`), under
  their own organization. Pass the result to each encoder; one record alone loads its own.
  """
  @spec actor_names([struct()]) :: map()
  def actor_names([]), do: ActorDocument.names(nil, [])

  def actor_names([first | _] = records),
    do: ActorDocument.names(first.organization_id, Enum.flat_map(records, &actors/1))

  defp actors(%CommandStage{owner: owner}), do: [owner]
  defp actors(_record), do: []

  @doc "#465: encodes a list's records with `encode/2`, loading their actor names once."
  @spec encode_all([struct()], (struct(), map() -> map())) :: [map()]
  def encode_all(records, encode) do
    names = actor_names(records)
    Enum.map(records, &encode.(&1, names))
  end

  defp names_for(nil, record), do: actor_names([record])
  defp names_for(names, _record), do: names

  def command_stage(%CommandStage{} = stage, names \\ nil) do
    names = names_for(names, stage)

    %{
      command_stage_id: stage.command_stage_id,
      organization_id: stage.organization_id,
      mission_id: stage.mission_id,
      stage_name: stage.stage_name,
      description: stage.description,
      owner: ActorDocument.actor(stage.owner, names),
      visibility: Atom.to_string(stage.visibility),
      lifecycle_state: Atom.to_string(stage.lifecycle_state),
      metadata: stage.metadata
    }
  end

  def staged_command_item(%StagedCommandItem{} = item) do
    %{
      staged_command_item_id: item.staged_command_item_id,
      organization_id: item.organization_id,
      mission_id: item.mission_id,
      command_stage_id: item.command_stage_id,
      source_endpoint_ref: item.source_endpoint_ref,
      mission_model_revision_id: item.mission_model_revision_id,
      command_id: item.command_id,
      argument_values: JsonDocument.encode(item.argument_values),
      priority: item.priority,
      not_before: iso8601(item.not_before),
      expires_at: iso8601(item.expires_at),
      notes: item.notes,
      item_order: item.item_order,
      lifecycle_state: Atom.to_string(item.lifecycle_state),
      submitted_command_request_id: item.submitted_command_request_id,
      metadata: JsonDocument.encode(item.metadata)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
