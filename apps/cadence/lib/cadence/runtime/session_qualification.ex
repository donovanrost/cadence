defmodule Cadence.Runtime.SessionQualification do
  @moduledoc """
  Trusted provider-specific verification of external fencing and protocol recovery.

  The default policy qualifies no provider. A root may supply an implementation
  that validates actual external evidence against the exact session basis. An
  implementation must not accept a configuration flag as proof of authority.
  These callbacks must be bounded and must not call the session gate recursively.
  """

  @callback verify_fencing(map(), map()) :: :ok | {:error, term()}
  @callback verify_recovery_exchange(map(), map(), map(), map()) :: :ok | {:error, term()}
  @callback verify_protocol_recovery(map(), map(), map()) :: :ok | {:error, term()}

  def verify_fencing(_basis, _evidence), do: {:error, :unsupported_takeover}

  def verify_recovery_exchange(_basis, _fencing, _exchange, _evidence),
    do: {:error, :unsupported_takeover}

  def verify_protocol_recovery(_basis, _fencing, _evidence),
    do: {:error, :unsupported_takeover}
end
