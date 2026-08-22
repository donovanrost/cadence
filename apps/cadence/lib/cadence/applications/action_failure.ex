defmodule Cadence.Applications.ActionFailure do
  @moduledoc """
  Stable operator-facing failure returned by an application action adapter.

  Application domains retain their native error vocabulary. Their first-party
  action adapter translates failures that cross the host boundary so the web
  host never needs application-specific pattern matches or copy.
  """

  @type t :: %__MODULE__{
          code: binary(),
          message: binary(),
          field: binary() | nil,
          retryable?: boolean()
        }

  @enforce_keys [:code, :message]
  defstruct [:code, :message, :field, retryable?: false]
end
