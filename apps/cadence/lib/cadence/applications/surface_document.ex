defmodule Cadence.Applications.SurfaceDocument do
  @moduledoc "Typed declarative data returned to the host renderer for one surface."

  alias Cadence.Applications.SurfaceElements.{
    Activity,
    Diagnostics,
    GeneratedForm,
    PacketBindings,
    Stat,
    Table
  }

  @type t :: %__MODULE__{
          title: binary(),
          description: binary() | nil,
          stats: [Stat.t()],
          diagnostics: Diagnostics.t() | nil,
          form: GeneratedForm.t() | nil,
          packet_bindings: PacketBindings.t() | nil,
          table: Table.t() | nil,
          activity: Activity.t() | nil
        }

  @enforce_keys [:title]
  defstruct [
    :title,
    :description,
    :diagnostics,
    :form,
    :packet_bindings,
    :table,
    :activity,
    stats: []
  ]

  @max_stats 6

  @type validation_error ::
          :invalid_application_surface_document
          | :invalid_application_surface_stat
          | :invalid_application_surface_diagnostics
          | :invalid_application_surface_form
          | :invalid_application_surface_packet_bindings
          | :invalid_application_surface_table
          | :invalid_application_surface_activity
          | :undeclared_application_surface_action

  @spec validate(t()) :: :ok | {:error, validation_error()}
  def validate(%__MODULE__{} = document) do
    with true <- valid_text?(document.title),
         true <- optional_text?(document.description),
         :ok <- validate_stats(document.stats),
         :ok <- validate_diagnostics(document.diagnostics),
         :ok <- validate_form(document.form),
         :ok <- validate_packet_bindings(document.packet_bindings),
         :ok <- validate_table(document.table),
         :ok <- validate_activity(document.activity),
         true <- unique_block_ids?(document) do
      :ok
    else
      false -> {:error, :invalid_application_surface_document}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(_document), do: {:error, :invalid_application_surface_document}

  @spec validate(t(), [binary()]) :: :ok | {:error, validation_error()}
  def validate(%__MODULE__{} = document, declared_actions) when is_list(declared_actions) do
    with :ok <- validate(document) do
      with :ok <- validate_form_action(document.form, declared_actions) do
        validate_packet_bindings_action(document.packet_bindings, declared_actions)
      end
    end
  end

  def validate(_document, _declared_actions),
    do: {:error, :invalid_application_surface_document}

  defp validate_stats(stats) when is_list(stats) do
    stat_ids = Enum.map(stats, &stat_id/1)

    if length(stats) <= @max_stats and Enum.all?(stats, &(Stat.validate(&1) == :ok)) and
         length(Enum.uniq(stat_ids)) == length(stat_ids) do
      :ok
    else
      {:error, :invalid_application_surface_stat}
    end
  end

  defp validate_stats(_stats), do: {:error, :invalid_application_surface_stat}

  defp validate_diagnostics(nil), do: :ok
  defp validate_diagnostics(%Diagnostics{} = diagnostics), do: Diagnostics.validate(diagnostics)

  defp validate_diagnostics(_diagnostics),
    do: {:error, :invalid_application_surface_diagnostics}

  defp validate_form(nil), do: :ok
  defp validate_form(%GeneratedForm{} = form), do: GeneratedForm.validate(form)
  defp validate_form(_form), do: {:error, :invalid_application_surface_form}

  defp validate_packet_bindings(nil), do: :ok

  defp validate_packet_bindings(%PacketBindings{} = bindings),
    do: PacketBindings.validate(bindings)

  defp validate_packet_bindings(_bindings),
    do: {:error, :invalid_application_surface_packet_bindings}

  defp validate_table(nil), do: :ok
  defp validate_table(%Table{} = table), do: Table.validate(table)
  defp validate_table(_table), do: {:error, :invalid_application_surface_table}

  defp validate_activity(nil), do: :ok
  defp validate_activity(%Activity{} = activity), do: Activity.validate(activity)
  defp validate_activity(_activity), do: {:error, :invalid_application_surface_activity}

  defp validate_form_action(nil, _declared_actions), do: :ok

  defp validate_form_action(%GeneratedForm{action_id: action_id}, declared_actions) do
    if action_id in declared_actions,
      do: :ok,
      else: {:error, :undeclared_application_surface_action}
  end

  defp validate_packet_bindings_action(nil, _declared_actions), do: :ok

  defp validate_packet_bindings_action(
         %PacketBindings{action_id: action_id},
         declared_actions
       ) do
    if action_id in declared_actions,
      do: :ok,
      else: {:error, :undeclared_application_surface_action}
  end

  defp unique_block_ids?(document) do
    block_ids =
      [
        document.diagnostics,
        document.form,
        document.packet_bindings,
        document.table,
        document.activity
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)

    length(Enum.uniq(block_ids)) == length(block_ids)
  end

  defp stat_id(%Stat{id: id}), do: id
  defp stat_id(_stat), do: nil

  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
