defmodule Cadence.ProceduresBuilders do
  @moduledoc """
  Builders for Procedures tests that don't need persistence.
  """

  def build_context(overrides \\ %{}) do
    defaults = %{
      mission_id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      target_id: nil,
      execution_id: Ecto.UUID.generate(),
      params: %{},
      vars: %{},
      trigger: nil
    }

    Map.merge(defaults, to_map(overrides))
  end

  defp to_map(kw) when is_list(kw), do: Map.new(kw)
  defp to_map(map) when is_map(map), do: map
end
