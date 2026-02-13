defmodule SpotterWeb.AnnotationComponents do
  @moduledoc """
  Shared HEEx components for annotation rendering.

  Provides reusable annotation editor (form) and annotation card list
  used by `SessionLive`, `SubagentLive`, and future detail pages.
  """
  use Phoenix.Component

  @doc """
  Renders the annotation editor: selected-text preview + comment form + save/cancel buttons.

  ## Assigns

    * `:selected_text` (required) - the text the user selected
    * `:selection_label` - descriptive label for the selection (default "Selected text")
    * `:save_event` - the phx-submit event name (default "save_annotation")
    * `:clear_event` - the phx-click cancel event name (default "clear_selection")
  """
  attr(:selected_text, :string, required: true)
  attr(:selection_label, :string, default: "Selected text")
  attr(:save_event, :string, default: "save_annotation")
  attr(:clear_event, :string, default: "clear_selection")

  def annotation_editor(assigns) do
    ~H"""
    <div class="annotation-form">
      <div class="annotation-form-hint">{@selection_label}</div>
      <pre class="annotation-form-preview"><%= @selected_text %></pre>
      <form phx-submit={@save_event}>
        <textarea
          name="comment"
          placeholder="Add a comment..."
          required
          class="annotation-form-textarea"
        />
        <div class="annotation-form-actions">
          <button type="submit" class="btn btn-success">Save</button>
          <button type="button" class="btn" phx-click={@clear_event}>Cancel</button>
        </div>
      </form>
    </div>
    """
  end

  @doc """
  Renders a list of annotation cards.

  ## Assigns

    * `:annotations` (required) - list of annotation records (preloaded with `:message_refs`)
    * `:highlight_event` - the phx-click event for highlighting (default "highlight_annotation")
    * `:delete_event` - the phx-click event for deleting (default "delete_annotation")
    * `:empty_message` - text shown when no annotations exist (default "No annotations yet.")
  """
  attr(:annotations, :list, required: true)
  attr(:highlight_event, :string, default: "highlight_annotation")
  attr(:delete_event, :string, default: "delete_annotation")
  attr(:empty_message, :string, default: "No annotations yet.")

  def annotation_cards(assigns) do
    ~H"""
    <%= if @annotations == [] do %>
      <p class="text-muted text-sm">{@empty_message}</p>
    <% end %>

    <%= for ann <- @annotations do %>
      <div class="annotation-card" phx-click={@highlight_event} phx-value-id={ann.id}>
        <div class="flex items-center gap-2 mb-2">
          <span class={"annotation-source-badge annotation-source-#{ann.source}"}>
            {source_badge_text(ann.source)}
          </span>
          <span
            :if={ann.source == :transcript && ann.message_refs != []}
            class="text-muted text-xs"
          >
            {length(ann.message_refs)} messages
          </span>
        </div>
        <pre class="annotation-text"><%= ann.selected_text %></pre>
        <p class="annotation-comment"><%= ann.comment %></p>
        <div class="annotation-meta">
          <span class="annotation-time"><%= Calendar.strftime(ann.inserted_at, "%H:%M") %></span>
          <button
            class="btn-ghost text-error text-xs"
            phx-click={@delete_event}
            phx-value-id={ann.id}
          >
            Delete
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  @doc false
  def source_badge_text(:transcript), do: "Transcript"
  def source_badge_text(:terminal), do: "Terminal"
  def source_badge_text(:file), do: "File"

  def source_badge_text(source) when is_atom(source),
    do: source |> to_string() |> String.capitalize()

  def source_badge_text(_), do: "Unknown"

  @doc """
  Returns a human-readable label for a selection, based on source and message IDs.
  """
  def selection_label(:transcript, [_ | _] = message_ids) do
    "Selected transcript text (#{length(message_ids)} messages)"
  end

  def selection_label(:transcript, _), do: "Selected transcript text"
  def selection_label(:file, _), do: "Selected file text"
  def selection_label(_, _), do: "Selected terminal text"
end
