defmodule Spotter.ProductSpec.Agent.Tools do
  @moduledoc """
  In-process MCP tools for the product specification agent.

  Defines 11 tools (domains CRUD, features CRUD+search+delete,
  requirements CRUD+search+delete) that execute SQL directly against the
  Dolt-backed `ProductSpec.Repo`.

  The current commit hash is stored in the process dictionary before the
  agent run starts (see `ToolHelpers.set_commit_hash/1`).
  """

  use ClaudeAgentSDK.Tool

  alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

  # ── Domains ──

  deftool :domains_list,
          "List all product domains for a project",
          ClaudeAgentSDK.Tool.simple_schema(project_id: :string),
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id}) do
      result =
        H.dolt_query!(
          """
          SELECT id, project_id, spec_key, name, description, updated_by_git_commit
          FROM product_domains WHERE project_id = ? ORDER BY name
          """,
          [project_id]
        )

      H.text_result(%{domains: H.rows_to_maps(result)})
    end
  end

  deftool :domains_create,
          "Create or upsert a product domain by (project_id, spec_key)",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              spec_key: %{type: "string", description: "Unique domain key (lowercase, hyphens)"},
              name: %{type: "string", description: "Human-readable domain name"},
              description: %{type: "string", description: "Domain description"}
            },
            required: ["project_id", "spec_key", "name"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "spec_key" => spec_key, "name" => name} = input) do
      case H.validate_spec_key(spec_key) do
        :ok ->
          id = Ash.UUID.generate()

          H.dolt_query!(
            """
            INSERT INTO product_domains (id, project_id, spec_key, name, description, updated_by_git_commit)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description),
              updated_by_git_commit = VALUES(updated_by_git_commit)
            """,
            [id, project_id, spec_key, name, input["description"], H.commit_hash()]
          )

          H.text_result(%{ok: true, spec_key: spec_key})

        {:error, msg} ->
          H.text_result(%{error: msg})
      end
    end
  end

  deftool :domains_update,
          "Update an existing product domain",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              domain_id: %{type: "string", description: "Domain UUID"},
              spec_key: %{type: "string", description: "New spec_key"},
              name: %{type: "string", description: "New name"},
              description: %{type: "string", description: "New description"}
            },
            required: ["project_id", "domain_id"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "domain_id" => domain_id} = input) do
      case H.maybe_validate_spec_key(input["spec_key"]) do
        :ok ->
          {sets, params} = H.build_update_sets(input, ["spec_key", "name", "description"])

          if sets == [] do
            H.text_result(%{error: "no fields to update"})
          else
            sets = sets ++ ["updated_by_git_commit = ?"]
            params = params ++ [H.commit_hash(), project_id, domain_id]

            H.dolt_query!(
              "UPDATE product_domains SET #{Enum.join(sets, ", ")} WHERE project_id = ? AND id = ?",
              params
            )

            H.text_result(%{ok: true})
          end

        {:error, msg} ->
          H.text_result(%{error: msg})
      end
    end
  end

  # ── Features ──

  deftool :features_search,
          "Search product features by domain and/or text query",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              domain_id: %{type: "string", description: "Filter by domain UUID"},
              q: %{
                type: "string",
                description: "Substring search on spec_key, name, or description"
              }
            },
            required: ["project_id"]
          },
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id} = input) do
      {where, params} = {["project_id = ?"], [project_id]}

      {where, params} =
        if input["domain_id"] do
          {where ++ ["domain_id = ?"], params ++ [input["domain_id"]]}
        else
          {where, params}
        end

      {where, params} =
        if input["q"] do
          like = "%#{input["q"]}%"

          {where ++ ["(spec_key LIKE ? OR name LIKE ? OR description LIKE ?)"],
           params ++ [like, like, like]}
        else
          {where, params}
        end

      result =
        H.dolt_query!(
          """
          SELECT id, project_id, domain_id, spec_key, name, description, updated_by_git_commit
          FROM product_features WHERE #{Enum.join(where, " AND ")} ORDER BY name
          """,
          params
        )

      H.text_result(%{features: H.rows_to_maps(result)})
    end
  end

  deftool :features_create,
          "Create or upsert a product feature by (project_id, domain_id, spec_key)",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              domain_id: %{type: "string", description: "Parent domain UUID"},
              spec_key: %{type: "string", description: "Unique feature key within domain"},
              name: %{type: "string", description: "Human-readable feature name"},
              description: %{type: "string", description: "Feature description"}
            },
            required: ["project_id", "domain_id", "spec_key", "name"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(
          %{"project_id" => pid, "domain_id" => did, "spec_key" => sk, "name" => name} = input
        ) do
      case H.validate_spec_key(sk) do
        :ok ->
          id = Ash.UUID.generate()

          H.dolt_query!(
            """
            INSERT INTO product_features (id, project_id, domain_id, spec_key, name, description, updated_by_git_commit)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description),
              updated_by_git_commit = VALUES(updated_by_git_commit)
            """,
            [id, pid, did, sk, name, input["description"], H.commit_hash()]
          )

          H.text_result(%{ok: true, spec_key: sk})

        {:error, msg} ->
          H.text_result(%{error: msg})
      end
    end
  end

  deftool :features_update,
          "Update an existing product feature",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              feature_id: %{type: "string", description: "Feature UUID"},
              domain_id: %{type: "string", description: "New parent domain UUID"},
              spec_key: %{type: "string", description: "New spec_key"},
              name: %{type: "string", description: "New name"},
              description: %{type: "string", description: "New description"}
            },
            required: ["project_id", "feature_id"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "feature_id" => feature_id} = input) do
      case H.maybe_validate_spec_key(input["spec_key"]) do
        :ok ->
          {sets, params} =
            H.build_update_sets(input, ["domain_id", "spec_key", "name", "description"])

          if sets == [] do
            H.text_result(%{error: "no fields to update"})
          else
            sets = sets ++ ["updated_by_git_commit = ?"]
            params = params ++ [H.commit_hash(), project_id, feature_id]

            H.dolt_query!(
              "UPDATE product_features SET #{Enum.join(sets, ", ")} WHERE project_id = ? AND id = ?",
              params
            )

            H.text_result(%{ok: true})
          end

        {:error, msg} ->
          H.text_result(%{error: msg})
      end
    end
  end

  deftool :features_delete,
          "Delete a product feature and its requirements",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              feature_id: %{type: "string", description: "Feature UUID to delete"}
            },
            required: ["project_id", "feature_id"]
          },
          annotations: %{destructiveHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "feature_id" => feature_id}) do
      H.dolt_query!(
        "DELETE FROM product_requirements WHERE project_id = ? AND feature_id = ?",
        [project_id, feature_id]
      )

      H.dolt_query!(
        "DELETE FROM product_features WHERE project_id = ? AND id = ?",
        [project_id, feature_id]
      )

      H.text_result(%{ok: true})
    end
  end

  # ── Requirements ──

  deftool :requirements_search,
          "Search product requirements by feature and/or text query",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              feature_id: %{type: "string", description: "Filter by feature UUID"},
              q: %{
                type: "string",
                description: "Substring search on spec_key, statement, or rationale"
              }
            },
            required: ["project_id"]
          },
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id} = input) do
      {where, params} = {["project_id = ?"], [project_id]}

      {where, params} =
        if input["feature_id"] do
          {where ++ ["feature_id = ?"], params ++ [input["feature_id"]]}
        else
          {where, params}
        end

      {where, params} =
        if input["q"] do
          like = "%#{input["q"]}%"

          {where ++ ["(spec_key LIKE ? OR statement LIKE ? OR rationale LIKE ?)"],
           params ++ [like, like, like]}
        else
          {where, params}
        end

      result =
        H.dolt_query!(
          """
          SELECT id, project_id, feature_id, spec_key, statement, rationale,
                 acceptance_criteria, priority, updated_by_git_commit
          FROM product_requirements WHERE #{Enum.join(where, " AND ")} ORDER BY spec_key
          """,
          params
        )

      H.text_result(%{requirements: H.rows_to_maps(result)})
    end
  end

  deftool :requirements_create,
          "Create or upsert a product requirement by (project_id, feature_id, spec_key)",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              feature_id: %{type: "string", description: "Parent feature UUID"},
              spec_key: %{type: "string", description: "Unique requirement key within feature"},
              statement: %{
                type: "string",
                description: "Requirement statement (must include 'shall')"
              },
              rationale: %{type: "string", description: "Why this requirement exists"},
              acceptance_criteria: %{
                type: "array",
                items: %{type: "string"},
                description: "List of acceptance criteria"
              },
              priority: %{type: "string", description: "Priority level"}
            },
            required: ["project_id", "feature_id", "spec_key", "statement"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(
          %{
            "project_id" => pid,
            "feature_id" => fid,
            "spec_key" => sk,
            "statement" => statement
          } = input
        ) do
      with :ok <- H.validate_spec_key(sk),
           :ok <- H.validate_shall(statement) do
        id = Ash.UUID.generate()
        ac_json = if input["acceptance_criteria"], do: Jason.encode!(input["acceptance_criteria"])

        H.dolt_query!(
          """
          INSERT INTO product_requirements
            (id, project_id, feature_id, spec_key, statement, rationale, acceptance_criteria, priority, updated_by_git_commit)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE statement = VALUES(statement), rationale = VALUES(rationale),
            acceptance_criteria = VALUES(acceptance_criteria), priority = VALUES(priority),
            updated_by_git_commit = VALUES(updated_by_git_commit)
          """,
          [
            id,
            pid,
            fid,
            sk,
            statement,
            input["rationale"],
            ac_json,
            input["priority"],
            H.commit_hash()
          ]
        )

        H.text_result(%{ok: true, spec_key: sk})
      else
        {:error, msg} -> H.text_result(%{error: msg})
      end
    end
  end

  deftool :requirements_update,
          "Update an existing product requirement",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              requirement_id: %{type: "string", description: "Requirement UUID"},
              spec_key: %{type: "string", description: "New spec_key"},
              statement: %{type: "string", description: "New statement (must include 'shall')"},
              rationale: %{type: "string", description: "New rationale"},
              acceptance_criteria: %{
                type: "array",
                items: %{type: "string"},
                description: "New acceptance criteria"
              },
              priority: %{type: "string", description: "New priority"}
            },
            required: ["project_id", "requirement_id"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "requirement_id" => requirement_id} = input) do
      with :ok <- H.maybe_validate_spec_key(input["spec_key"]),
           :ok <- H.maybe_validate_shall(input["statement"]) do
        {sets, params} =
          H.build_update_sets(input, ["spec_key", "statement", "rationale", "priority"])

        {sets, params} =
          if input["acceptance_criteria"] do
            {sets ++ ["acceptance_criteria = ?"],
             params ++ [Jason.encode!(input["acceptance_criteria"])]}
          else
            {sets, params}
          end

        if sets == [] do
          H.text_result(%{error: "no fields to update"})
        else
          sets = sets ++ ["updated_by_git_commit = ?"]
          params = params ++ [H.commit_hash(), project_id, requirement_id]

          H.dolt_query!(
            "UPDATE product_requirements SET #{Enum.join(sets, ", ")} WHERE project_id = ? AND id = ?",
            params
          )

          H.text_result(%{ok: true})
        end
      else
        {:error, msg} -> H.text_result(%{error: msg})
      end
    end
  end

  deftool :requirements_delete,
          "Delete a product requirement",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              requirement_id: %{type: "string", description: "Requirement UUID to delete"}
            },
            required: ["project_id", "requirement_id"]
          },
          annotations: %{destructiveHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "requirement_id" => requirement_id}) do
      H.dolt_query!(
        "DELETE FROM product_requirements WHERE project_id = ? AND id = ?",
        [project_id, requirement_id]
      )

      H.text_result(%{ok: true})
    end
  end

  @doc "Returns all tool modules for MCP server registration."
  def all_tool_modules do
    __MODULE__
    |> ClaudeAgentSDK.Tool.list_tools()
    |> Enum.map(& &1.module)
  end
end
