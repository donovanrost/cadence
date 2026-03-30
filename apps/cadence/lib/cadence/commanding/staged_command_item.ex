defmodule Cadence.Commanding.StagedCommandItem do
  @moduledoc """
  Editable draft command entry within a command stage.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :draft | :submitted | :canceled

  @type t :: %__MODULE__{
          staged_command_item_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          command_stage_id: binary(),
          source_endpoint_ref: binary(),
          command_snapshot_id: binary(),
          command_id: binary(),
          argument_values: map(),
          priority: non_neg_integer(),
          not_before: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          notes: binary() | nil,
          item_order: non_neg_integer(),
          lifecycle_state: lifecycle_state(),
          submitted_command_request_id: binary() | nil,
          metadata: map()
        }

  defstruct [
    :staged_command_item_id,
    :organization_id,
    :mission_id,
    :command_stage_id,
    :source_endpoint_ref,
    :command_snapshot_id,
    :command_id,
    :not_before,
    :expires_at,
    :notes,
    :submitted_command_request_id,
    argument_values: %{},
    priority: 3,
    item_order: 0,
    lifecycle_state: :draft,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      staged_command_item_id:
        Map.get(
          attrs,
          :staged_command_item_id,
          Map.get(attrs, "staged_command_item_id", Ids.new("staged_command_item"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      command_stage_id: Map.fetch!(attrs, :command_stage_id),
      source_endpoint_ref: Map.fetch!(attrs, :source_endpoint_ref),
      command_snapshot_id: Map.fetch!(attrs, :command_snapshot_id),
      command_id: Map.fetch!(attrs, :command_id),
      argument_values: Map.get(attrs, :argument_values, Map.get(attrs, "argument_values", %{})),
      priority: Map.get(attrs, :priority, Map.get(attrs, "priority", 3)),
      not_before: Map.get(attrs, :not_before, Map.get(attrs, "not_before")),
      expires_at: Map.get(attrs, :expires_at, Map.get(attrs, "expires_at")),
      notes: Map.get(attrs, :notes, Map.get(attrs, "notes")),
      item_order: Map.get(attrs, :item_order, Map.get(attrs, "item_order", 0)),
      lifecycle_state:
        normalize_lifecycle_state(
          Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :draft))
        ),
      submitted_command_request_id:
        Map.get(
          attrs,
          :submitted_command_request_id,
          Map.get(attrs, "submitted_command_request_id")
        ),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_lifecycle_state(:draft), do: :draft
  defp normalize_lifecycle_state("draft"), do: :draft
  defp normalize_lifecycle_state(:submitted), do: :submitted
  defp normalize_lifecycle_state("submitted"), do: :submitted
  defp normalize_lifecycle_state(:canceled), do: :canceled
  defp normalize_lifecycle_state("canceled"), do: :canceled
  defp normalize_lifecycle_state(_other), do: :draft
end
