defmodule SpotterWeb.CoChangeLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupCommit,
    CoChangeGroupMemberStat,
    Commit,
    Project
  }

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    projects =
      try do
        Project |> Ash.read!()
      rescue
        _ -> []
      end

    {:ok,
     socket
     |> assign(
       projects: projects,
       selected_project_id: nil,
       scope: :file,
       rows: [],
       sort_by: :max_frequency_30d,
       sort_dir: :desc,
       expanded_member: nil,
       expanded_commit_hash: nil,
       member_stats: %{},
       group_commits: %{},
       commit_details: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])

    socket =
      socket
      |> assign(selected_project_id: project_id, expanded_member: nil, expanded_commit_hash: nil)
      |> load_rows()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = parse_project_id(raw_id)
    path = if project_id, do: "/co-change?project_id=#{project_id}", else: "/co-change"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("toggle_scope", %{"scope" => scope}, socket) do
    scope = parse_scope(scope)

    {:noreply,
     socket
     |> assign(scope: scope, expanded_member: nil, expanded_commit_hash: nil)
     |> load_rows()}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)
    %{sort_by: current_field, sort_dir: current_dir} = socket.assigns

    new_dir =
      if field == current_field do
        if current_dir == :asc, do: :desc, else: :asc
      else
        :desc
      end

    {:noreply,
     socket
     |> assign(sort_by: field, sort_dir: new_dir)
     |> sort_rows()}
  end

  def handle_event("toggle_expand", %{"member" => member}, socket) do
    new_expanded =
      if socket.assigns.expanded_member == member, do: nil, else: member

    socket =
      socket
      |> assign(expanded_member: new_expanded, expanded_commit_hash: nil)
      |> maybe_load_provenance(new_expanded)

    {:noreply, socket}
  end

  def handle_event("toggle_commit_detail", %{"hash" => hash}, socket) do
    new_hash =
      if socket.assigns.expanded_commit_hash == hash, do: nil, else: hash

    socket =
      if new_hash && not Map.has_key?(socket.assigns.commit_details, new_hash) do
        load_commit_detail(socket, new_hash)
      else
        socket
      end

    {:noreply, assign(socket, expanded_commit_hash: new_hash)}
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp parse_scope("directory"), do: :directory
  defp parse_scope(_), do: :file

  defp load_rows(%{assigns: %{selected_project_id: nil}} = socket) do
    assign(socket, rows: [])
  end

  defp load_rows(socket) do
    %{selected_project_id: project_id, scope: scope} = socket.assigns

    groups =
      try do
        CoChangeGroup
        |> Ash.Query.filter(project_id == ^project_id and scope == ^scope)
        |> Ash.read!()
      rescue
        _ -> []
      end

    rows = derive_rows(groups)

    socket
    |> assign(rows: rows, member_stats: %{}, group_commits: %{})
    |> sort_rows()
  end

  defp derive_rows(groups) do
    groups
    |> Enum.flat_map(fn group ->
      Enum.map(group.members, fn member ->
        {member, group}
      end)
    end)
    |> Enum.group_by(fn {member, _} -> member end, fn {_, group} -> group end)
    |> Enum.map(fn {member, member_groups} ->
      max_freq = member_groups |> Enum.map(& &1.frequency_30d) |> Enum.max()

      last_seen =
        member_groups |> Enum.map(& &1.last_seen_at) |> Enum.max(DateTime, fn -> nil end)

      sorted_groups =
        Enum.sort_by(member_groups, fn g -> {-g.frequency_30d, g.group_key} end)

      %{
        member: member,
        max_frequency_30d: max_freq,
        last_seen_at: last_seen,
        groups: sorted_groups
      }
    end)
  end

  defp sort_rows(socket) do
    %{rows: rows, sort_by: field, sort_dir: dir} = socket.assigns

    sorted =
      case {field, dir} do
        {:member, :asc} ->
          Enum.sort_by(rows, & &1.member)

        {:member, :desc} ->
          Enum.sort_by(rows, & &1.member, :desc)

        {:max_frequency_30d, :desc} ->
          Enum.sort_by(rows, fn r -> {-r.max_frequency_30d, r.member} end)

        {:max_frequency_30d, :asc} ->
          Enum.sort_by(rows, fn r -> {r.max_frequency_30d, r.member} end)

        {:last_seen_at, :desc} ->
          Enum.sort_by(
            rows,
            fn r -> r.last_seen_at || ~U[1970-01-01 00:00:00Z] end,
            {:desc, DateTime}
          )

        {:last_seen_at, :asc} ->
          Enum.sort_by(
            rows,
            fn r -> r.last_seen_at || ~U[1970-01-01 00:00:00Z] end,
            {:asc, DateTime}
          )
      end

    assign(socket, rows: sorted)
  end

  defp maybe_load_provenance(socket, nil), do: socket

  defp maybe_load_provenance(socket, member) do
    %{selected_project_id: project_id, scope: scope} = socket.assigns

    # Load member stats for all groups this member belongs to
    stats =
      try do
        CoChangeGroupMemberStat
        |> Ash.Query.filter(
          project_id == ^project_id and scope == ^scope and member_path == ^member
        )
        |> Ash.read!()
      rescue
        _ -> []
      end

    # Find group_keys for this member
    group_keys =
      socket.assigns.rows
      |> Enum.find(fn r -> r.member == member end)
      |> case do
        nil -> []
        row -> Enum.map(row.groups, & &1.group_key)
      end

    # Load commits for those groups
    commits_by_group =
      Enum.reduce(group_keys, %{}, fn gk, acc ->
        commits =
          try do
            CoChangeGroupCommit
            |> Ash.Query.filter(
              project_id == ^project_id and scope == ^scope and group_key == ^gk
            )
            |> Ash.read!()
            |> Enum.sort_by(& &1.committed_at, {:desc, DateTime})
            |> Enum.take(10)
          rescue
            _ -> []
          end

        Map.put(acc, gk, commits)
      end)

    stats_by_group =
      Enum.group_by(stats, & &1.group_key)

    socket
    |> assign(
      member_stats: Map.merge(socket.assigns.member_stats, stats_by_group),
      group_commits: Map.merge(socket.assigns.group_commits, commits_by_group)
    )
  end

  defp load_commit_detail(socket, hash) do
    detail =
      try do
        Commit
        |> Ash.Query.filter(commit_hash == ^hash)
        |> Ash.read!()
        |> List.first()
      rescue
        _ -> nil
      end

    assign(socket, commit_details: Map.put(socket.assigns.commit_details, hash, detail))
  end

  defp format_group(group) do
    members = Enum.join(group.members, " + ")
    "#{members} \u00d7#{group.frequency_30d}"
  end

  defp scope_label(:file), do: "File"
  defp scope_label(:directory), do: "Directory"

  defp selected_project(assigns) do
    Enum.find(assigns.projects, &(&1.id == assigns.selected_project_id))
  end

  defp sort_indicator(assigns, field) do
    if assigns.sort_by == field do
      if assigns.sort_dir == :asc, do: " ↑", else: " ↓"
    else
      ""
    end
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_bytes(nil), do: "-"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <h1>Co-change Groups</h1>
        <div>
          <a :if={@selected_project_id} href={"/projects/#{@selected_project_id}/heatmap"} class="btn btn-ghost">Heatmap</a>
          <a :if={@selected_project_id} href={"/hotspots?project_id=#{@selected_project_id}"} class="btn btn-ghost">Hotspots</a>
        </div>
      </div>

      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
          <div class="filter-bar">
            <button
              phx-click="filter_project"
              phx-value-project-id="all"
              class={"filter-btn#{if @selected_project_id == nil, do: " is-active"}"}
            >
              All
            </button>
            <button
              :for={project <- @projects}
              phx-click="filter_project"
              phx-value-project-id={project.id}
              class={"filter-btn#{if @selected_project_id == project.id, do: " is-active"}"}
            >
              {project.name}
            </button>
          </div>
        </div>

        <div>
          <label class="filter-label">Scope</label>
          <div class="filter-bar">
            <button
              phx-click="toggle_scope"
              phx-value-scope="file"
              class={"filter-btn#{if @scope == :file, do: " is-active"}"}
            >
              Files
            </button>
            <button
              phx-click="toggle_scope"
              phx-value-scope="directory"
              class={"filter-btn#{if @scope == :directory, do: " is-active"}"}
            >
              Directories
            </button>
          </div>
        </div>
      </div>

      <%= if @selected_project_id == nil do %>
        <div class="empty-state">
          Select a project to view co-change groups.
        </div>
      <% else %>
        <%= if @rows == [] do %>
          <div class="empty-state">
            <%= if selected_project(assigns) do %>
              No co-change groups for {selected_project(assigns).name} yet.
            <% else %>
              Project not found.
            <% end %>
          </div>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>
                  <button phx-click="sort" phx-value-field="member" class="sort-btn">
                    {scope_label(@scope)}{sort_indicator(assigns, :member)}
                  </button>
                </th>
                <th>
                  <button phx-click="sort" phx-value-field="max_frequency_30d" class="sort-btn">
                    Max Co-Change (30d){sort_indicator(assigns, :max_frequency_30d)}
                  </button>
                </th>
                <th>
                  <button phx-click="sort" phx-value-field="last_seen_at" class="sort-btn">
                    Last Seen{sort_indicator(assigns, :last_seen_at)}
                  </button>
                </th>
                <th>Co-change groups</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @rows do %>
                <tr>
                  <td title={row.member}>
                    <button
                      phx-click="toggle_expand"
                      phx-value-member={row.member}
                      class="expand-btn"
                      aria-expanded={to_string(@expanded_member == row.member)}
                      aria-label={"Expand details for #{row.member}"}
                    >
                      <span class="expand-icon">{if @expanded_member == row.member, do: "▾", else: "▸"}</span>
                      {row.member}
                    </button>
                  </td>
                  <td>{row.max_frequency_30d}</td>
                  <td>{format_datetime(row.last_seen_at)}</td>
                  <td>
                    <span :for={group <- row.groups} class="badge" style="margin-right: 0.5rem;">
                      {format_group(group)}
                    </span>
                  </td>
                </tr>
                <%= if @expanded_member == row.member do %>
                  <tr class="detail-row">
                    <td colspan="4">
                      <div class="detail-panel" style="padding: 1rem;">
                        <%= for group <- row.groups do %>
                          <div style="margin-bottom: 1.5rem;">
                            <h4 style="margin: 0 0 0.5rem 0;">{format_group(group)}</h4>

                            <div style="margin-bottom: 0.75rem;">
                              <strong>Members</strong>
                              <% stats = Map.get(@member_stats, group.group_key, []) %>
                              <%= if stats == [] do %>
                                <div class="empty-state-small" style="padding: 0.25rem 0; opacity: 0.6;">No file metrics available.</div>
                              <% else %>
                                <table class="inner-table" style="margin-top: 0.25rem;">
                                  <thead>
                                    <tr>
                                      <th>Path</th>
                                      <th>Size</th>
                                      <th>LOC</th>
                                      <th>Measured at</th>
                                    </tr>
                                  </thead>
                                  <tbody>
                                    <tr :for={stat <- stats}>
                                      <td>{stat.member_path}</td>
                                      <td>{format_bytes(stat.size_bytes)}</td>
                                      <td>{stat.loc || "-"}</td>
                                      <td>{format_datetime(stat.measured_at)}</td>
                                    </tr>
                                  </tbody>
                                </table>
                              <% end %>
                            </div>

                            <div>
                              <strong>Relevant Commits</strong>
                              <% commits = Map.get(@group_commits, group.group_key, []) %>
                              <%= if commits == [] do %>
                                <div class="empty-state-small" style="padding: 0.25rem 0; opacity: 0.6;">No commit provenance recorded.</div>
                              <% else %>
                                <div style="margin-top: 0.25rem;">
                                  <%= for gc <- commits do %>
                                    <div style="margin-bottom: 0.5rem;">
                                      <button
                                        phx-click="toggle_commit_detail"
                                        phx-value-hash={gc.commit_hash}
                                        class="commit-link-btn"
                                        aria-expanded={to_string(@expanded_commit_hash == gc.commit_hash)}
                                        aria-label={"Show details for commit #{String.slice(gc.commit_hash, 0, 8)}"}
                                      >
                                        <code>{String.slice(gc.commit_hash, 0, 8)}</code>
                                      </button>
                                      <span style="opacity: 0.6; margin-left: 0.5rem;">{format_datetime(gc.committed_at)}</span>

                                      <%= if @expanded_commit_hash == gc.commit_hash do %>
                                        <% detail = Map.get(@commit_details, gc.commit_hash) %>
                                        <div class="commit-detail-panel" style="margin: 0.5rem 0 0 1rem; padding: 0.5rem; border-left: 2px solid var(--border-color, #444);">
                                          <%= if detail do %>
                                            <div><strong>Hash:</strong> <code>{detail.commit_hash}</code></div>
                                            <div><strong>Date:</strong> {format_datetime(detail.committed_at)}</div>
                                            <div :if={detail.git_branch}><strong>Branch:</strong> {detail.git_branch}</div>
                                            <div :if={detail.changed_files != []}>
                                              <strong>Changed files ({length(detail.changed_files)}):</strong>
                                              <ul style="margin: 0.25rem 0 0 1rem; padding: 0;">
                                                <li :for={f <- detail.changed_files} style="font-size: 0.85em;">{f}</li>
                                              </ul>
                                            </div>
                                          <% else %>
                                            <div style="opacity: 0.6;">Commit details not available in database.</div>
                                          <% end %>
                                        </div>
                                      <% end %>
                                    </div>
                                  <% end %>
                                </div>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        <% end %>
      <% end %>
    </div>
    """
  end
end
