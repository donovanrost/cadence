defmodule Cadence.Commanding.CommandStage do
  @moduledoc """
  Mission-scoped command staging container used for collaborative draft command
  preparation.
  """

  alias Cadence.Ids

  @type visibility :: :private | :shared
  @type lifecycle_state :: :draft | :in_review | :ready_to_submit | :submitted | :canceled

  @type t :: %__MODULE__{
          command_stage_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          stage_name: binary(),
          description: binary() | nil,
          owner: map(),
          visibility: visibility(),
          lifecycle_state: lifecycle_state(),
          metadata: map()
        }

  defstruct [
    :command_stage_id,
    :organization_id,
    :mission_id,
    :stage_name,
    :description,
    owner: %{},
    visibility: :private,
    lifecycle_state: :draft,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_stage_id:
        Map.get(
          attrs,
          :command_stage_id,
          Map.get(attrs, "command_stage_id", Ids.new("command_stage"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      stage_name: Map.fetch!(attrs, :stage_name),
      description: Map.get(attrs, :description, Map.get(attrs, "description")),
      owner: Map.get(attrs, :owner, Map.get(attrs, "owner", %{})),
      visibility:
        normalize_visibility(Map.get(attrs, :visibility, Map.get(attrs, "visibility", :private))),
      lifecycle_state:
        normalize_lifecycle_state(
          Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :draft))
        ),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_visibility(:private), do: :private
  defp normalize_visibility("private"), do: :private
  defp normalize_visibility(:shared), do: :shared
  defp normalize_visibility("shared"), do: :shared
  defp normalize_visibility(_other), do: :private

  defp normalize_lifecycle_state(:draft), do: :draft
  defp normalize_lifecycle_state("draft"), do: :draft
  defp normalize_lifecycle_state(:in_review), do: :in_review
  defp normalize_lifecycle_state("in_review"), do: :in_review
  defp normalize_lifecycle_state(:ready_to_submit), do: :ready_to_submit
  defp normalize_lifecycle_state("ready_to_submit"), do: :ready_to_submit
  defp normalize_lifecycle_state(:submitted), do: :submitted
  defp normalize_lifecycle_state("submitted"), do: :submitted
  defp normalize_lifecycle_state(:canceled), do: :canceled
  defp normalize_lifecycle_state("canceled"), do: :canceled
  defp normalize_lifecycle_state(_other), do: :draft
end
