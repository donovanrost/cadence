defmodule Cadence.ContactPlanning.ContactRequirementTemplateVersion do
  @moduledoc "Immutable schedule and Requirement content for one recurring template version."

  alias Cadence.ContactPlanning.{ContentHash, RequirementSchedule}
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @type t :: %__MODULE__{
          contact_requirement_template_version_id: binary(),
          contact_requirement_template_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          version: pos_integer(),
          spacecraft_id: binary(),
          schedule_document: map(),
          requirement_document: map(),
          catch_up_policy_document: map(),
          content_sha256: binary(),
          created_by: binary(),
          created_at: DateTime.t()
        }

  defstruct [
    :contact_requirement_template_version_id,
    :contact_requirement_template_id,
    :organization_id,
    :mission_id,
    :version,
    :spacecraft_id,
    :schedule_document,
    :requirement_document,
    :catch_up_policy_document,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    template =
      %__MODULE__{
        contact_requirement_template_version_id:
          value(
            attrs,
            :contact_requirement_template_version_id,
            Ids.new("contact_requirement_template_version")
          ),
        contact_requirement_template_id: required(attrs, :contact_requirement_template_id),
        organization_id: required(attrs, :organization_id),
        mission_id: required(attrs, :mission_id),
        version: positive(value(attrs, :version, 1), :version),
        spacecraft_id: required(attrs, :spacecraft_id),
        schedule_document:
          attrs
          |> value(:schedule_document)
          |> RequirementSchedule.normalize(),
        requirement_document:
          attrs
          |> value(:requirement_document)
          |> document(:requirement_document),
        catch_up_policy_document:
          attrs
          |> value(:catch_up_policy_document, %{})
          |> normalize_catch_up_policy(),
        content_sha256: value(attrs, :content_sha256),
        created_by: required(attrs, :created_by),
        created_at: datetime(value(attrs, :created_at, DateTime.utc_now()), :created_at)
      }

    %{template | content_sha256: template.content_sha256 || content_sha256(template)}
  end

  @spec content_document(t()) :: map()
  def content_document(%__MODULE__{} = version) do
    %{
      "spacecraft_id" => version.spacecraft_id,
      "schedule" => version.schedule_document,
      "requirement" => version.requirement_document,
      "catch_up_policy" => version.catch_up_policy_document
    }
  end

  @spec content_sha256(t()) :: binary()
  def content_sha256(%__MODULE__{} = version),
    do: version |> content_document() |> ContentHash.sha256()

  defp normalize_catch_up_policy(policy) when is_map(policy) do
    policy = JsonDocument.encode(policy)
    maximum = Map.get(policy, "maximum_occurrences_per_run", 100)
    lookback = Map.get(policy, "maximum_lookback_seconds", 7 * 24 * 60 * 60)

    %{
      "maximum_occurrences_per_run" =>
        bounded_positive(maximum, 1, 1_000, "maximum_occurrences_per_run"),
      "maximum_lookback_seconds" =>
        bounded_non_negative(
          lookback,
          31 * 24 * 60 * 60,
          "maximum_lookback_seconds"
        )
    }
  end

  defp normalize_catch_up_policy(_policy),
    do: raise(ArgumentError, "catch_up_policy_document must be an object")

  defp document(value, _field) when is_map(value), do: JsonDocument.encode(value)
  defp document(_value, field), do: raise(ArgumentError, "#{field} must be an object")

  defp bounded_positive(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: value

  defp bounded_positive(_value, minimum, maximum, field),
    do: raise(ArgumentError, "#{field} must be between #{minimum} and #{maximum}")

  defp bounded_non_negative(value, maximum, _field)
       when is_integer(value) and value >= 0 and value <= maximum,
       do: value

  defp bounded_non_negative(_value, maximum, field),
    do: raise(ArgumentError, "#{field} must be between 0 and #{maximum}")

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
