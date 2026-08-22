defmodule Cadence.Applications.SurfaceElements.ActivityItem do
  @moduledoc "One bounded operational entry rendered by the application host."

  @type tone :: :ready | :attention | :blocked | :info
  @type t :: %__MODULE__{
          id: binary(),
          title: binary(),
          detail: binary(),
          value: binary() | nil,
          timestamp: binary() | nil,
          tone: tone()
        }

  @enforce_keys [:id, :title, :detail]
  defstruct [:id, :title, :detail, :value, :timestamp, tone: :info]
end
