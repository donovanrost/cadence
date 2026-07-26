defmodule Cadence.Applications.SurfaceElements.Diagnostic do
  @moduledoc "One exceptional finding rendered by the application host."

  @type severity :: :info | :warning | :error

  @type t :: %__MODULE__{
          id: binary(),
          code: binary(),
          severity: severity(),
          title: binary(),
          detail: binary(),
          value: binary() | nil
        }

  @enforce_keys [:id, :code, :severity, :title, :detail]
  defstruct [:id, :code, :severity, :title, :detail, :value]
end
