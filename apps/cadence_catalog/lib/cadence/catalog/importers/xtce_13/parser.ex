defmodule Cadence.Catalog.Importers.Xtce13.Parser do
  @moduledoc "Bounded, external-entity-free XML parser for XTCE 1.3 source models."

  alias Cadence.Catalog.Importers.Xtce13.Element

  @default_max_bytes 10 * 1024 * 1024
  @default_max_depth 128
  @default_max_nodes 250_000

  @spec parse(binary(), keyword()) :: {:ok, Element.t()} | {:error, term()}
  def parse(xml, opts \\ []) when is_binary(xml) and is_list(opts) do
    with :ok <- bounded_size(xml, Keyword.get(opts, :max_bytes, @default_max_bytes)),
         :ok <- reject_document_type(xml) do
      state = %{
        stack: [],
        root: nil,
        error: nil,
        nodes: 0,
        max_depth: Keyword.get(opts, :max_depth, @default_max_depth),
        max_nodes: Keyword.get(opts, :max_nodes, @default_max_nodes)
      }

      case :xmerl_sax_parser.stream(xml,
             event_fun: &event/3,
             event_state: state
           ) do
        {:ok, %{error: nil, root: %Element{} = root}, _rest} ->
          {:ok, root}

        {:ok, %{error: reason}, _rest} when not is_nil(reason) ->
          {:error, reason}

        {:ok, _state, _rest} ->
          {:error, :xtce_document_root_missing}

        {:fatal_error, location, reason, _end_tags, _state} ->
          {:error, {:invalid_xtce_xml, location, List.to_string(reason)}}

        {:error, reason} ->
          {:error, {:invalid_xtce_xml, reason}}
      end
    end
  catch
    :exit, reason -> {:error, {:invalid_xtce_xml, reason}}
  end

  defp event(_event, _location, %{error: reason} = state) when not is_nil(reason), do: state

  defp event({:startElement, namespace, local_name, _qualified_name, attributes}, location, state) do
    depth = length(state.stack) + 1
    nodes = state.nodes + 1

    cond do
      depth > state.max_depth ->
        %{state | error: :xtce_maximum_depth_exceeded}

      nodes > state.max_nodes ->
        %{state | error: :xtce_maximum_node_count_exceeded}

      true ->
        element = %Element{
          name: List.to_string(local_name),
          namespace: character_data(namespace),
          attributes: attributes(attributes),
          line: location_line(location)
        }

        %{state | stack: [element | state.stack], nodes: nodes}
    end
  end

  defp event(
         {event, characters},
         _location,
         %{stack: [%Element{} = current | rest]} = state
       )
       when event in [:characters, :ignorableWhitespace] do
    text = current.text <> List.to_string(characters)
    %{state | stack: [%Element{current | text: text} | rest]}
  end

  defp event({:endElement, _namespace, _local_name, _qualified_name}, _location, state) do
    case state.stack do
      [%Element{} = current] ->
        %{state | stack: [], root: finalize(current)}

      [%Element{} = current, %Element{} = parent | rest] ->
        parent = %Element{parent | children: [finalize(current) | parent.children]}
        %{state | stack: [parent | rest]}

      [] ->
        %{state | error: :xtce_unbalanced_xml}
    end
  end

  defp event(_event, _location, state), do: state

  defp finalize(%Element{} = element),
    do: %Element{element | children: Enum.reverse(element.children)}

  defp attributes(attributes) do
    Map.new(attributes, fn {_uri, _prefix, local_name, value} ->
      {List.to_string(local_name), List.to_string(value)}
    end)
  end

  defp location_line({_file, _entity, line}) when is_integer(line), do: line
  defp location_line(_location), do: nil

  defp character_data([]), do: nil
  defp character_data(value), do: List.to_string(value)

  defp bounded_size(xml, max_bytes) when byte_size(xml) <= max_bytes, do: :ok
  defp bounded_size(_xml, _max_bytes), do: {:error, :xtce_artifact_too_large}

  defp reject_document_type(xml) do
    if Regex.match?(~r/<!\s*(DOCTYPE|ENTITY)/i, xml) do
      {:error, :xtce_document_type_forbidden}
    else
      :ok
    end
  end
end
