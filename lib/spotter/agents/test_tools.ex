defmodule Spotter.Agents.TestTools do
  @moduledoc """
  In-process MCP tools for syncing test cases per file.

  Defines CRUD tools that the Claude Agent SDK agent uses to keep
  Spotter's stored tests in sync with actual test files.
  """

  use ClaudeAgentSDK.Tool

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Transcripts.TestCase

  # ── List ──

  deftool :list_tests,
          "List all stored tests for a given project and file path",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"}
            },
            required: ["project_id", "relative_path"]
          },
          annotations: %{readOnlyHint: true} do
    require Ash.Query
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools.Helpers

    def execute(%{"project_id" => project_id, "relative_path" => relative_path}) do
      Tracer.with_span "spotter.commit_tests.tool.list_tests" do
        Tracer.set_attribute("spotter.project_id", project_id)
        Tracer.set_attribute("spotter.relative_path", relative_path)

        tests =
          TestCase
          |> Ash.Query.filter(project_id == ^project_id and relative_path == ^relative_path)
          |> Ash.Query.sort(
            describe_path: :asc,
            test_name: :asc,
            line_start: :asc,
            framework: :asc
          )
          |> Ash.read!()
          |> Enum.map(&Helpers.serialize_test/1)

        Helpers.ok_result(%{tests: tests})
      end
    end
  end

  # ── Create ──

  deftool :create_test,
          "Create a new test case record for a file",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"},
              framework: %{type: "string", description: "Test framework (e.g. ExUnit, Jest)"},
              describe_path: %{
                type: "array",
                items: %{type: "string"},
                description: "Nesting path of describe blocks"
              },
              test_name: %{type: "string", description: "Test name"},
              line_start: %{type: "integer", description: "Start line number"},
              line_end: %{type: "integer", description: "End line number"},
              given: %{
                type: "array",
                items: %{type: "string"},
                description: "Given preconditions"
              },
              when: %{type: "array", items: %{type: "string"}, description: "When actions"},
              then: %{type: "array", items: %{type: "string"}, description: "Then assertions"},
              confidence: %{type: "number", description: "Extraction confidence 0.0-1.0"},
              metadata: %{type: "object", description: "Arbitrary metadata"},
              source_commit_hash: %{
                type: "string",
                description: "Git commit hash that introduced this test"
              }
            },
            required: ["project_id", "relative_path", "framework", "test_name"]
          } do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools.Helpers

    def execute(%{"project_id" => project_id, "relative_path" => relative_path} = input) do
      Tracer.with_span "spotter.commit_tests.tool.create_test" do
        Tracer.set_attribute("spotter.project_id", project_id)
        Tracer.set_attribute("spotter.relative_path", relative_path)

        source_commit_id = Helpers.resolve_commit_id(input["source_commit_hash"])

        attrs =
          %{
            project_id: project_id,
            relative_path: relative_path,
            framework: input["framework"],
            describe_path: input["describe_path"] || [],
            test_name: input["test_name"],
            line_start: input["line_start"],
            line_end: input["line_end"],
            given: input["given"] || [],
            when: input["when"] || [],
            then: input["then"] || [],
            confidence: input["confidence"],
            metadata: input["metadata"] || %{},
            source_commit_id: source_commit_id
          }

        case Ash.create(TestCase, attrs) do
          {:ok, test} ->
            Helpers.ok_result(%{test: Helpers.serialize_test(test)})

          {:error, error} ->
            {:error, Helpers.format_error(error)}
        end
      end
    end
  end

  # ── Update ──

  deftool :update_test,
          "Update an existing test case record",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"},
              test_id: %{type: "string", description: "Test case UUID"},
              patch: %{
                type: "object",
                description:
                  "Fields to update: framework, describe_path, test_name, line_start, line_end, given, when, then, confidence, metadata, source_commit_hash"
              }
            },
            required: ["project_id", "relative_path", "test_id", "patch"]
          } do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools.Helpers

    def execute(%{
          "project_id" => project_id,
          "relative_path" => relative_path,
          "test_id" => test_id,
          "patch" => patch
        }) do
      Tracer.with_span "spotter.commit_tests.tool.update_test" do
        Tracer.set_attribute("spotter.project_id", project_id)
        Tracer.set_attribute("spotter.relative_path", relative_path)
        Tracer.set_attribute("spotter.test_id", test_id)

        with {:ok, test} <- Helpers.load_and_verify(test_id, project_id, relative_path),
             attrs <- Helpers.build_update_attrs(patch),
             {:ok, updated} <- Ash.update(test, attrs) do
          Helpers.ok_result(%{test: Helpers.serialize_test(updated)})
        else
          {:error, error} -> {:error, Helpers.format_error(error)}
        end
      end
    end
  end

  # ── Delete ──

  deftool :delete_test,
          "Delete a test case record",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"},
              test_id: %{type: "string", description: "Test case UUID"}
            },
            required: ["project_id", "relative_path", "test_id"]
          },
          annotations: %{destructiveHint: true} do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools.Helpers

    def execute(%{
          "project_id" => project_id,
          "relative_path" => relative_path,
          "test_id" => test_id
        }) do
      Tracer.with_span "spotter.commit_tests.tool.delete_test" do
        Tracer.set_attribute("spotter.project_id", project_id)
        Tracer.set_attribute("spotter.relative_path", relative_path)
        Tracer.set_attribute("spotter.test_id", test_id)

        with {:ok, test} <- Helpers.load_and_verify(test_id, project_id, relative_path) do
          case Ash.destroy(test) do
            :ok ->
              Helpers.ok_result(%{ok: true})

            {:error, error} ->
              {:error, Helpers.format_error(error)}
          end
        end
      end
    end
  end

  @doc "Returns all tool modules for MCP server registration."
  def all_tool_modules do
    __MODULE__
    |> ClaudeAgentSDK.Tool.list_tools()
    |> Enum.map(& &1.module)
  end
