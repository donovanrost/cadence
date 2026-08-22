defmodule Cadence.ApplicationDispatch.Selector do
  @moduledoc """
  First-class selector schema composed of scope and protocol-stage selectors.
  """

  alias Cadence.ApplicationDispatch.{SelectorMatch, SelectorScope}

  @type t :: %__MODULE__{
          scope: SelectorScope.t(),
          match: SelectorMatch.t()
        }

  defstruct [:scope, :match]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      scope: build_scope(attrs),
      match: build_match(attrs)
    }
  end

  defp build_scope(%{scope: %SelectorScope{} = scope}), do: scope
  defp build_scope(%{"scope" => %SelectorScope{} = scope}), do: scope

  defp build_scope(%{scope: scope_attrs}) when is_map(scope_attrs),
    do: SelectorScope.new(scope_attrs)

  defp build_scope(%{"scope" => scope_attrs}) when is_map(scope_attrs),
    do: SelectorScope.new(scope_attrs)

  defp build_scope(attrs), do: SelectorScope.new(attrs)

  defp build_match(%{match: %SelectorMatch{} = match}), do: match
  defp build_match(%{"match" => %SelectorMatch{} = match}), do: match

  defp build_match(%{match: match_attrs}) when is_map(match_attrs),
    do: SelectorMatch.new(match_attrs)

  defp build_match(%{"match" => match_attrs}) when is_map(match_attrs),
    do: SelectorMatch.new(match_attrs)

  defp build_match(attrs), do: SelectorMatch.new(attrs)
end
