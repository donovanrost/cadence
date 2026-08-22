defmodule Cadence.Commanding.CommandApproval do
  @moduledoc """
  Durable approval or rejection record attached to a command request.
  """

  alias Cadence.Ids

  @type decision :: :approved | :rejected

  @type t :: %__MODULE__{
          command_approval_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          command_request_id: binary(),
          decision: decision(),
          decided_by: map(),
          decided_at: DateTime.t() | nil,
          reason: binary() | nil,
          metadata: map()
        }

  defstruct [
    :command_approval_id,
    :organization_id,
    :mission_id,
    :command_request_id,
    :decision,
    :decided_at,
    :reason,
    decided_by: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_approval_id:
        Map.get(
          attrs,
          :command_approval_id,
          Map.get(attrs, "command_approval_id", Ids.new("command_approval"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      command_request_id: Map.fetch!(attrs, :command_request_id),
      decision:
        normalize_decision(Map.get(attrs, :decision, Map.get(attrs, "decision", :approved))),
      decided_by: Map.get(attrs, :decided_by, Map.get(attrs, "decided_by", %{})),
      decided_at: Map.get(attrs, :decided_at, Map.get(attrs, "decided_at")),
      reason: Map.get(attrs, :reason, Map.get(attrs, "reason")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_decision(:approved), do: :approved
  defp normalize_decision("approved"), do: :approved
  defp normalize_decision(:rejected), do: :rejected
  defp normalize_decision("rejected"), do: :rejected
  defp normalize_decision(_other), do: :approved
end
