defmodule Cadence.Applications.ActionRequest do
  @moduledoc """
  Typed request for a host-standard or application-defined operation.

  `origin` is the host the request came through: `:console` (the console's app surface host) or
  `:legacy_host` (the legacy application host). The host sets it, never the client; providers
  that keep a save trail (limits, derived telemetry) record it and refuse a save without one.
  """

  @type origin :: :console | :legacy_host

  @type t :: %__MODULE__{
          application_key: binary(),
          application_version: pos_integer(),
          action_id: binary(),
          surface_id: binary() | nil,
          surface_version: pos_integer() | nil,
          params: map(),
          expected_configuration_version: pos_integer() | nil,
          idempotency_key: binary() | nil,
          origin: origin() | nil
        }

  @enforce_keys [:application_key, :application_version, :action_id]
  defstruct [
    :application_key,
    :application_version,
    :action_id,
    :surface_id,
    :surface_version,
    :expected_configuration_version,
    :idempotency_key,
    :origin,
    params: %{}
  ]

  @doc "The save trail's `via` for a request's origin; `:error` when the host set none."
  @spec via(t()) :: {:ok, binary()} | {:error, :action_origin_required}
  def via(%__MODULE__{origin: :console}), do: {:ok, "console"}
  def via(%__MODULE__{origin: :legacy_host}), do: {:ok, "legacy_host"}
  def via(%__MODULE__{}), do: {:error, :action_origin_required}
end
