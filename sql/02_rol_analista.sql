-- =====================================================================
--  Usuario de SOLO LECTURA para el Agente Analista (chat).
--  El agente escribe consultas SQL por su cuenta: con este usuario
--  no puede borrar ni modificar nada aunque se equivoque.
--
--  1) Cambiá la contraseña de abajo por una tuya.
--  2) Pegá en Supabase > SQL Editor > Run.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'analista_ro') then
    create role analista_ro login password 'CAMBIAR_ESTA_CLAVE';
  end if;
end $$;

grant usage on schema public to analista_ro;
grant select on all tables in schema public to analista_ro;
alter default privileges in schema public grant select on tables to analista_ro;
alter role analista_ro set statement_timeout = '15s';

-- Las tablas tienen RLS activado: este usuario necesita su propia política de lectura.
do $$
declare t text;
begin
  foreach t in array array['retailers','marcas','productos','precios','alertas','corridas'] loop
    execute format('drop policy if exists lectura_analista on %I', t);
    execute format('create policy lectura_analista on %I for select to analista_ro using (true)', t);
  end loop;
end $$;
