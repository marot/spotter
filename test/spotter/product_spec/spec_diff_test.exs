defmodule Spotter.ProductSpec.SpecDiffTest do
  use ExUnit.Case, async: true

  alias Spotter.ProductSpec.SpecDiff

  defp make_req(spec_key, opts \\ []) do
    %{
      spec_key: spec_key,
      statement: opts[:statement] || "stmt-#{spec_key}",
      rationale: opts[:rationale] || "rat-#{spec_key}",
      acceptance_criteria: opts[:acceptance_criteria] || "ac-#{spec_key}",
      priority: opts[:priority] || "P2"
    }
  end

  defp make_feature(spec_key, reqs, opts \\ []) do
    %{
      spec_key: spec_key,
      name: opts[:name] || "Feature #{spec_key}",
      description: opts[:description] || "desc-#{spec_key}",
      requirements: reqs
    }
  end

  defp make_domain(spec_key, features, opts \\ []) do
    %{
      spec_key: spec_key,
      name: opts[:name] || "Domain #{spec_key}",
      description: opts[:description] || "desc-#{spec_key}",
      features: features
    }
  end

  describe "diff/2" do
    test "detects added domain, feature, and requirement" do
      from_tree = []

      to_tree = [
        make_domain("d1", [
          make_feature("f1", [make_req("r1")])
        ])
      ]

      result = SpecDiff.diff(from_tree, to_tree)

      assert length(result.added) == 3
      assert result.removed == []
      assert result.changed == []

      levels = Enum.map(result.added, & &1.level) |> Enum.sort()
      assert levels == [:domain, :feature, :requirement]
    end

    test "detects removed domain, feature, and requirement" do
      from_tree = [
        make_domain("d1", [
          make_feature("f1", [make_req("r1")])
        ])
      ]

      to_tree = []

      result = SpecDiff.diff(from_tree, to_tree)

      assert result.added == []
      assert length(result.removed) == 3
      assert result.changed == []

      levels = Enum.map(result.removed, & &1.level) |> Enum.sort()
      assert levels == [:domain, :feature, :requirement]
    end

    test "detects changed fields on domain, feature, and requirement" do
      from_tree = [
        make_domain(
          "d1",
          [
            make_feature("f1", [make_req("r1", statement: "old stmt")])
          ],
          name: "Old Domain"
        )
      ]

      to_tree = [
        make_domain(
          "d1",
          [
            make_feature("f1", [make_req("r1", statement: "new stmt")], name: "New Feature")
          ],
          name: "New Domain"
        )
      ]

      result = SpecDiff.diff(from_tree, to_tree)

      assert result.added == []
      assert result.removed == []
      assert length(result.changed) == 3

      domain_change = Enum.find(result.changed, &(&1.level == :domain))
      assert domain_change.before.name == "Old Domain"
      assert domain_change.after.name == "New Domain"
      assert :name in domain_change.changed_fields

      feature_change = Enum.find(result.changed, &(&1.level == :feature))
      assert feature_change.before.name == "Feature f1"
      assert feature_change.after.name == "New Feature"

      req_change = Enum.find(result.changed, &(&1.level == :requirement))
      assert req_change.before.statement == "old stmt"
      assert req_change.after.statement == "new stmt"
      assert :statement in req_change.changed_fields
    end

    test "empty baseline treats everything as added" do
      to_tree = [
        make_domain("d1", [make_feature("f1", [])]),
        make_domain("d2", [])
      ]

      result = SpecDiff.diff([], to_tree)

      assert length(result.added) == 3
      assert result.removed == []
      assert result.changed == []
    end

    test "identical trees produce empty diff" do
      tree = [
        make_domain("d1", [
          make_feature("f1", [make_req("r1")])
        ])
      ]

      result = SpecDiff.diff(tree, tree)

      assert result.added == []
      assert result.removed == []
      assert result.changed == []
    end
  end
end
