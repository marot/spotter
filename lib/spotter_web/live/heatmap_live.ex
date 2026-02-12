defmodule SpotterWeb.HeatmapLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{FileHeatmap, Project}

  require Ash.Query

  @max_rows 100

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Ash.get(Project, project_id) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(project: project, min_score: 0, sort_by: :heat_score)
         |> load_heatmap()}

      _ ->
        {:ok, assign(socket, project: nil, heatmap_entries: [])}
    end
  end

  @impl true
  def handle_event("filter_min_score", %{"min_score" => raw}, socket) do
    min_score = parse_min_score(raw)

    {:noreply,
     socket
     |> assign(min_score: min_score)
     |> load_heatmap()}
  end

  def handle_event("sort_by", %{"field" => field}, socket) do
    sort_by = parse_sort_by(field)

    {:noreply,
     socket
     |> assign(sort_by: sort_by)
     |> load_heatmap()}
  end

  defp load_heatmap(socket) do
    %{project: project, min_score: min_score, sort_by: sort_by} = socket.assigns

    entries =
      FileHeatmap
      |> Ash.Query.filter(project_id == ^project.id and heat_score >= ^min_score)
      |> Ash.Query.sort([{sort_by, :desc}])
      |> Ash.Query.limit(@max_rows)
      |> Ash.read!()

    assign(socket, heatmap_entries: entries)
  end

  defp parse_min_score(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, _} -> max(0, min(n, 100))
      :error -> 0
    end
  end

  defp parse_min_score(_), do: 0

  defp parse_sort_by("change_count_30d"), do: :change_count_30d
  defp parse_sort_by(_), do: :heat_score

  defp heat_badge_class(score) when score >= 70, do: "badge badge-hot"
  defp heat_badge_class(score) when score >= 40, do: "badge badge-warm"
  defp heat_badge_class(score) when score >= 15, do: "badge badge-mild"
  defp heat_badge_class(_), do: "badge badge-cold"

  defp relative_time(nil), do: "\u2014"

  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <%= if @project == nil do %>
        <div class="empty-state">
          <p>Project not found.</p>
          <a href="/" class="btn">Back to dashboard</a>
        </div>
      <% else %>
        <div class="page-header">
          <h1>File Heatmap &mdash; {@project.name}</h1>
          <a href="/" class="btn btn-ghost">Back</a>
        </div>

        <div class="filter-section">
          <div>
            <label class="filter-label">Min score</label>
            <div class="filter-bar">
              <button
                :for={threshold <- [0, 15, 40, 70]}
                phx-click="filter_min_score"
                phx-value-min_score={threshold}
                class={"filter-btn#{if @min_score == threshold, do: " is-active"}"}
              >
                {threshold}+
              </button>
            </div>
          </div>

          <div>
            <label class="filter-label">Sort by</label>
            <div class="filter-bar">
              <button
                phx-click="sort_by"
                phx-value-field="heat_score"
                class={"filter-btn#{if @sort_by == :heat_score, do: " is-active"}"}
              >
                Heat score
              </button>
              <button
                phx-click="sort_by"
                phx-value-field="change_count_30d"
                class={"filter-btn#{if @sort_by == :change_count_30d, do: " is-active"}"}
              >
                Change count
              </button>
            </div>
          </div>
        </div>

        <%= if @heatmap_entries == [] do %>
          <div class="empty-state">
            No file activity data for this project yet.
            Heatmap data is computed automatically when file snapshots and commits are ingested.
          </div>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>File</th>
                <th>Heat</th>
                <th>Changes (30d)</th>
                <th>Last changed</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @heatmap_entries}>
                <td title={entry.relative_path}>
                  {entry.relative_path}
                </td>
                <td>
                  <span class={heat_badge_class(entry.heat_score)}>
                    {Float.round(entry.heat_score, 1)}
                  </span>
                </td>
                <td>{entry.change_count_30d} changes</td>
                <td>{relative_time(entry.last_changed_at)}</td>
              </tr>
            </tbody>
          </table>
        <% end %>
      <% end %>
    </div>

    <style>
      .badge-hot { background: #dc2626; color: #fff; }
      .badge-warm { background: #ea580c; color: #fff; }
      .badge-mild { background: #ca8a04; color: #fff; }
      .badge-cold { background: #6b7280; color: #fff; }
    </style>
    """
  end
end
