-- =====================================================================
--  Monitor de Precios PepsiCo Snacks — Esquema Supabase (Postgres)
--  Pegar TODO este archivo en Supabase > SQL Editor > Run.
--  Se puede volver a correr sin romper nada (es idempotente).
-- =====================================================================

-- ---------- 1. Tablas de configuración ----------

create table if not exists retailers (
  id          text primary key,
  nombre      text not null,
  dominio     text not null,
  plataforma  text not null check (plataforma in ('vtex','coto')),
  activo      boolean not null default true
);

insert into retailers (id, nombre, dominio, plataforma) values
  ('carrefour', 'Carrefour', 'www.carrefour.com.ar',               'vtex'),
  ('jumbo',     'Jumbo',     'www.jumbo.com.ar',                   'vtex'),
  ('disco',     'Disco',     'www.disco.com.ar',                   'vtex'),
  ('vea',       'Vea',       'www.vea.com.ar',                     'vtex'),
  ('dia',       'Día',       'diaonline.supermercadosdia.com.ar',  'vtex'),
  ('changomas', 'ChangoMás', 'www.masonline.com.ar',               'vtex'),
  ('coto',      'Coto',      'www.cotodigital.com.ar',             'coto')
on conflict (id) do update
  set nombre = excluded.nombre, dominio = excluded.dominio, plataforma = excluded.plataforma;

-- Marcas a monitorear. "termino" es lo que se busca en cada sitio.
create table if not exists marcas (
  id       text primary key,      -- clave normalizada (sin tildes ni símbolos)
  nombre   text not null,         -- cómo se muestra
  termino  text not null,         -- búsqueda en el sitio
  activo   boolean not null default true
);

insert into marcas (id, nombre, termino) values
  ('lays',     'Lay''s',   'lays'),
  ('doritos',  'Doritos',  'doritos'),
  ('3d',       '3D',       '3d'),
  ('cheetos',  'Cheetos',  'cheetos'),
  ('tostitos', 'Tostitos', 'tostitos'),
  ('twistos',  'Twistos',  'twistos'),
  ('pehuamar', 'Pehuamar', 'pehuamar')
on conflict (id) do update set nombre = excluded.nombre, termino = excluded.termino;

-- ---------- 2. Datos ----------

create table if not exists productos (
  ean          text primary key,
  nombre       text,              -- nombre tal como vino del primer retailer
  nombre_corto text,              -- nombre limpio (lo completa el agente Normalizador)
  marca        text,
  variedad     text,              -- ej. "Clásicas", "Queso", "Jamón Serrano"
  segmento     text,              -- ej. "Papas fritas", "Nachos", "Maní"
  gramaje_g    numeric,
  imagen_url   text,
  normalizado  boolean not null default false,
  creado_at    timestamptz not null default now()
);

create table if not exists precios (
  fecha            date not null,
  retailer_id      text not null references retailers(id),
  ean              text not null,
  nombre_retailer  text,
  precio           numeric,       -- precio de góndola online (con descuento directo aplicado)
  precio_lista     numeric,       -- precio "antes" (si hay rebaja); si no, igual a precio
  en_promo         boolean not null default false,
  promo_texto      text,          -- ej. "2do al 70%", "-15%"
  disponible       boolean not null default true,
  url              text,
  gramaje_g        numeric,
  precio_kg        numeric,
  capturado_at     timestamptz not null default now(),
  primary key (fecha, retailer_id, ean)
);
create index if not exists precios_ean_idx on precios (ean, fecha);

create table if not exists alertas (
  id               bigserial primary key,
  fecha            date not null,
  tipo             text not null,  -- suba | baja | promo_nueva | promo_fin | quiebre | reposicion | nuevo_sku
  retailer_id      text not null references retailers(id),
  ean              text not null,
  nombre           text,
  precio_anterior  numeric,
  precio_nuevo     numeric,
  variacion_pct    numeric,
  detalle          text,
  creado_at        timestamptz not null default now()
);
create index if not exists alertas_fecha_idx on alertas (fecha);

