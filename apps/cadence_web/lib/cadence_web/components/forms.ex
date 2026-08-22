defmodule CadenceWeb.Components.Forms do
  @moduledoc """
  Shared form-layout building blocks. Compose the existing `<.button>` and HUD
  utilities — no new CSS.
  """

  use Phoenix.Component

  import CadenceWeb.Components.Button, only: [button: 1]

  @doc """
  The canonical form footer: a primary submit button and an optional ghost
  Cancel link, over the standard `border-t border-base-300/60 pt-5` rule.

  Pass `cancel_navigate` to render the Cancel link. Any extra actions go in the
  inner block (rendered after Cancel).
  """
  attr :submit, :string, default: "Save"
  attr :submit_type, :string, default: "submit"
  attr :cancel_navigate, :string, default: nil
  attr :cancel_label, :string, default: "Cancel"
  attr :class, :string, default: nil
  slot :inner_block

  def form_actions(assigns) do
    ~H"""
    <div class={["flex items-center gap-3 border-t border-base-300/60 pt-5", @class]}>
      <.button type={@submit_type} size={:md}>{@submit}</.button>
      <.button :if={@cancel_navigate} variant={:ghost} size={:md} navigate={@cancel_navigate}>
        {@cancel_label}
      </.button>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A numbered form section: an `① Title ──────` heading over the section's
  fields. Wraps its body in a `space-y-4` section so consecutive fields stack
  with the standard rhythm.
  """
  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def form_section(assigns) do
    ~H"""
    <section id={@id} class={["space-y-4", @class]}>
      <div class="flex items-center gap-3">
        <span class="hud-label text-primary/70">{@number}</span>
        <h2 class="hud-label">{@title}</h2>
        <div class="flex-1 h-px bg-base-300/60"></div>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
