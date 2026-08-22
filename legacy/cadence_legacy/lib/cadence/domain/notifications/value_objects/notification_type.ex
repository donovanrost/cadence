defmodule Cadence.Domain.Notifications.ValueObjects.NotificationType do
  @moduledoc """
  Value object representing the type of notification.

  ## Notification Types

  - `:procedure_submitted` - A procedure was submitted for approval
  - `:procedure_approved` - A procedure was approved
  - `:procedure_rejected` - A procedure was rejected
  - `:procedure_finalized` - A procedure reached final approval state
  - `:procedure_withdrawn` - A procedure was withdrawn by the submitter
  """

  @type t ::
          :procedure_submitted
          | :procedure_approved
          | :procedure_rejected
          | :procedure_finalized
          | :procedure_withdrawn

  @values [
    :procedure_submitted,
    :procedure_approved,
    :procedure_rejected,
    :procedure_finalized,
    :procedure_withdrawn
  ]

  @doc """
  Returns all valid notification type values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid notification type.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a notification type value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_notification_type}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_notification_type}

  @doc """
  Parses a string or atom into a notification type.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_notification_type}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case value do
      "procedure_submitted" -> {:ok, :procedure_submitted}
      "procedure_approved" -> {:ok, :procedure_approved}
      "procedure_rejected" -> {:ok, :procedure_rejected}
      "procedure_finalized" -> {:ok, :procedure_finalized}
      "procedure_withdrawn" -> {:ok, :procedure_withdrawn}
      _ -> {:error, :invalid_notification_type}
    end
  end

  def parse(_), do: {:error, :invalid_notification_type}

  @doc """
  Returns the database string representation.
  """
  @spec to_string(t()) :: String.t()
  def to_string(type) when is_atom(type), do: Atom.to_string(type)

  @doc """
  Returns the display name for a notification type.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:procedure_submitted), do: "Procedure Submitted"
  def display_name(:procedure_approved), do: "Procedure Approved"
  def display_name(:procedure_rejected), do: "Procedure Rejected"
  def display_name(:procedure_finalized), do: "Procedure Finalized"
  def display_name(:procedure_withdrawn), do: "Procedure Withdrawn"

  @doc """
  Returns true if this notification type is related to procedures.
  """
  @spec procedure_related?(t()) :: boolean()
  def procedure_related?(type) when type in @values, do: true
  def procedure_related?(_), do: false

  @doc """
  Returns the associated event type for recipient discovery.
  """
  @spec to_event_type(t()) :: atom()
  def to_event_type(:procedure_submitted), do: :submitted
  def to_event_type(:procedure_approved), do: :approved
  def to_event_type(:procedure_rejected), do: :rejected
  def to_event_type(:procedure_finalized), do: :finalized
  def to_event_type(:procedure_withdrawn), do: :withdrawn
end
