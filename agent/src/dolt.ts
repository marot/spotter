import mysql, { type RowDataPacket, type ResultSetHeader } from "mysql2/promise";

export type { RowDataPacket };

export interface DoltConfig {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
}

let pool: mysql.Pool | null = null;

export function getDoltConfig(): DoltConfig {
  return {
    host: process.env.SPOTTER_DOLT_HOST ?? "localhost",
    port: parseInt(process.env.SPOTTER_DOLT_PORT ?? "13306", 10),
    database: process.env.SPOTTER_DOLT_DATABASE ?? "spotter_product",
    user: process.env.SPOTTER_DOLT_USERNAME ?? "spotter",
    password: process.env.SPOTTER_DOLT_PASSWORD ?? "spotter",
  };
}

export function getPool(): mysql.Pool {
  if (!pool) {
    const config = getDoltConfig();
    pool = mysql.createPool({
      host: config.host,
      port: config.port,
      database: config.database,
      user: config.user,
      password: config.password,
      waitForConnections: true,
      connectionLimit: 3,
    });
  }
  return pool;
}

export async function query(
  sql: string,
  params: unknown[] = [],
): Promise<RowDataPacket[]> {
  const [rows] = await getPool().query<RowDataPacket[]>(sql, params);
  return rows;
}

export async function execute(
  sql: string,
  params: unknown[] = [],
): Promise<ResultSetHeader> {
  const [result] = await getPool().query<ResultSetHeader>(sql, params);
  return result;
}

export async function shutdown(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
