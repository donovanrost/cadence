defmodule Cadence.Domain.Procedures.ValueObjects.VersionStatus do
  @moduledoc """
  Value object representing procedure version status in the approval workflow.

  ## Status Values

  - `:draft` - Initial state, being authored
  - `:submitted` - Submitted for review
  - `:approved` - Approved and ready for use
  - `:rejected` - Rejected during review
  - `:withdrawn` - Author withdrew the submission
  - `:deprecated` - Superseded by a newer version

  ## Approval Workflow

  ```
  ┌───────┐    submit    ┌───────────┐    approve    ┌──────────┐
  │ DRAFT │ ───────────► │ SUBMITTED │ ────────────► │ APPROVED │
  └───────┘              └───────────┘               └──────────┘
                              │                           │
                              │ reject                    │ deprecate
                              ▼                           ▼
                         ┌──────────┐              ┌────────────┐
                         │ REJECTED │              │ DEPRECATED │
                         └──────────┘              └────────────┘

                         ┌───────────┐
                         │ WITHDRAWN │◄── withdraw (from submitted)
                         └───────────┘
  ```
  """

  @type t :: :draft | :submitted | :approved | :rejected | :withdrawn | :deprecated

  @values [:draft, :submitted, :approved, :rejected, :withdrawn, :deprecated]

  # States where the version can be executed
  @executable_states [:approved]

  # States where the version can be edited
  @editable_states [:draft]

  # Terminal states
  @terminal_states [:rejected, :withdrawn, :deprecated]

  # Valid transitions
  @valid_transitions %{
    draft: [:submitted],
    submitted: [:approved, :rejected, :withdrawn],
    approved: [:deprecated],
    rejected: [],
    withdrawn: [],
    deprecated: []
  }

  @doc """
  Returns all valid status values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the initial status for a new version.
  """
  @spec initial() :: t()
  def initial, do: :draft

  @doc """
  Returns true if the given value is a valid status.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a status value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_status}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_status}

  @doc """
  Parses a string or atom into a status.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_status}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "draft" -> {:ok, :draft}
      "submitted" -> {:ok, :submitted}
      "approved" -> {:ok, :approved}
      "rejected" -> {:ok, :rejected}
      "withdrawn" -> {:ok, :withdrawn}
      "deprecated" -> {:ok, :deprecated}
      _ -> {:error, :invalid_status}
    end
  end

  def parse(_), do: {:error, :invalid_status}

  @doc """
  Returns true if the version can be executed.
  """
  @spec executable?(t()) :: boolean()
  def executable?(status) when status in @executable_states, do: true
  def executable?(_), do: false

  @doc """
  Returns true if the version can be edited.
  """
  @spec editable?(t()) :: boolean()
  def editable?(status) when status in @editable_states, do: true
  def editable?(_), do: false

  @doc """
  Returns true if the status is terminal.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(status) when status in @terminal_states, do: true
  def terminal?(_), do: false

  @doc """
  Returns true if the version is pending review.
  """
  @spec pending_review?(t()) :: boolean()
  def pending_review?(:submitted), do: true
  def pending_review?(_), do: false

  @doc """
  Returns the list of valid next states.
  """
  @spec valid_next_states(t()) :: [t()]
  def valid_next_states(status) when is_map_key(@valid_transitions, status) do
    Map.fetch!(@valid_transitions, status)
  end

  def valid_next_states(_), do: []

  @doc """
  Returns true if a transition is valid.
  """
  @spec can_transition?(t(), t()) :: boolean()
  def can_transition?(from, to) when from in @values and to in @values do
    to in Map.get(@valid_transitions, from, [])
  end

  def can_transition?(_, _), do: false

  @doc """
  Validates a transition.
  """
  @spec validate_transition(t(), t()) :: :ok | {:error, {:invalid_transition, t(), t()}}
  def validate_transition(from, to) do
    if can_transition?(from, to) do
      :ok
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  @doc """
  Returns the display name for a status.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:draft), do: "Draft"
  def display_name(:submitted), do: "Submitted"
  def display_name(:approved), do: "Approved"
  def display_name(:rejected), do: "Rejected"
  def display_name(:withdrawn), do: "Withdrawn"
  def display_name(:deprecated), do: "Deprecated"

  @doc """
  Returns a color for the status (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:draft), do: "gray"
  def color(:submitted), do: "yellow"
  def color(:approved), do: "green"
  def color(:rejected), do: "red"
  def color(:withdrawn), do: "gray"
  def color(:deprecated), do: "gray"
end
