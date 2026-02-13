import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import * as crypto from "crypto";
import * as dolt from "./dolt.js";

// Shared state: commit_hash is set at startup and used by all write tools
let currentCommitHash = "";

export function setCommitHash(hash: string): void {
  currentCommitHash = hash;
}

const SPEC_KEY_RE = /^[a-z0-9][a-z0-9-]{2,159}$/;

function validateSpecKey(key: string): string | null {
  if (!SPEC_KEY_RE.test(key)) {
    return "spec_key must match ^[a-z0-9][a-z0-9-]{2,159}$";
  }
  return null;
}

function textResult(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

// ── Domains ──

export const domainsList = tool(
  "domains_list",
  "List all product domains for a project",
  { project_id: z.string().describe("Project UUID") },
  async (args) => {
    const rows = await dolt.query(
      "SELECT id, project_id, spec_key, name, description, updated_by_git_commit FROM product_domains WHERE project_id = ? ORDER BY name",
      [args.project_id],
    );
    return textResult(JSON.stringify({ domains: rows }));
  },
);

export const domainsCreate = tool(
  "domains_create",
  "Create or upsert a product domain by (project_id, spec_key)",
  {
    project_id: z.string().describe("Project UUID"),
    spec_key: z.string().describe("Unique domain key (lowercase, hyphens)"),
    name: z.string().describe("Human-readable domain name"),
    description: z.string().optional().describe("Domain description"),
  },
  async (args) => {
    const keyErr = validateSpecKey(args.spec_key);
    if (keyErr) return textResult(JSON.stringify({ error: keyErr }));

    const id = crypto.randomUUID();
    await dolt.execute(
      `INSERT INTO product_domains (id, project_id, spec_key, name, description, updated_by_git_commit)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description), updated_by_git_commit = VALUES(updated_by_git_commit)`,
      [id, args.project_id, args.spec_key, args.name, args.description ?? null, currentCommitHash],
    );
    return textResult(JSON.stringify({ ok: true, spec_key: args.spec_key }));
  },
);

export const domainsUpdate = tool(
  "domains_update",
  "Update an existing product domain",
  {
    project_id: z.string().describe("Project UUID"),
    domain_id: z.string().describe("Domain UUID"),
    spec_key: z.string().optional().describe("New spec_key"),
    name: z.string().optional().describe("New name"),
    description: z.string().optional().describe("New description"),
  },
  async (args) => {
    if (args.spec_key) {
      const keyErr = validateSpecKey(args.spec_key);
      if (keyErr) return textResult(JSON.stringify({ error: keyErr }));
    }

    const sets: string[] = [];
    const params: unknown[] = [];

    if (args.spec_key !== undefined) { sets.push("spec_key = ?"); params.push(args.spec_key); }
    if (args.name !== undefined) { sets.push("name = ?"); params.push(args.name); }
    if (args.description !== undefined) { sets.push("description = ?"); params.push(args.description); }

    if (sets.length === 0) return textResult(JSON.stringify({ error: "no fields to update" }));

    sets.push("updated_by_git_commit = ?");
    params.push(currentCommitHash);
    params.push(args.project_id, args.domain_id);

    await dolt.execute(
      `UPDATE product_domains SET ${sets.join(", ")} WHERE project_id = ? AND id = ?`,
      params,
    );
    return textResult(JSON.stringify({ ok: true }));
  },
);

// ── Features ──

export const featuresSearch = tool(
  "features_search",
  "Search product features by domain and/or text query",
  {
    project_id: z.string().describe("Project UUID"),
    domain_id: z.string().optional().describe("Filter by domain UUID"),
    q: z.string().optional().describe("Substring search on spec_key, name, or description"),
  },
  async (args) => {
    let sql = "SELECT id, project_id, domain_id, spec_key, name, description, updated_by_git_commit FROM product_features WHERE project_id = ?";
    const params: unknown[] = [args.project_id];

    if (args.domain_id) {
      sql += " AND domain_id = ?";
      params.push(args.domain_id);
    }
    if (args.q) {
      sql += " AND (spec_key LIKE ? OR name LIKE ? OR description LIKE ?)";
      const like = `%${args.q}%`;
      params.push(like, like, like);
    }
    sql += " ORDER BY name";

    const rows = await dolt.query(sql, params);
    return textResult(JSON.stringify({ features: rows }));
  },
);

export const featuresCreate = tool(
  "features_create",
  "Create or upsert a product feature by (project_id, domain_id, spec_key)",
  {
    project_id: z.string().describe("Project UUID"),
    domain_id: z.string().describe("Parent domain UUID"),
    spec_key: z.string().describe("Unique feature key within domain"),
    name: z.string().describe("Human-readable feature name"),
    description: z.string().optional().describe("Feature description"),
  },
  async (args) => {
    const keyErr = validateSpecKey(args.spec_key);
    if (keyErr) return textResult(JSON.stringify({ error: keyErr }));

    const id = crypto.randomUUID();
    await dolt.execute(
      `INSERT INTO product_features (id, project_id, domain_id, spec_key, name, description, updated_by_git_commit)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description), updated_by_git_commit = VALUES(updated_by_git_commit)`,
      [id, args.project_id, args.domain_id, args.spec_key, args.name, args.description ?? null, currentCommitHash],
    );
    return textResult(JSON.stringify({ ok: true, spec_key: args.spec_key }));
  },
);

export const featuresUpdate = tool(
  "features_update",
  "Update an existing product feature",
  {
    project_id: z.string().describe("Project UUID"),
    feature_id: z.string().describe("Feature UUID"),
    domain_id: z.string().optional().describe("New parent domain UUID"),
    spec_key: z.string().optional().describe("New spec_key"),
    name: z.string().optional().describe("New name"),
    description: z.string().optional().describe("New description"),
  },
  async (args) => {
    if (args.spec_key) {
      const keyErr = validateSpecKey(args.spec_key);
      if (keyErr) return textResult(JSON.stringify({ error: keyErr }));
    }

    const sets: string[] = [];
    const params: unknown[] = [];

    if (args.domain_id !== undefined) { sets.push("domain_id = ?"); params.push(args.domain_id); }
    if (args.spec_key !== undefined) { sets.push("spec_key = ?"); params.push(args.spec_key); }
    if (args.name !== undefined) { sets.push("name = ?"); params.push(args.name); }
    if (args.description !== undefined) { sets.push("description = ?"); params.push(args.description); }

    if (sets.length === 0) return textResult(JSON.stringify({ error: "no fields to update" }));

    sets.push("updated_by_git_commit = ?");
    params.push(currentCommitHash);
    params.push(args.project_id, args.feature_id);

    await dolt.execute(
      `UPDATE product_features SET ${sets.join(", ")} WHERE project_id = ? AND id = ?`,
      params,
    );
    return textResult(JSON.stringify({ ok: true }));
  },
);

export const featuresDelete = tool(
  "features_delete",
  "Delete a product feature and its requirements",
  {
    project_id: z.string().describe("Project UUID"),
    feature_id: z.string().describe("Feature UUID to delete"),
  },
  async (args) => {
    await dolt.execute(
      "DELETE FROM product_requirements WHERE project_id = ? AND feature_id = ?",
      [args.project_id, args.feature_id],
    );
    await dolt.execute(
      "DELETE FROM product_features WHERE project_id = ? AND id = ?",
      [args.project_id, args.feature_id],
    );
    return textResult(JSON.stringify({ ok: true }));
  },
);

// ── Requirements ──

export const requirementsSearch = tool(
  "requirements_search",
  "Search product requirements by feature and/or text query",
  {
    project_id: z.string().describe("Project UUID"),
    feature_id: z.string().optional().describe("Filter by feature UUID"),
    q: z.string().optional().describe("Substring search on spec_key, statement, or rationale"),
  },
  async (args) => {
    let sql = "SELECT id, project_id, feature_id, spec_key, statement, rationale, acceptance_criteria, priority, updated_by_git_commit FROM product_requirements WHERE project_id = ?";
    const params: unknown[] = [args.project_id];

    if (args.feature_id) {
      sql += " AND feature_id = ?";
      params.push(args.feature_id);
    }
    if (args.q) {
      sql += " AND (spec_key LIKE ? OR statement LIKE ? OR rationale LIKE ?)";
      const like = `%${args.q}%`;
      params.push(like, like, like);
    }
    sql += " ORDER BY spec_key";

    const rows = await dolt.query(sql, params);
    return textResult(JSON.stringify({ requirements: rows }));
  },
);

function validateShall(statement: string): string | null {
  if (!/shall/i.test(statement)) {
    return "statement must include 'shall'";
  }
  return null;
}

export const requirementsCreate = tool(
  "requirements_create",
  "Create or upsert a product requirement by (project_id, feature_id, spec_key)",
  {
    project_id: z.string().describe("Project UUID"),
    feature_id: z.string().describe("Parent feature UUID"),
    spec_key: z.string().describe("Unique requirement key within feature"),
    statement: z.string().describe("Requirement statement (must include 'shall')"),
    rationale: z.string().optional().describe("Why this requirement exists"),
    acceptance_criteria: z.array(z.string()).optional().describe("List of acceptance criteria"),
    priority: z.string().optional().describe("Priority level"),
  },
  async (args) => {
    const keyErr = validateSpecKey(args.spec_key);
    if (keyErr) return textResult(JSON.stringify({ error: keyErr }));

    const shallErr = validateShall(args.statement);
    if (shallErr) return textResult(JSON.stringify({ error: shallErr }));

    const id = crypto.randomUUID();
    const acJson = args.acceptance_criteria ? JSON.stringify(args.acceptance_criteria) : null;

    await dolt.execute(
      `INSERT INTO product_requirements (id, project_id, feature_id, spec_key, statement, rationale, acceptance_criteria, priority, updated_by_git_commit)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE statement = VALUES(statement), rationale = VALUES(rationale), acceptance_criteria = VALUES(acceptance_criteria), priority = VALUES(priority), updated_by_git_commit = VALUES(updated_by_git_commit)`,
      [id, args.project_id, args.feature_id, args.spec_key, args.statement, args.rationale ?? null, acJson, args.priority ?? null, currentCommitHash],
    );
    return textResult(JSON.stringify({ ok: true, spec_key: args.spec_key }));
  },
);

export const requirementsUpdate = tool(
  "requirements_update",
  "Update an existing product requirement",
  {
    project_id: z.string().describe("Project UUID"),
    requirement_id: z.string().describe("Requirement UUID"),
    spec_key: z.string().optional().describe("New spec_key"),
    statement: z.string().optional().describe("New statement (must include 'shall')"),
    rationale: z.string().optional().describe("New rationale"),
    acceptance_criteria: z.array(z.string()).optional().describe("New acceptance criteria"),
    priority: z.string().optional().describe("New priority"),
  },
  async (args) => {
    if (args.spec_key) {
      const keyErr = validateSpecKey(args.spec_key);
      if (keyErr) return textResult(JSON.stringify({ error: keyErr }));
    }
    if (args.statement) {
      const shallErr = validateShall(args.statement);
      if (shallErr) return textResult(JSON.stringify({ error: shallErr }));
    }

    const sets: string[] = [];
    const params: unknown[] = [];

    if (args.spec_key !== undefined) { sets.push("spec_key = ?"); params.push(args.spec_key); }
    if (args.statement !== undefined) { sets.push("statement = ?"); params.push(args.statement); }
    if (args.rationale !== undefined) { sets.push("rationale = ?"); params.push(args.rationale); }
    if (args.acceptance_criteria !== undefined) { sets.push("acceptance_criteria = ?"); params.push(JSON.stringify(args.acceptance_criteria)); }
    if (args.priority !== undefined) { sets.push("priority = ?"); params.push(args.priority); }

    if (sets.length === 0) return textResult(JSON.stringify({ error: "no fields to update" }));

    sets.push("updated_by_git_commit = ?");
    params.push(currentCommitHash);
    params.push(args.project_id, args.requirement_id);

    await dolt.execute(
      `UPDATE product_requirements SET ${sets.join(", ")} WHERE project_id = ? AND id = ?`,
      params,
    );
    return textResult(JSON.stringify({ ok: true }));
  },
);

export const requirementsDelete = tool(
  "requirements_delete",
  "Delete a product requirement",
  {
    project_id: z.string().describe("Project UUID"),
    requirement_id: z.string().describe("Requirement UUID to delete"),
  },
  async (args) => {
    await dolt.execute(
      "DELETE FROM product_requirements WHERE project_id = ? AND id = ?",
      [args.project_id, args.requirement_id],
    );
    return textResult(JSON.stringify({ ok: true }));
  },
);

export const allTools = [
  domainsList,
  domainsCreate,
  domainsUpdate,
  featuresSearch,
  featuresCreate,
  featuresUpdate,
  featuresDelete,
  requirementsSearch,
  requirementsCreate,
  requirementsUpdate,
  requirementsDelete,
];