end

defmodule Spotter.Agents.TestTools.Helpers do
  @moduledoc false

  require Ash.Query

  alias Spotter.Transcripts.{Commit, TestCase}

  @update_keys ~w(framework describe_path test_name line_start line_end given when then confidence metadata)

  @doc "Build update attrs from a patch map, resolving source_commit_hash."
  def build_update_attrs(patch) do
    source_commit_id = resolve_commit_id(patch["source_commit_hash"])

    attrs =
      patch
      |> Map.take(@update_keys)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()

    if source_commit_id, do: Map.put(attrs, :source_commit_id, source_commit_id), else: attrs
  end

  @doc "Serialize a TestCase to a plain map for JSON output."
  def serialize_test(%TestCase{} = tc) do
    %{
      id: tc.id,
      project_id: tc.project_id,
      relative_path: tc.relative_path,
      framework: tc.framework,
      describe_path: tc.describe_path,
      test_name: tc.test_name,
      line_start: tc.line_start,
      line_end: tc.line_end,
      given: tc.given,
      when: tc.when,
      then: tc.then,
      confidence: tc.confidence,
      metadata: tc.metadata,
      source_commit_id: tc.source_commit_id
    }
  end

  @doc "Wrap a result map as an MCP text content block."
  def ok_result(data) do
    {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}}
  end

  @doc "Resolve a commit hash to an ID, returning nil if not found."
  def resolve_commit_id(nil), do: nil
  def resolve_commit_id(""), do: nil

  def resolve_commit_id(hash) do
    case Commit
         |> Ash.Query.filter(commit_hash == ^hash)
         |> Ash.read_one() do
      {:ok, %Commit{id: id}} -> id
      _ -> nil
    end
  end

  @doc "Load a test case and verify it belongs to the expected project+file."
  def load_and_verify(test_id, project_id, relative_path) do
    case Ash.get(TestCase, test_id) do
      {:ok, test} ->
        if test.project_id == project_id and test.relative_path == relative_path do
          {:ok, test}
        else
          {:error, "test_not_in_file"}
        end

      {:error, _} ->
        {:error, "test_not_found"}
    end
  end

  @doc "Format an Ash error into a string."
  def format_error(%{errors: errors}) when is_list(errors) do
    Enum.map_join(errors, "; ", &Exception.message/1)
  end

  def format_error(error) when is_binary(error), do: error
  def format_error(error), do: inspect(error)
end
