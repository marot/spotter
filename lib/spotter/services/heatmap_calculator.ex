defmodule Spotter.Services.HeatmapCalculator do
  @moduledoc "Computes file change frequency and heat scores from FileSnapshot data + git history."

  require Logger
  require Ash.Query

  alias Spotter.Services.GitLogReader
  alias Spotter.Transcripts.{FileHeatmap, FileSnapshot, Session}

  @binary_extensions ~w(.png .jpg .jpeg .gif .bmp .ico .svg .webp .woff .woff2 .ttf .eot .otf
    .pdf .zip .tar .gz .bz2 .7z .exe .dll .so .dylib .o .beam .ez .pyc .class .jar)

  @doc """
  Compute heatmap data for a project.

  Options:
    - :window_days - rolling window in days (default 30)
    - :reference_date - for deterministic tests (default DateTime.utc_now())
  """
  @spec compute(String.t(), keyword()) :: :ok | {:error, term()}
  def compute(project_id, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, 30)
    reference_date = Keyword.get(opts, :reference_date, DateTime.utc_now())
    since = DateTime.add(reference_date, -window_days * 86_400, :second)

    snapshot_data = load_snapshot_data(project_id, since)
    git_data = load_git_data(project_id, window_days)

    file_map = merge_data(snapshot_data, git_data)

    upsert_heatmaps(project_id, file_map, reference_date)
    delete_stale_rows(project_id, file_map)

    :ok
  end

  defp load_snapshot_data(project_id, since) do
    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.read!()

    session_ids = Enum.map(sessions, & &1.id)

    if session_ids == [] do
      []
    else
      FileSnapshot
      |> Ash.Query.filter(session_id in ^session_ids and timestamp >= ^since)
      |> Ash.read!()
    end
  end

  defp load_git_data(project_id, window_days) do
    case resolve_repo_path(project_id) do
      {:ok, repo_path} ->
        case GitLogReader.changed_files_by_commit(repo_path, since_days: window_days) do
          {:ok, commits} -> commits
          {:error, _} -> []
        end

      :skip ->
        []
    end
  end

  defp resolve_repo_path(project_id) do
    case Session
         |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [session] ->
        if File.dir?(session.cwd) do
          {:ok, session.cwd}
        else
          Logger.warning("HeatmapCalculator: cwd #{session.cwd} not accessible, skipping git")
          :skip
        end

      [] ->
        Logger.warning("HeatmapCalculator: no sessions with cwd for project #{project_id}")
        :skip
    end
  end

  defp merge_data(snapshots, git_commits) do
    snapshot_entries =
      Enum.map(snapshots, fn snap ->
        path = snap.relative_path || snap.file_path
        {path, snap.timestamp}
      end)

    git_entries =
      Enum.flat_map(git_commits, fn commit ->
        Enum.map(commit.files, fn file -> {file, commit.timestamp} end)
      end)

    (snapshot_entries ++ git_entries)
    |> Enum.reject(fn {path, _} -> binary_file?(path) end)
    |> Enum.group_by(fn {path, _} -> path end, fn {_, ts} -> ts end)
    |> Map.new(fn {path, timestamps} ->
      {path,
       %{
         change_count: length(timestamps),
         last_changed_at: Enum.max(timestamps, DateTime)
       }}
    end)
  end

  defp binary_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in @binary_extensions
  end

  defp upsert_heatmaps(project_id, file_map, reference_date) do
    Enum.each(file_map, fn {path, data} ->
      heat_score = calculate_heat_score(data.change_count, data.last_changed_at, reference_date)

      Ash.create!(FileHeatmap, %{
        project_id: project_id,
        relative_path: path,
        change_count_30d: data.change_count,
        heat_score: heat_score,
        last_changed_at: data.last_changed_at
      })
    end)
  end

  defp delete_stale_rows(project_id, file_map) do
    current_paths = Map.keys(file_map)

    existing =
      FileHeatmap
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.read!()

    stale = Enum.filter(existing, fn row -> row.relative_path not in current_paths end)
    Enum.each(stale, &Ash.destroy!/1)
  end

  @doc """
  Calculate heat score from change count and recency.

  Formula:
    frequency_norm = min(log1p(change_count) / log(21), 1.0)
    recency_norm = exp(-days_since / 14)
    heat_score = (0.65 * frequency_norm + 0.35 * recency_norm) * 100
  """
  @spec calculate_heat_score(non_neg_integer(), DateTime.t(), DateTime.t()) :: float()
  def calculate_heat_score(change_count, last_changed_at, reference_date) do
    days_since = max(DateTime.diff(reference_date, last_changed_at, :second) / 86_400, 0)
    frequency_norm = min(:math.log(1 + change_count) / :math.log(21), 1.0)
    recency_norm = :math.exp(-days_since / 14)

    Float.round((0.65 * frequency_norm + 0.35 * recency_norm) * 100, 2)
  end
end
