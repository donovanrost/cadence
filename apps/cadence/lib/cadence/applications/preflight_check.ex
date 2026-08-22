defmodule Cadence.Applications.PreflightCheck do
  @moduledoc "One bounded dependency, configuration, resource, or compilation check."

  @type category :: :dependency | :configuration | :resource | :compilation
  @type state :: :ready | :attention | :blocked

  @type t :: %__MODULE__{
          id: binary(),
          category: category(),
          state: state(),
          title: binary(),
          detail: binary(),
          value: binary() | nil
        }

  @enforce_keys [:id, :category, :state, :title, :detail]
  defstruct [:id, :category, :state, :title, :detail, :value]
end
