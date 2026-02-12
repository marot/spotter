defmodule SpotterWeb.SubagentLive do
  use Phoenix.LiveView

  alias Spotter.Services.{ReviewUpdates, TranscriptRenderer}

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationMessageRef,
    Message,
    Session,
    Subagent
  }

  require Ash.Query

  @impl true
  def mount(%{"session_id" => session_id, "agent_id" => agent_id}, _session, socket) do
    case load_subagent_data(session_id, agent_id) do
      {:ok, session_record, subagent, messages, rendered_lines, annotations} ->
        socket =
          assign(socket,
            session_id: session_id,
            agent_id: agent_id,
            session_record: session_record,
            subagent: subagent,
            messages: messages,
            rendered_lines: rendered_lines,
            annotations: annotations,
            selected_text: nil,
            selection_message_ids: [],
            not_found: false
          )

        {:ok, socket}

      :not_found ->
        {:ok,
         assign(socket,
           session_id: session_id,
           agent_id: agent_id,
           not_found: true
         )}
    end
  end

  @impl true
  def handle_event("transcript_text_selected", params, socket) do
    {:noreply,
     assign(socket,
       selected_text: params["text"],
       selection_message_ids: params["message_ids"] || []
     )}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_text: nil, selection_message_ids: [])}
  end

  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    params = %{
      session_id: socket.assigns.session_record.id,
      subagent_id: socket.assigns.subagent.id,
      source: :transcript,
      selected_text: socket.assigns.selected_text,
      comment: comment
    }

    case Ash.create(Annotation, params) do
      {:ok, annotation} ->
        create_message_refs(annotation, socket)
        ReviewUpdates.broadcast_counts()

        {:noreply,
         socket
         |> assign(
           annotations: load_annotations(socket.assigns.subagent),
           selected_text: nil,
           selection_message_ids: []
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_annotation", %{"id" => id}, socket) do
    case Ash.get(Annotation, id) do
      {:ok, annotation} ->
        Ash.destroy!(annotation)
        ReviewUpdates.broadcast_counts()
        {:noreply, assign(socket, annotations: load_annotations(socket.assigns.subagent))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("highlight_annotation", %{"id" => id}, socket) do
    case Ash.get(Annotation, id, load: [message_refs: :message]) do
      {:ok, %{source: :transcript, message_refs: refs}} when refs != [] ->
        message_ids = refs |> Enum.sort_by(& &1.ordinal) |> Enum.map(& &1.message.id)

        socket =
          socket
          |> push_event("scroll_to_message", %{id: List.first(message_ids)})
          |> push_event("highlight_transcript_annotation", %{message_ids: message_ids})

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_subagent_data(session_id, agent_id) do
    with {:ok, %Session{} = session_record} <-
           Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one(),
         {:ok, %Subagent{} = subagent} <-
           Subagent
           |> Ash.Query.filter(session_id == ^session_record.id and agent_id == ^agent_id)
           |> Ash.read_one() do
      messages = load_messages(subagent)
      rendered_lines = TranscriptRenderer.render(messages)
      annotations = load_annotations(subagent)
      {:ok, session_record, subagent, messages, rendered_lines, annotations}
    else
      _ -> :not_found
    end
  end

  defp load_messages(subagent) do
    Message
    |> Ash.Query.filter(subagent_id == ^subagent.id)
    |> Ash.Query.sort(timestamp: :asc)
    |> Ash.read!()
    |> Enum.map(fn msg ->
      %{
        id: msg.id,
        uuid: msg.uuid,
        type: msg.type,
        role: msg.role,
        content: msg.content,
        timestamp: msg.timestamp
      }
    end)
  end

  defp load_annotations(subagent) do
    Annotation
    |> Ash.Query.filter(subagent_id == ^subagent.id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
    |> Ash.load!(message_refs: :message)
  end

  defp create_message_refs(annotation, socket) do
    socket.assigns.selection_message_ids
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.each(fn {msg_id, ordinal} ->
      Ash.create!(AnnotationMessageRef, %{
        annotation_id: annotation.id,
        message_id: msg_id,
        ordinal: ordinal
      })
    end)
  end

  defp transcript_row_classes(line) do
    kind =
      case line[:kind] do
        :tool_use -> ["is-tool-use"]
        :tool_result -> ["is-tool-result"]
        :thinking -> ["is-thinking"]
        _ -> []
      end

    type = if line.type == :user, do: ["is-user"], else: []
    code = if line[:render_mode] == :code, do: ["is-code"], else: []

    Enum.join(["transcript-row"] ++ kind ++ type ++ code, " ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @not_found do %>
      <div class="breadcrumb">
        <a href="/">Dashboard</a>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-current">Agent not found</span>
      </div>
      <div class="terminal-connecting">
        <div>
          <div class="terminal-connecting-title">Subagent not found</div>
          <div class="terminal-connecting-subtitle">
            The requested subagent could not be found.
          </div>
        </div>
      </div>
    <% else %>
      <div class="breadcrumb">
        <a href="/">Dashboard</a>
        <span class="breadcrumb-sep">/</span>
        <a href={"/sessions/#{@session_id}"}>Session {String.slice(@session_id, 0, 7)}</a>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-current">Agent {@subagent.slug || String.slice(@agent_id, 0, 7)}</span>
      </div>
      <div class="session-layout">
        <div class="session-transcript" id="transcript-panel">
          <div class="transcript-header">
            <h3>Transcript</h3>
          </div>

          <%= if @rendered_lines != [] do %>
            <div id="transcript-messages" phx-hook="TranscriptSelection" phx-update="replace">
              <%= for line <- @rendered_lines do %>
                <div
                  id={"msg-#{line.line_number}"}
                  data-message-id={line.message_id}
                  class={transcript_row_classes(line)}
                >
                  <span class="row-text"><%= line.line %></span>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="transcript-empty">
              No transcript available for this agent.
            </p>
          <% end %>
        </div>
        <div class="session-sidebar">
          <div class="sidebar-tab-content">
            <h3 class="mb-4">Annotations</h3>

            <%= if @selected_text do %>
              <div class="annotation-form">
                <div class="annotation-form-hint">
                  Selected transcript text
                  <span :if={@selection_message_ids != []}>
                    ({length(@selection_message_ids)} messages)
                  </span>
                </div>
                <pre class="annotation-form-preview"><%= @selected_text %></pre>
                <form phx-submit="save_annotation">
                  <textarea
                    name="comment"
                    placeholder="Add a comment..."
                    required
                    class="annotation-form-textarea"
                  />
                  <div class="annotation-form-actions">
                    <button type="submit" class="btn btn-success">Save</button>
                    <button type="button" class="btn" phx-click="clear_selection">Cancel</button>
                  </div>
                </form>
              </div>
            <% end %>

            <%= if @annotations == [] do %>
              <p class="text-muted text-sm">
                Select text in the transcript to add annotations.
              </p>
            <% end %>

            <%= for ann <- @annotations do %>
              <div class="annotation-card" phx-click="highlight_annotation" phx-value-id={ann.id}>
                <div class="flex items-center gap-2 mb-2">
                  <span class="badge badge-agent">Transcript</span>
                  <span :if={ann.message_refs != []} class="text-muted text-xs">
                    {length(ann.message_refs)} messages
                  </span>
                </div>
                <pre class="annotation-text"><%= ann.selected_text %></pre>
                <p class="annotation-comment"><%= ann.comment %></p>
                <div class="annotation-meta">
                  <span class="annotation-time">
                    <%= Calendar.strftime(ann.inserted_at, "%H:%M") %>
                  </span>
                  <button class="btn-ghost text-error text-xs" phx-click="delete_annotation" phx-value-id={ann.id}>
                    Delete
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