create table if not exists corridas (
  id        bigserial primary key,
  workflow  text not null,
  fecha     date,
  filas     integer,
  detalle   jsonb,
  creado_at timestamptz not null default now()
);

-- ---------- 3. Funciones que usan los agentes de n8n ----------

-- Agente 1 (Recolector): guarda el lote del día. Re-ejecutable: pisa el día.
create or replace function ingestar_precios(p_filas jsonb, p_fecha date, p_detalle jsonb default '{}'::jsonb)
returns integer language plpgsql as $$
declare n integer;
begin
  insert into productos (ean, nombre, marca, gramaje_g, imagen_url)
  select distinct on (f.ean) f.ean, f.nombre, f.marca, f.gramaje_g, f.imagen_url
  from jsonb_to_recordset(p_filas) as f(ean text, nombre text, marca text, gramaje_g numeric, imagen_url text)
  where f.ean is not null
  order by f.ean
  on conflict (ean) do update
    set imagen_url = coalesce(productos.imagen_url, excluded.imagen_url),
        gramaje_g  = coalesce(productos.gramaje_g,  excluded.gramaje_g),
        marca      = coalesce(productos.marca,      excluded.marca);

  insert into precios (fecha, retailer_id, ean, nombre_retailer, precio, precio_lista,
                       en_promo, promo_texto, disponible, url, gramaje_g, precio_kg)
  select distinct on (f.retailer_id, f.ean)
         p_fecha, f.retailer_id, f.ean, f.nombre, f.precio, coalesce(f.precio_lista, f.precio),
         coalesce(f.en_promo, false), f.promo_texto, coalesce(f.disponible, true), f.url, f.gramaje_g,
         case when f.gramaje_g > 0 and f.precio > 0 then round(f.precio / f.gramaje_g * 1000, 2) end
  from jsonb_to_recordset(p_filas) as f(retailer_id text, ean text, nombre text, precio numeric,
       precio_lista numeric, en_promo boolean, promo_texto text, disponible boolean, url text, gramaje_g numeric)
  where f.ean is not null and f.retailer_id in (select id from retailers)
  order by f.retailer_id, f.ean
  on conflict (fecha, retailer_id, ean) do update
    set nombre_retailer = excluded.nombre_retailer, precio = excluded.precio,
        precio_lista = excluded.precio_lista, en_promo = excluded.en_promo,
        promo_texto = excluded.promo_texto, disponible = excluded.disponible,
        url = excluded.url, gramaje_g = excluded.gramaje_g, precio_kg = excluded.precio_kg,
        capturado_at = now();
  get diagnostics n = row_count;

  insert into corridas (workflow, fecha, filas, detalle) values ('recolector', p_fecha, n, p_detalle);
  return n;
end $$;

-- Agente 2 (Normalizador): completa marca/variedad/segmento/gramaje.
create or replace function actualizar_productos(p_filas jsonb)
returns integer language plpgsql as $$
declare n integer;
begin
  update productos p
     set nombre_corto = coalesce(nullif(f.nombre_corto, ''), p.nombre_corto),
         marca        = coalesce(nullif(f.marca, ''), p.marca),
         variedad     = coalesce(nullif(f.variedad, ''), p.variedad),
         segmento     = coalesce(nullif(f.segmento, ''), p.segmento),
         gramaje_g    = coalesce(f.gramaje_g, p.gramaje_g),
         normalizado  = true
    from jsonb_to_recordset(p_filas) as f(ean text, nombre_corto text, marca text, variedad text,
                                           segmento text, gramaje_g numeric)
   where p.ean = f.ean;
  get diagnostics n = row_count;

  -- recalcula precio por kg donde ahora conocemos el gramaje
  update precios pr
     set gramaje_g = p.gramaje_g,
         precio_kg = round(pr.precio / p.gramaje_g * 1000, 2)
    from productos p
   where p.ean = pr.ean and p.gramaje_g > 0 and pr.precio > 0
     and (pr.gramaje_g is null or pr.precio_kg is null);

  insert into corridas (workflow, filas) values ('normalizador', n);
  return n;
