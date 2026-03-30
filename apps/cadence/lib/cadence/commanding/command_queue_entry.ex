defmodule Cadence.Commanding.CommandQueueEntry do
  @moduledoc """
  Durable queued command entry ordered within a dispatch lane.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :pending | :release_pending | :released | :canceled

  @type t :: %__MODULE__{
          command_queue_entry_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          command_request_id: binary(),
          source_endpoint_ref: binary(),
          queue_lane_key: binary(),
          priority: non_neg_integer(),
          queue_sequence: pos_integer(),
          not_before: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          lifecycle_state: lifecycle_state(),
          enqueued_by: map(),
          enqueued_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :command_queue_entry_id,
    :organization_id,
    :mission_id,
    :command_request_id,
    :source_endpoint_ref,
    :queue_lane_key,
    :queue_sequence,
    :not_before,
    :expires_at,
    :enqueued_at,
    priority: 3,
    lifecycle_state: :pending,
    enqueued_by: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_queue_entry_id:
        Map.get(
          attrs,
          :command_queue_entry_id,
          Map.get(attrs, "command_queue_entry_id", Ids.new("command_queue_entry"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      command_request_id: Map.fetch!(attrs, :command_request_id),
      source_endpoint_ref: Map.fetch!(attrs, :source_endpoint_ref),
      queue_lane_key: Map.fetch!(attrs, :queue_lane_key),
      priority: Map.get(attrs, :priority, Map.get(attrs, "priority", 3)),
      queue_sequence:
        Map.get(
          attrs,
          :queue_sequence,
          Map.get(attrs, "queue_sequence", System.unique_integer([:positive, :monotonic]))
        ),
      not_before: Map.get(attrs, :not_before, Map.get(attrs, "not_before")),
      expires_at: Map.get(attrs, :expires_at, Map.get(attrs, "expires_at")),
      lifecycle_state:
        normalize_lifecycle_state(
          Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :pending))
        ),
      enqueued_by: Map.get(attrs, :enqueued_by, Map.get(attrs, "enqueued_by", %{})),
      enqueued_at: Map.get(attrs, :enqueued_at, Map.get(attrs, "enqueued_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_lifecycle_state(:pending), do: :pending
  defp normalize_lifecycle_state("pending"), do: :pending
  defp normalize_lifecycle_state(:release_pending), do: :release_pending
  defp normalize_lifecycle_state("release_pending"), do: :release_pending
  defp normalize_lifecycle_state(:released), do: :released
  defp normalize_lifecycle_state("released"), do: :released
  defp normalize_lifecycle_state(:canceled), do: :canceled
  defp normalize_lifecycle_state("canceled"), do: :canceled
  defp normalize_lifecycle_state(_other), do: :pending
end
