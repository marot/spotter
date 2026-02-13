defmodule SpotterWeb.ProductLive do
  use Phoenix.LiveView

  alias Spotter.ProductSpec
  alias Spotter.Transcripts.{Commit, Project}

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

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
       tree: [],
       expanded: MapSet.new(),
       search_query: "",
       dolt_available: dolt_available?(),
       commit_id_cache: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])

    # Default to first project if none selected
    project_id =
      project_id || socket.assigns.projects |> List.first() |> then(&(&1 && &1.id))

    socket =
      socket
      |> assign(selected_project_id: project_id)
      |> load_tree()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = parse_project_id(raw_id)
    path = if project_id, do: "/product?project_id=#{project_id}", else: "/product"
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("expand_all", _params, socket) do
    ids =
      for domain <- socket.assigns.tree,
          id <- [domain.id | Enum.map(domain.features, & &1.id)],
          do: id

    {:noreply, assign(socket, expanded: MapSet.new(ids))}
  end

  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, expanded: MapSet.new())}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, search_query: String.trim(q))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <div>
          <h1>Product</h1>
          <p class="text-muted text-sm">Rolling spec derived from commits</p>
        </div>
      </div>

      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
          <div class="filter-bar">
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
      </div>

      <div :if={not @dolt_available} class="product-callout">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <circle cx="8" cy="8" r="6" /><line x1="8" y1="5" x2="8" y2="8" /><circle cx="8" cy="11" r="0.5" fill="currentColor" />
        </svg>
        <span>Dolt is unavailable. Start it with <code>docker compose -f docker-compose.dolt.yml up -d</code></span>
      </div>

      <div :if={@dolt_available and @selected_project_id != nil}>
        <div class="product-toolbar">
          <div class="product-search">
            <input
              type="text"
              placeholder="Search domains, features, requirements..."
              phx-change="search"
              phx-debounce="200"
              name="q"
              value={@search_query}
              class="product-search-input"
            />
          </div>
          <div class="product-actions">
            <button phx-click="expand_all" class="btn btn-ghost btn-sm">Expand all</button>
            <button phx-click="collapse_all" class="btn btn-ghost btn-sm">Collapse all</button>
          </div>
        </div>

        <div :if={filtered_tree(@tree, @search_query) == []} class="empty-state">
          <p :if={@search_query != ""}>No results for "<strong>{@search_query}</strong>"</p>
          <p :if={@search_query == ""}>No domains yet. The spec agent populates this from commits.</p>
        </div>

        <div :for={domain <- filtered_tree(@tree, @search_query)} class="product-domain">
          <button class="product-row product-row--domain" phx-click="toggle" phx-value-id={domain.id}>
            <span class={"product-chevron#{if MapSet.member?(@expanded, domain.id), do: " is-open"}"}>&#9656;</span>
            <span class="product-name">{domain.name}</span>
            <code class="product-key">{domain.spec_key}</code>
            <.commit_hash hash={domain.updated_by_git_commit} cache={@commit_id_cache} />
            <span class="product-count">{length(domain.features)} features</span>
          </button>

          <div :if={MapSet.member?(@expanded, domain.id)} class="product-children">
            <div :for={feature <- domain.features} class="product-feature">
              <button class="product-row product-row--feature" phx-click="toggle" phx-value-id={feature.id}>
                <span class={"product-chevron#{if MapSet.member?(@expanded, feature.id), do: " is-open"}"}>&#9656;</span>
                <span class="product-name">{feature.name}</span>
                <code class="product-key">{feature.spec_key}</code>
                <.commit_hash hash={feature.updated_by_git_commit} cache={@commit_id_cache} />
                <span class="product-count">{length(feature.requirements)} reqs</span>
              </button>

              <div :if={MapSet.member?(@expanded, feature.id)} class="product-children">
                <div :for={req <- feature.requirements} class="product-requirement">
                  <div class="product-row product-row--req">
                    <code class="product-key">{req.spec_key}</code>
                    <span class="product-statement">{req.statement}</span>
                    <.commit_hash hash={req.updated_by_git_commit} cache={@commit_id_cache} />
                  </div>
                  <p :if={req.rationale} class="product-rationale">{req.rationale}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={@dolt_available and @selected_project_id == nil} class="empty-state">
        <p>Select a project to view its product specification.</p>
      </div>
    </div>
    """
  end

  defp commit_hash(assigns) do
    ~H"""
    <span :if={@hash} class="product-commit">
      <a :if={@cache[@hash]} href={"/history/commits/#{@cache[@hash]}"}>
        <code>{String.slice(@hash, 0, 7)}</code>
      </a>
      <code :if={!@cache[@hash]}>{String.slice(@hash, 0, 7)}</code>
    </span>
    """
  end

  defp load_tree(socket) do
    project_id = socket.assigns.selected_project_id

    if project_id && socket.assigns.dolt_available do
      Tracer.with_span "spotter.product_live.load_tree" do
        Tracer.set_attribute("spotter.project_id", project_id)

        tree =
          try do
            ProductSpec.tree(project_id)
          rescue
            e ->
              Tracer.set_status(:error, Exception.message(e))
              []
          end

        commit_hashes =
          tree
          |> collect_commit_hashes()
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        cache = build_commit_cache(commit_hashes)

        assign(socket, tree: tree, commit_id_cache: cache)
      end
    else
      assign(socket, tree: [], commit_id_cache: %{})
    end
  end

  defp collect_commit_hashes(tree) do
    Enum.flat_map(tree, fn domain ->
      [domain.updated_by_git_commit] ++
        Enum.flat_map(domain.features, fn feature ->
          [feature.updated_by_git_commit] ++
            Enum.map(feature.requirements, & &1.updated_by_git_commit)
        end)
    end)
  end

  defp build_commit_cache([]), do: %{}

  defp build_commit_cache(hashes) do
    case Commit |> Ash.Query.filter(commit_hash in ^hashes) |> Ash.read() do
      {:ok, commits} -> Map.new(commits, &{&1.commit_hash, &1.id})
      _ -> %{}
    end
  end

  defp filtered_tree(tree, ""), do: tree

  defp filtered_tree(tree, q) do
    q = String.downcase(q)

    tree
    |> Enum.map(&filter_domain(&1, q))
    |> Enum.filter(fn domain ->
      domain.features != [] ||
        matches?(domain.name, q) ||
        matches?(domain.spec_key, q)
    end)
  end

  defp filter_domain(domain, q) do
    features =
      domain.features
      |> Enum.map(&filter_feature(&1, q))
      |> Enum.filter(fn feature ->
        feature.requirements != [] ||
          matches?(feature.name, q) ||
          matches?(feature.spec_key, q) ||
          matches?(feature.description, q)
      end)

    %{domain | features: features}
  end

  defp filter_feature(feature, q) do
    reqs =
      Enum.filter(feature.requirements, fn req ->
        matches?(req.spec_key, q) ||
          matches?(req.statement, q) ||
          matches?(req.rationale, q)
      end)

    %{feature | requirements: reqs}
  end

  defp matches?(nil, _q), do: false
  defp matches?(text, q), do: text |> String.downcase() |> String.contains?(q)

  defp dolt_available? do
    case Process.whereis(Spotter.ProductSpec.Repo) do
      nil -> false
      _pid -> true
    end
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id
end