end $$;

-- Agente 3 (Alertas): compara el día contra la captura anterior de cada retailer.
create or replace function generar_alertas(p_fecha date, p_umbral numeric default 1.0)
returns setof alertas language plpgsql as $$
begin
  delete from alertas where fecha = p_fecha;

  insert into alertas (fecha, tipo, retailer_id, ean, nombre, precio_anterior, precio_nuevo, variacion_pct, detalle)
  with hoy as (
    select * from precios where fecha = p_fecha
  ), ret_hoy as (           -- solo retailers que hoy respondieron (si uno falló, no dispara falsas alertas)
    select distinct retailer_id from hoy
  ), ant_fecha as (
    select retailer_id, max(fecha) as f from precios where fecha < p_fecha group by retailer_id
  ), ant as (
    select p.* from precios p join ant_fecha a on a.retailer_id = p.retailer_id and p.fecha = a.f
  ), comp as (
    select coalesce(h.retailer_id, a.retailer_id)           as retailer_id,
           coalesce(h.ean, a.ean)                           as ean,
           coalesce(h.nombre_retailer, a.nombre_retailer)   as nombre,
           a.precio as p_ant, h.precio as p_hoy,
           a.en_promo as promo_ant, h.en_promo as promo_hoy,
           a.disponible as disp_ant, h.disponible as disp_hoy,
           h.promo_texto,
           (h.ean is not null) as en_hoy, (a.ean is not null) as en_ant,
           exists (select 1 from ant_fecha af where af.retailer_id = coalesce(h.retailer_id, a.retailer_id)) as tiene_hist
      from hoy h full join ant a on a.retailer_id = h.retailer_id and a.ean = h.ean
     where coalesce(h.retailer_id, a.retailer_id) in (select retailer_id from ret_hoy)
  )
  select p_fecha, t.tipo, c.retailer_id, c.ean, c.nombre, c.p_ant, c.p_hoy,
         case when c.p_ant > 0 and c.p_hoy > 0 then round((c.p_hoy / c.p_ant - 1) * 100, 2) end,
         t.detalle
    from comp c
    cross join lateral (values
      (case when c.en_hoy and c.en_ant and c.p_ant > 0 and c.p_hoy > 0
                 and (c.p_hoy / c.p_ant - 1) * 100 >=  p_umbral then 'suba' end, null::text),
      (case when c.en_hoy and c.en_ant and c.p_ant > 0 and c.p_hoy > 0
                 and (c.p_hoy / c.p_ant - 1) * 100 <= -p_umbral then 'baja' end, null),
      (case when c.en_hoy and c.en_ant and c.promo_hoy and not c.promo_ant then 'promo_nueva' end, c.promo_texto),
      (case when c.en_hoy and c.en_ant and not c.promo_hoy and c.promo_ant then 'promo_fin' end, null),
      (case when c.en_ant and c.disp_ant and (not c.en_hoy or not c.disp_hoy) then 'quiebre' end,
            case when c.en_hoy then 'Sin stock online' else 'Ya no aparece en el sitio' end),
      (case when c.en_hoy and c.en_ant and not c.disp_ant and c.disp_hoy then 'reposicion' end, null),
      (case when c.en_hoy and not c.en_ant and c.tiene_hist
                 and not exists (select 1 from precios x where x.retailer_id = c.retailer_id
                                   and x.ean = c.ean and x.fecha < p_fecha) then 'nuevo_sku' end, null)
    ) as t(tipo, detalle)
   where t.tipo is not null;

  return query select * from alertas where fecha = p_fecha
               order by tipo, abs(coalesce(variacion_pct, 0)) desc;
