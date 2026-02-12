defmodule SpotterWeb.ProjectReviewLive do
  use Phoenix.LiveView

  alias Spotter.Services.{ReviewSessionRegistry, ReviewTokenStore, Tmux}
  alias Spotter.Transcripts.{Annotation, Project, Session}
  require Ash.Query

  @review_port Application.compile_env(:spotter, [SpotterWeb.Endpoint, :http, :port], 1100)
  @review_heartbeat_interval 10_000

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Ash.get(Project, project_id) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(project: project, review_session_name: nil)
         |> load_review_data()}

      _ ->
        {:ok,
         assign(socket,
           project: nil,
           sessions: [],
           open_annotations: [],
           review_session_name: nil
         )}
    end
  end

  @impl true
  def handle_event("close_review_session", _params, socket) do
    project = socket.assigns.project

    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.select([:id])
      |> Ash.read!()

    session_ids = Enum.map(sessions, & &1.id)

    closed_count =
      if session_ids == [] do
        0
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == :open)
        |> Ash.read!()
        |> Enum.reduce(0, fn ann, acc ->
          Ash.update!(ann, %{}, action: :close)
          acc + 1
        end)
      end

    {:noreply,
     socket
     |> put_flash(:info, "Closed #{closed_count} annotations")
     |> load_review_data()}
  end

  def handle_event("open_conversation", _params, socket) do
    project = socket.assigns.project
    token = ReviewTokenStore.mint(project.id)

    case tmux_module().launch_project_review(project.id, token, @review_port) do
      {:ok, name} ->
        previous = socket.assigns.review_session_name

        if previous && previous != name do
          ReviewSessionRegistry.deregister(previous)
        end

        ReviewSessionRegistry.register(name)
        Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)

        {:noreply,
         socket
         |> assign(review_session_name: name)
         |> put_flash(:info, "Launched review session: #{name}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :info, "Failed to launch: #{reason}")}
    end
  end

  @impl true
  def handle_info(:review_heartbeat, socket) do
    if name = socket.assigns.review_session_name do
      ReviewSessionRegistry.heartbeat(name)
      Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)
    end

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if name = socket.assigns[:review_session_name] do
      ReviewSessionRegistry.deregister(name)
    end

    :ok
  end

  defp tmux_module, do: Application.get_env(:spotter, :tmux_module, Tmux)

  defp load_review_data(socket) do
    project = socket.assigns.project

    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.sort(started_at: :desc)
      |> Ash.read!()

    session_ids = Enum.map(sessions, & &1.id)
    sessions_by_id = Map.new(sessions, &{&1.id, &1})

    open_annotations =
      if session_ids == [] do
        []
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == :open)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!()
        |> Ash.load!(message_refs: :message)
      end

    assign(socket,
      sessions: sessions,
      sessions_by_id: sessions_by_id,
      open_annotations: open_annotations
    )
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp source_badge(:transcript), do: "Transcript"
  defp source_badge(_), do: "Terminal"

  defp source_badge_class(:transcript), do: "badge badge-agent"
  defp source_badge_class(_), do: "badge badge-terminal"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="breadcrumb">
        <a href="/">Dashboard</a>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-current">
          <%= if @project, do: "Review: #{@project.name}", else: "Project not found" %>
        </span>
      </div>

      <div :if={Phoenix.Flash.get(@flash, :info)} class="flash-info">
        {Phoenix.Flash.get(@flash, :info)}
      </div>

      <div :if={Phoenix.Flash.get(@flash, :error)} class="flash-error">
        {Phoenix.Flash.get(@flash, :error)}
      </div>

      <%= if is_nil(@project) do %>
        <div class="empty-state">
          The requested project does not exist.
        </div>
      <% else %>
        <%= if @open_annotations == [] do %>
          <div class="empty-state">
            No open annotations for this project.
          </div>
        <% else %>
          <div class="review-header">
            <span class="review-count">
              {length(@open_annotations)} open annotations across {map_size(@sessions_by_id)} sessions
            </span>
            <div class="review-actions">
              <button class="btn btn-success" phx-click="open_conversation">
                Open conversation
              </button>
              <button class="btn btn-danger" phx-click="close_review_session">
                Close review session
              </button>
            </div>
          </div>

          <%= for ann <- @open_annotations do %>
            <% session = Map.get(@sessions_by_id, ann.session_id) %>
            <div class="annotation-card">
              <div class="flex items-center gap-2 mb-2">
                <span class={source_badge_class(ann.source)}>
                  {source_badge(ann.source)}
                </span>
                <span :if={ann.source == :transcript && ann.message_refs != []} class="text-muted text-xs">
                  {length(ann.message_refs)} messages
                </span>
                <span :if={session} class="text-muted text-xs">
                  {session_label(session)}
                </span>
              </div>
              <pre class="annotation-text"><%= ann.selected_text %></pre>
              <p class="annotation-comment"><%= ann.comment %></p>
              <div class="annotation-meta">
                <span class="annotation-time">
                  <%= Calendar.strftime(ann.inserted_at, "%H:%M") %>
                </span>
                <a :if={session} href={"/sessions/#{session.session_id}"} class="text-xs">
                  View session
                </a>
              </div>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end
end
