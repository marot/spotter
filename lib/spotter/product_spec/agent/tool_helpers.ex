defmodule Spotter.ProductSpec.Agent.ToolHelpers do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Spotter.ProductSpec.Repo

  @spec_key_re ~r/^[a-z0-9][a-z0-9-]{2,159}$/

  @doc "Sets the git commit hash used by write tools for `updated_by_git_commit`."
  @spec set_commit_hash(String.t()) :: :ok
  def set_commit_hash(hash) do
    Process.put(:spec_agent_commit_hash, hash)
    :ok
  end

  def commit_hash, do: Process.get(:spec_agent_commit_hash, "")

  def text_result(data) do
    {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}}
  end

  def validate_spec_key(key) do
    if Regex.match?(@spec_key_re, key),
      do: :ok,
      else: {:error, "spec_key must match ^[a-z0-9][a-z0-9-]{2,159}$"}
  end

  def maybe_validate_spec_key(nil), do: :ok
  def maybe_validate_spec_key(key), do: validate_spec_key(key)

  def validate_shall(statement) do
    if statement =~ ~r/shall/i,
      do: :ok,
      else: {:error, "statement must include 'shall'"}
  end

  def maybe_validate_shall(nil), do: :ok
  def maybe_validate_shall(statement), do: validate_shall(statement)

  def rows_to_maps(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns |> Enum.zip(row) |> Map.new()
    end)
  end

  def build_update_sets(input, fields) do
    Enum.reduce(fields, {[], []}, fn field, {sets, params} ->
      case input[field] do
        nil -> {sets, params}
        value -> {sets ++ ["#{field} = ?"], params ++ [value]}
      end
    end)
  end

  def dolt_query!(sql, params \\ []) do
    SQL.query!(Repo, sql, params)
  end
end
