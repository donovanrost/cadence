defmodule Cadence.Commanding.CommandApproval do
  @moduledoc """
  Durable approval or rejection record attached to a command request.
  """

  alias Cadence.Ids

  # not_required: a request released without a second GO (#117 step 4b; its release's own row).
  @type decision :: :approved | :rejected | :not_required

  @type t :: %__MODULE__{
          command_approval_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          command_request_id: binary(),
          decision: decision(),
          decided_by: map(),
          decided_at: DateTime.t() | nil,
          reason: binary() | nil,
          metadata: map(),
          subject_digest: binary() | nil,
          separated_from: [binary()],
          admin_mode: boolean() | nil
        }

  defstruct [
    :command_approval_id,
    :organization_id,
    :mission_id,
    :command_request_id,
    :decision,
    :decided_at,
    :reason,
    # #117 step 4b: the four-eyes record (required on a stored row).
    :subject_digest,
    :admin_mode,
    decided_by: %{},
    metadata: %{},
    separated_from: []
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
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})),
      subject_digest: Map.get(attrs, :subject_digest),
      separated_from: Map.get(attrs, :separated_from, []),
      admin_mode: Map.get(attrs, :admin_mode)
    }
  end

  defp normalize_decision(:approved), do: :approved
  defp normalize_decision("approved"), do: :approved
  defp normalize_decision(:rejected), do: :rejected
  defp normalize_decision("rejected"), do: :rejected
  defp normalize_decision(:not_required), do: :not_required
  defp normalize_decision("not_required"), do: :not_required
  # #117 step 4a (ca-security, domain): an unknown decision never reads as approved.
  defp normalize_decision(other),
    do: raise(ArgumentError, "unknown command approval decision: #{inspect(other)}")
end
