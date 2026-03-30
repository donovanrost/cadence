defmodule Cadence.ApplicationDispatch.SelectorScope do
  @moduledoc """
  Scope selector for governed application dispatch.
  """

  @type target_scope :: :mission | :source_endpoint

  @type t :: %__MODULE__{
          target_scope: target_scope(),
          source_endpoint_ref: binary() | nil
        }

  defstruct [:target_scope, :source_endpoint_ref]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    source_endpoint_ref =
      Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref"))

    %__MODULE__{
      target_scope:
        attrs
        |> Map.get(:target_scope, Map.get(attrs, "target_scope"))
        |> case do
          nil -> infer_target_scope(source_endpoint_ref)
          target_scope -> target_scope
        end
        |> normalize_target_scope(),
      source_endpoint_ref: source_endpoint_ref
    }
  end

  defp infer_target_scope(nil), do: :mission
  defp infer_target_scope(_source_endpoint_ref), do: :source_endpoint

  defp normalize_target_scope(target_scope) when is_atom(target_scope), do: target_scope

  defp normalize_target_scope(target_scope) when is_binary(target_scope),
    do: String.to_existing_atom(target_scope)
end