end $$;

-- ---------- 4. Vistas (las usan el dashboard y el agente Analista) ----------

create or replace view v_precios as
select p.fecha, p.retailer_id, r.nombre as retailer, p.ean,
       coalesce(pr.nombre_corto, p.nombre_retailer) as producto,
       pr.marca, pr.variedad, pr.segmento,
       coalesce(pr.gramaje_g, p.gramaje_g) as gramaje_g,
       p.precio, p.precio_lista, p.en_promo, p.promo_texto, p.disponible, p.precio_kg,
       p.url, pr.imagen_url
  from precios p
  join retailers r on r.id = p.retailer_id
  left join productos pr on pr.ean = p.ean;

-- Último día capturado + variación contra la captura anterior del mismo retailer
create or replace view v_precios_hoy as
with ult as (select max(fecha) as f from precios)
select v.*, prev.precio as precio_anterior,
       case when prev.precio > 0 and v.precio > 0 then round((v.precio / prev.precio - 1) * 100, 2) end as var_pct
  from v_precios v
  cross join ult
  left join lateral (
       select x.precio from precios x
        where x.retailer_id = v.retailer_id and x.ean = v.ean and x.fecha < v.fecha and x.precio > 0
        order by x.fecha desc limit 1) prev on true
 where v.fecha = ult.f;

-- Índice de precios por retailer: 100 = mediana del mercado para el mismo EAN ese día
-- (solo EANs que están en 3 o más cadenas, para que la comparación sea justa)
create or replace view v_indice_retailer as
with base as (
  select fecha, retailer_id, ean, precio from precios where precio > 0
), med as (
  select fecha, ean, percentile_cont(0.5) within group (order by precio) as mediana
    from base group by fecha, ean having count(*) >= 3
)
select b.fecha, b.retailer_id, r.nombre as retailer,
       round(avg(b.precio / m.mediana)::numeric * 100, 1) as indice,
       count(*) as skus_comparables
  from base b join med m using (fecha, ean) join retailers r on r.id = b.retailer_id
 group by b.fecha, b.retailer_id, r.nombre;

-- Tendencia diaria por retailer y marca (liviana, para gráficos)
create or replace view v_tendencia as
select p.fecha, p.retailer_id, r.nombre as retailer, pr.marca,
       count(*) as skus,
       round(avg(p.precio_kg), 0) as precio_kg_prom,
       round(100.0 * count(*) filter (where p.en_promo) / count(*), 1) as pct_promo,
       count(*) filter (where not p.disponible) as sin_stock
  from precios p join retailers r on r.id = p.retailer_id
  left join productos pr on pr.ean = p.ean
 group by p.fecha, p.retailer_id, r.nombre, pr.marca;

create or replace view v_alertas as
select a.*, r.nombre as retailer, pr.marca, coalesce(pr.gramaje_g, null) as gramaje_g
  from alertas a join retailers r on r.id = a.retailer_id
  left join productos pr on pr.ean = a.ean;

-- ---------- 5. Resumen diario (Agente 3 lo usa para armar el mail) ----------

