defmodule Cadence.Commanding.Groups.CommandGroup do
  @moduledoc """
  One operator intent: N targets x K commands, reviewed, approved and aborted
  as a unit (docs/apogee/domain/group-requests.md). Members are ordinary
  `Cadence.Commanding.CommandRequest`s carrying `metadata["group"]`.
  """

  alias Cadence.Ids

  @type state :: :approval_pending | :queued | :rejected | :sent_back | :aborted

  @type t :: %__MODULE__{
          command_group_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          state: state(),
          title: binary(),
          log_entry: binary() | nil,
          requested_by: map(),
          requested_at: DateTime.t(),
          requested_approver_user_id: binary() | nil,
          operation_id: binary() | nil,
          sent_back_from: binary() | nil,
          target_query: map(),
          targets: [map()],
          resolved_at: DateTime.t(),
          commands: [map()],
          release: map(),
          basis: map(),
          policy: map(),
          preflight: map(),
          member_count: non_neg_integer(),
          decided_by: map() | nil,
          decided_at: DateTime.t() | nil,
          decision: map() | nil,
          aborted_by: map() | nil,
          aborted_at: DateTime.t() | nil,
          abort_reason: binary() | nil,
          abort_result: map() | nil
        }

  @states ~w(approval_pending queued rejected sent_back aborted)a

  defstruct [
    :command_group_id,
    :organization_id,
    :mission_id,
    :state,
    :title,
    :log_entry,
    :requested_at,
    :requested_approver_user_id,
    :operation_id,
    :sent_back_from,
    :resolved_at,
    :decided_by,
    :decided_at,
    :decision,
    :aborted_by,
    :aborted_at,
    :abort_reason,
    :abort_result,
    requested_by: %{},
    target_query: %{},
    targets: [],
    commands: [],
    release: %{},
    basis: %{},
    policy: %{},
    preflight: %{},
    member_count: 0
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_atom_key(key), value} end)

    struct(__MODULE__, attrs)
    |> Map.update!(:command_group_id, &(&1 || Ids.new("command_group")))
    |> Map.update!(:state, &normalize_state/1)
  end

  @spec states() :: [state()]
  def states, do: @states

  defp normalize_state(state) when state in @states, do: state

  defp normalize_state(state) when is_binary(state) do
    Enum.find(@states, :approval_pending, &(Atom.to_string(&1) == state))
  end

  defp normalize_state(_state), do: :approval_pending

  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key(key) when is_binary(key), do: String.to_existing_atom(key)
end
