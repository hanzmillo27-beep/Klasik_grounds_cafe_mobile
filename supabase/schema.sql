-- Read-only catalog queries for the existing Supabase database.
-- These statements inspect the schema; they do not create or alter objects.

-- Table columns, types, defaults, and nullability.
select
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- Foreign-key relationships between public tables.
select
  source.table_name,
  source.column_name,
  target.table_name as referenced_table,
  target.column_name as referenced_column
from information_schema.table_constraints as constraints
join information_schema.key_column_usage as source
  on source.constraint_catalog = constraints.constraint_catalog
  and source.constraint_schema = constraints.constraint_schema
  and source.constraint_name = constraints.constraint_name
join information_schema.constraint_column_usage as target
  on target.constraint_catalog = constraints.constraint_catalog
  and target.constraint_schema = constraints.constraint_schema
  and target.constraint_name = constraints.constraint_name
where constraints.constraint_type = 'FOREIGN KEY'
  and constraints.table_schema = 'public'
order by source.table_name, source.column_name;

-- Existing public functions and their call signatures.
select
  proc.proname as function_name,
  pg_get_function_identity_arguments(proc.oid) as arguments,
  pg_get_function_result(proc.oid) as result_type
from pg_proc as proc
join pg_namespace as ns on ns.oid = proc.pronamespace
where ns.nspname = 'public'
  and proc.prokind = 'f'
order by proc.proname;

-- Row-level security policies that control the app's table access.
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