create or replace function resumen_diario(p_fecha date, p_umbral numeric default 1.0)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform generar_alertas(p_fecha, p_umbral);

  select jsonb_build_object(
    'fecha',          p_fecha,
    'fecha_anterior', (select max(fecha) from precios where fecha < p_fecha),
    'skus',           (select count(distinct ean) from precios where fecha = p_fecha),
    'registros',      (select count(*) from precios where fecha = p_fecha),
    'por_retailer',   '[]'::jsonb,   -- se completa abajo
    'indice',         coalesce((
        select jsonb_agg(jsonb_build_object('retailer', retailer, 'indice', indice,
                                            'skus_comparables', skus_comparables) order by indice)
          from v_indice_retailer where fecha = p_fecha), '[]'::jsonb),
    'conteo',         coalesce((
        select jsonb_object_agg(tipo, n) from (select tipo, count(*) n from alertas
                                                where fecha = p_fecha group by tipo) s), '{}'::jsonb),
    'alertas',        coalesce((
        select jsonb_agg(jsonb_build_object(
                 'tipo', tipo, 'retailer', retailer, 'marca', marca, 'nombre', nombre,
                 'precio_anterior', precio_anterior, 'precio_nuevo', precio_nuevo,
                 'variacion_pct', variacion_pct, 'detalle', detalle)
                 order by tipo, abs(coalesce(variacion_pct, 0)) desc)
          from v_alertas where fecha = p_fecha), '[]'::jsonb)
  ) into r;

  r :=jsonb_set(r, '{por_retailer}', coalesce((
        select jsonb_agg(x order by x->>'retailer') from (
          select jsonb_build_object('retailer', r2.nombre, 'skus', count(*),
                   'en_promo', count(*) filter (where p.en_promo),
                   'sin_stock', count(*) filter (where not p.disponible)) as x
            from precios p join retailers r2 on r2.id = p.retailer_id
           where p.fecha = p_fecha group by r2.nombre) s), '[]'::jsonb));
  return r;
end $$;

-- ---------- 6. Reporte semanal (Agente 5) ----------

create or replace function comparativo_semanal(p_fecha date)
returns table (marca text, producto text, ean text, gramaje_g numeric, retailer text,
               precio_hoy numeric, precio_hace_7d numeric, var_7d_pct numeric, precio_kg numeric,
               en_promo boolean, promo_texto text, disponible boolean, url text)
language sql stable as $$
  with hoy as (
    select * from precios where fecha = (select max(fecha) from precios where fecha <= p_fecha)
  ), ref as (
    select distinct on (x.retailer_id, x.ean) x.retailer_id, x.ean, x.precio
      from precios x
     where x.fecha <= p_fecha - 7 and x.fecha >= p_fecha - 14 and x.precio > 0
     order by x.retailer_id, x.ean, x.fecha desc
  )
  select pr.marca, coalesce(pr.nombre_corto, h.nombre_retailer), h.ean,
         coalesce(pr.gramaje_g, h.gramaje_g), r.nombre,
         h.precio, ref.precio,
         case when ref.precio > 0 and h.precio > 0 then round((h.precio / ref.precio - 1) * 100, 1) end,
         h.precio_kg, h.en_promo, h.promo_texto, h.disponible, h.url
    from hoy h
    join retailers r on r.id = h.retailer_id
    left join productos pr on pr.ean = h.ean
    left join ref on ref.retailer_id = h.retailer_id and ref.ean = h.ean
   order by 1, 2, 5;
$$;

-- ---------- 7. Seguridad ----------
-- El dashboard usa la clave "anon" (pública): solo puede LEER.
-- n8n usa la conexión Postgres (no pasa por estas políticas).

alter table retailers enable row level security;
alter table marcas    enable row level security;
alter table productos enable row level security;
alter table precios   enable row level security;
alter table alertas   enable row level security;
alter table corridas  enable row level security;

drop policy if exists lectura_publica on retailers;
drop policy if exists lectura_publica on marcas;
drop policy if exists lectura_publica on productos;
drop policy if exists lectura_publica on precios;
drop policy if exists lectura_publica on alertas;
drop policy if exists lectura_publica on corridas;
create policy lectura_publica on retailers for select to anon using (true);
create policy lectura_publica on marcas    for select to anon using (true);
create policy lectura_publica on productos for select to anon using (true);
create policy lectura_publica on precios   for select to anon using (true);
create policy lectura_publica on alertas   for select to anon using (true);
create policy lectura_publica on corridas  for select to anon using (true);

grant select on v_precios, v_precios_hoy, v_indice_retailer, v_tendencia, v_alertas to anon;
