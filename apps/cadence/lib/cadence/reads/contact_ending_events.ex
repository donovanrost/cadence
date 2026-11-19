defmodule Cadence.Reads.ContactEndingEvents do
  @moduledoc """
  Timeline sentences for a contact that was canceled or ended early (ux U55/U56), from domain's
  contact actions (`scheduled_contact_canceled`, `realized_contact_ended_early`):

    * an operator: "EARENDIL-007 · PUQ 13:04Z contact canceled by Mira K.: “…”" / "… contact ended
      early by Mira K.: “…”";
    * Cadence, because the reservation won't fly (cause `provider_*`): "… pass canceled by Cadence:
      the provider couldn't book it" (`provider_failed`), "… canceled it" (`provider_canceled`),
      "… rejected its booking" (`provider_rejected`); another cause, just "… pass canceled by
      Cadence".
  """

  @provider_words %{
    "provider_failed" => "the provider couldn't book it",
    "provider_canceled" => "the provider canceled it",
    "provider_rejected" => "the provider rejected its booking"
  }

  @spec sentence(atom() | binary(), map(), binary(), map(), binary()) :: binary()
  def sentence(kind, metadata, craft, facts, by) do
    label = label(craft, facts)
    reason = value(metadata, "reason")
    # Older provider cancels carry the cause only as their reason ("provider_canceled").
    cause = value(metadata, "cause") || provider_reason(reason)

    case {to_string(kind), cause} do
      {"realized_contact_ended_early", _cause} ->
        "#{label} contact ended early#{by}#{quote_reason(reason)}"

      {_canceled, "provider_" <> _ = cause} ->
        case Map.get(@provider_words, cause) do
          nil -> "#{label} pass canceled by Cadence"
          words -> "#{label} pass canceled by Cadence: #{words}"
        end

      {_canceled, _operator} ->
        "#{label} contact canceled#{by}#{quote_reason(reason)}"
    end
  end

  defp label(craft, facts) do
    station =
      case facts[:station] do
        %{code: code} when is_binary(code) -> " · #{code}"
        _none -> ""
      end

    time =
      case facts[:starts_at] do
        %DateTime{} = at -> " " <> Calendar.strftime(at, "%H:%MZ")
        _unknown -> ""
      end

    "#{craft}#{station}#{time}"
  end

  defp provider_reason("provider_" <> _ = reason), do: reason
  defp provider_reason(_reason), do: nil

  defp quote_reason(reason) when is_binary(reason) and reason != "", do: ": “#{reason}”"
  defp quote_reason(_reason), do: ""

  @keys %{"cause" => :cause, "reason" => :reason}

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, @keys[key])
  defp value(_map, _key), do: nil
end
