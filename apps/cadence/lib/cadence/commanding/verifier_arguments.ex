defmodule Cadence.Commanding.VerifierArguments do
  @moduledoc """
  Resolves `value_from_argument` on a verifier's criteria when its instance is created: the
  criteria compare with the value the command was sent with (#38 verifier scope; e.g. SET_MODE's
  `HK.sc_mode` == its `mode`). The stored instance holds the concrete value, so evaluation never
  looks back at the request.

  Values come from the request's resolved arguments, by the argument's id through the runtime
  definition's specs. An integer or enumerated argument sent as a string is its integer code, as
  the encoder sends it. A value that can't be found stays nil, which matches nothing: the
  verifier times out rather than passing.
  """

  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Commanding.CommandRequest

  @doc "`%{argument_id => value}` for the request's resolved arguments."
  @spec values(CommandRequest.t(), [map()]) :: %{binary() => term()}
  def values(%CommandRequest{} = request, argument_specs) do
    resolved = request.resolved_argument_values || %{}

    for spec <- argument_specs || [],
        Map.has_key?(resolved, spec.name),
        into: %{},
        do: {spec.argument_id, normalize(spec, Map.fetch!(resolved, spec.name))}
  end

  @doc "Replaces `value_from_argument` with the argument's value, in nested conditions too."
  @spec bind(MatchCriteria.t() | nil, map()) :: MatchCriteria.t() | nil
  def bind(nil, _arguments), do: nil

  def bind(%MatchCriteria{value_from_argument: id} = criteria, arguments) when is_binary(id),
    do: bind(%MatchCriteria{criteria | value: Map.get(arguments, id)}, arguments, :conditions)

  def bind(%MatchCriteria{} = criteria, arguments), do: bind(criteria, arguments, :conditions)

  defp bind(%MatchCriteria{} = criteria, arguments, :conditions),
    do: %MatchCriteria{criteria | conditions: Enum.map(criteria.conditions, &bind(&1, arguments))}

  defp normalize(%{base_type: type}, value)
       when type in [:integer, :enumerated] and is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> value
    end
  end

  defp normalize(_spec, value), do: value
end
