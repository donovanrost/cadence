defmodule Cadence.Applications.SettingsProvider do
  @moduledoc "Domain-owned values and writes for a registered settings section."
  @callback settings_snapshot(binary(), binary() | nil) :: map()
  @callback save(Cadence.Auth.Scope.t(), binary() | nil, binary(), map()) ::
              {:ok, struct()} | {:error, term()}
end
