-- =====================================================================
--  Monitor de Precios PepsiCo Snacks — Mejoras v2
--  Zonas (precios geolocalizados) · La Anónima · Competencia ·
--  Tamaños (medium / large bag) · Precio sugerido · Historial por día
--
--  Pegar TODO este archivo en Supabase > SQL Editor > Run,
--  DESPUÉS de 01_esquema.sql. Se puede volver a correr sin romper nada.
--  No borra datos: los precios que ya tenías quedan en la zona "web".
-- =====================================================================

-- ---------- 1. Zonas ----------
-- "web" = precio que muestra el sitio sin elegir ubicación (lo que se venía guardando).
-- El resto son provincias; cada una usa un código postal de referencia.
-- Para sumar una zona al relevamiento:  update zonas set activo = true where id = 'salta';

create table if not exists zonas (
  id        text primary key,
  nombre    text not null,
  provincia text,
  cp        text,                 -- código postal de referencia (null solo para "web")
  orden     integer not null default 100,
  activo    boolean not null default false
);

insert into zonas (id, nombre, provincia, cp, orden, activo) values
  ('web',              'Web (sin zona)',                 null,                 null,   0,  true),
  ('caba',             'CABA',                           'CABA',               '1425', 1,  true),
  ('gba',              'GBA (Pilar)',                    'Buenos Aires',       '1629', 2,  true),
  ('bsas_interior',    'Buenos Aires interior (Mar del Plata)', 'Buenos Aires','7600', 3,  true),
  ('cordoba',          'Córdoba',                        'Córdoba',            '5000', 4,  true),
  ('santa_fe',         'Santa Fe (Rosario)',             'Santa Fe',           '2000', 5,  true),
  ('mendoza',          'Mendoza',                        'Mendoza',            '5500', 6,  true),
  ('neuquen',          'Neuquén',                        'Neuquén',            '8300', 7,  true),
  ('tucuman',          'Tucumán',                        'Tucumán',            '4000', 8,  true),
  ('salta',            'Salta',                          'Salta',              '4400', 20, false),
  ('jujuy',            'Jujuy',                          'Jujuy',              '4600', 21, false),
  ('santiago',         'Santiago del Estero',            'Santiago del Estero','4200', 22, false),
  ('catamarca',        'Catamarca',                      'Catamarca',          '4700', 23, false),
  ('la_rioja',         'La Rioja',                       'La Rioja',           '5300', 24, false),
  ('san_juan',         'San Juan',                       'San Juan',           '5400', 25, false),
  ('san_luis',         'San Luis',                       'San Luis',           '5700', 26, false),
  ('chaco',            'Chaco (Resistencia)',            'Chaco',              '3500', 27, false),
  ('corrientes',       'Corrientes',                     'Corrientes',         '3400', 28, false),
  ('formosa',          'Formosa',                        'Formosa',            '3600', 29, false),
  ('misiones',         'Misiones (Posadas)',             'Misiones',           '3300', 30, false),
  ('entre_rios',       'Entre Ríos (Paraná)',            'Entre Ríos',         '3100', 31, false),
  ('la_pampa',         'La Pampa (Santa Rosa)',          'La Pampa',           '6300', 32, false),
  ('rio_negro',        'Río Negro (Bariloche)',          'Río Negro',          '8400', 33, false),
  ('chubut',           'Chubut (Comodoro Rivadavia)',    'Chubut',             '9000', 34, false),
  ('santa_cruz',       'Santa Cruz (Río Gallegos)',      'Santa Cruz',         '9400', 35, false),
  ('tierra_del_fuego', 'Tierra del Fuego (Ushuaia)',     'Tierra del Fuego',   '9410', 36, false)
on conflict (id) do nothing;   -- no pisa lo que hayas activado o editado

-- ---------- 2. Cadenas: La Anónima + cómo regionaliza cada una ----------
--   modo_zona = 'cp'      → el precio cambia según el código postal (Carrefour, ChangoMás, Día)
--   modo_zona = 'sc'      → el precio cambia según la sucursal elegida (Jumbo, Disco, Vea):
--                           hay que cargar el nº de sucursal por zona en retailer_zonas.sc
--   modo_zona = 'ninguno' → un solo precio online (Coto, La Anónima por ahora): se guarda en "web"

alter table retailers add column if not exists modo_zona text not null default 'ninguno';
alter table retailers drop constraint if exists retailers_plataforma_check;
alter table retailers add constraint retailers_plataforma_check check (plataforma in ('vtex','coto','laanonima'));
alter table retailers drop constraint if exists retailers_modo_zona_check;
alter table retailers add constraint retailers_modo_zona_check check (modo_zona in ('cp','sc','ninguno'));

insert into retailers (id, nombre, dominio, plataforma) values
  ('laanonima', 'La Anónima', 'www.laanonima.com.ar', 'laanonima')
on conflict (id) do nothing;

update retailers set modo_zona = 'cp' where id in ('carrefour','changomas','dia') and modo_zona = 'ninguno';
update retailers set modo_zona = 'sc' where id in ('jumbo','disco','vea')         and modo_zona = 'ninguno';

-- Excepciones por cadena y zona (opcional). Sin fila = se usa el CP de la zona.
create table if not exists retailer_zonas (
  retailer_id text not null references retailers(id),
  zona_id     text not null references zonas(id),
  cp          text,                         -- CP alternativo para esta cadena en esta zona
  sc          text,                         -- nº de sucursal / canal de venta (cadenas con modo_zona = 'sc')
  activo      boolean not null default true, -- false = no relevar esta cadena en esta zona
  primary key (retailer_id, zona_id)
);
-- Ejemplo (Jumbo en CABA usando la sucursal 32):
--   insert into retailer_zonas (retailer_id, zona_id, sc) values ('jumbo','caba','32');

-- Códigos internos de cadenas que no publican el EAN en el listado (La Anónima).
create table if not exists equivalencias (
  retailer_id  text not null references retailers(id),
  sku_retailer text not null,
  ean          text not null,
  creado_at    timestamptz not null default now(),
  primary key (retailer_id, sku_retailer)
);

-- ---------- 3. Marcas: PepsiCo, competencia y marcas propias ----------
alter table marcas add column if not exists tipo          text not null default 'pepsico';
alter table marcas add column if not exists fabricante    text;
alter table marcas add column if not exists alias         text;   -- otros nombres con los que la cadena publica la marca, separados por coma
alter table marcas add column if not exists solo_retailer text;   -- si se completa, sólo se busca en esas cadenas (ids separados por coma)
alter table marcas drop constraint if exists marcas_tipo_check;
alter table marcas add constraint marcas_tipo_check check (tipo in ('pepsico','competencia','marca_propia'));

update marcas set fabricante = 'PepsiCo' where tipo = 'pepsico' and fabricante is null;

-- "termino" admite varias búsquedas separadas por |.
-- Los alias de las marcas propias son una primera aproximación: si una cadena publica
-- la marca con otro nombre, agregalo en la columna alias.
insert into marcas (id, nombre, termino, tipo, alias, solo_retailer) values
  ('5hispanos',    '5 Hispanos',            '5 hispanos|cinco hispanos', 'competencia',  'cinco hispanos,5hispanos', null),
  ('pringles',     'Pringles',              'pringles',                  'competencia',  null, null),
  ('krachitos',    'Krachitos',             'krachitos',                 'competencia',  'krach-itos,krach itos', null),
  ('saladix',      'Saladix',               'saladix',                   'competencia',  null, null),
  ('mp_carrefour', 'Carrefour (MP)',        'papas fritas carrefour|nachos carrefour|palitos carrefour|mani carrefour', 'marca_propia', 'carrefour,carrefour classic,carrefour original', 'carrefour'),
  ('mp_dia',       'Día (MP)',              'papas fritas dia|nachos dia|palitos dia|mani dia',                         'marca_propia', 'dia', 'dia'),
  ('mp_coto',      'Coto (MP)',             'papas fritas coto|nachos coto|palitos coto|mani coto',                     'marca_propia', 'coto', 'coto'),
  ('mp_cencosud',  'Cuisine & Co (MP)',     'papas fritas cuisine|nachos cuisine|palitos cuisine|mani cuisine',         'marca_propia', 'cuisine & co,cuisine and co,cuisine&co,jumbo,vea,disco', 'jumbo,disco,vea'),
  ('mp_changomas', 'Check (MP)',            'papas fritas check|nachos check|palitos check|mani check',                 'marca_propia', 'check', 'changomas'),
  ('mp_laanonima', 'La Anónima (MP)',       'papas fritas la anonima|nachos la anonima|palitos la anonima|mani la anonima', 'marca_propia', 'la anonima,best', 'laanonima')
on conflict (id) do nothing;

-- ---------- 4. Tamaños de bolsa ----------
create table if not exists tamanos (
  id      text primary key,
  nombre  text not null,
  desde_g numeric not null,    -- inclusive
  hasta_g numeric not null,    -- inclusive
  orden   integer not null
);
insert into tamanos (id, nombre, desde_g, hasta_g, orden) values
  ('single', 'Single',     0,   59.99,  1),
  ('medium', 'Medium bag', 60,  120,    2),
  ('large',  'Large bag',  120.01, 300, 3),
  ('xl',     'XL / Familiar', 300.01, 100000, 4)
on conflict (id) do nothing;

-- Segmentos con los nombres que usa PepsiCo
update productos set segmento = 'Papas'     where segmento = 'Papas fritas';
update productos set segmento = 'Tortilla'  where segmento = 'Nachos';
update productos set segmento = 'Extruidos' where segmento = 'Snacks de maíz';

-- ---------- 5. Precios y alertas por zona ----------
alter table precios add column if not exists zona_id text not null default 'web' references zonas(id);
do $$
begin
  if not exists (
    select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
     where i.indrelid = 'precios'::regclass and i.indisprimary and a.attname = 'zona_id') then
    alter table precios drop constraint precios_pkey;
    alter table precios add primary key (fecha, retailer_id, zona_id, ean);
  end if;
end $$;
create index if not exists precios_zona_idx on precios (zona_id, fecha);

alter table alertas add column if not exists zona_id text not null default 'web' references zonas(id);

-- ---------- 6. Precio sugerido ----------
-- zona_id / retailer_id vacíos = vale para todas las zonas / todas las cadenas.
create table if not exists precios_sugeridos (
  id             bigserial primary key,
  ean            text not null,
  precio         numeric not null check (precio > 0),
  vigencia_desde date not null,
  zona_id        text references zonas(id),
  retailer_id    text references retailers(id),
  descripcion    text,             -- nombre tal como venía en el archivo
  lote           text,             -- nombre del archivo cargado
  cargado_at     timestamptz not null default now()
);
create unique index if not exists precios_sugeridos_uk
  on precios_sugeridos (ean, vigencia_desde, coalesce(zona_id, ''), coalesce(retailer_id, ''));

-- La usa el workflow 6 (Lector de precio sugerido). Re-ejecutable: pisa la misma vigencia.
create or replace function cargar_sugeridos(p_filas jsonb, p_vigencia date, p_lote text default null)
returns integer language plpgsql as $$
declare n integer;
begin
  insert into precios_sugeridos (ean, precio, vigencia_desde, zona_id, retailer_id, descripcion, lote)
  select distinct on (f.ean, coalesce(z.id, ''), coalesce(r.id, ''))
         f.ean, f.precio, p_vigencia, z.id, r.id, f.descripcion, p_lote
    from jsonb_to_recordset(p_filas) as f(ean text, precio numeric, zona_id text, retailer_id text, descripcion text)
    left join zonas z     on z.id = nullif(f.zona_id, '')
    left join retailers r on r.id = nullif(f.retailer_id, '')
   where f.ean is not null and f.precio > 0
   order by f.ean, coalesce(z.id, ''), coalesce(r.id, '')
  on conflict (ean, vigencia_desde, coalesce(zona_id, ''), coalesce(retailer_id, '')) do update
    set precio = excluded.precio, descripcion = excluded.descripcion, lote = excluded.lote, cargado_at = now();
  get diagnostics n = row_count;
  insert into corridas (workflow, fecha, filas, detalle)
  values ('sugeridos', p_vigencia, n, jsonb_build_object('lote', p_lote));
  return n;
end $$;

-- Sugerido vigente para un producto en una fecha: gana el más específico (cadena, después zona) y el más reciente.
create or replace function sugerido_vigente(p_ean text, p_zona text, p_retailer text, p_fecha date)
returns numeric language sql stable security definer set search_path = public as $$
  select s.precio
    from precios_sugeridos s
   where s.ean = p_ean and s.vigencia_desde <= p_fecha
     and (s.zona_id is null or s.zona_id = p_zona)
     and (s.retailer_id is null or s.retailer_id = p_retailer)
   order by (s.retailer_id is not null) desc, (s.zona_id is not null) desc, s.vigencia_desde desc
   limit 1;
$$;

-- ---------- 7. Funciones de los agentes (versión con zonas) ----------

drop function if exists ingestar_precios(jsonb, date, jsonb);
create or replace function ingestar_precios(p_filas jsonb, p_fecha date, p_detalle jsonb default '{}'::jsonb,
                                            p_equivalencias jsonb default '[]'::jsonb)
returns integer language plpgsql as $$
declare n integer;
begin
  -- códigos internos → EAN aprendidos en esta corrida
  insert into equivalencias (retailer_id, sku_retailer, ean)
  select distinct on (e.retailer_id, e.sku_retailer) e.retailer_id, e.sku_retailer, e.ean
    from jsonb_to_recordset(coalesce(p_equivalencias, '[]'::jsonb)) as e(retailer_id text, sku_retailer text, ean text)
   where e.ean ~ '^\d{8,14}$' and e.retailer_id in (select id from retailers)
  on conflict (retailer_id, sku_retailer) do update set ean = excluded.ean;

  -- lo que se había guardado con el código interno pasa a su EAN
  update precios p set ean = e.ean
    from equivalencias e
   where p.retailer_id = e.retailer_id and p.ean = 'SKU-' || e.retailer_id || '-' || e.sku_retailer
     and not exists (select 1 from precios q where q.fecha = p.fecha and q.retailer_id = p.retailer_id
                        and q.zona_id = p.zona_id and q.ean = e.ean);
  delete from precios p using equivalencias e
   where p.retailer_id = e.retailer_id and p.ean = 'SKU-' || e.retailer_id || '-' || e.sku_retailer;
  update alertas a set ean = e.ean
    from equivalencias e
   where a.retailer_id = e.retailer_id and a.ean = 'SKU-' || e.retailer_id || '-' || e.sku_retailer;

  create temporary table _lote on commit drop as
  select f.retailer_id,
         coalesce(nullif(f.zona_id, ''), 'web')                         as zona_id,
         coalesce(eq.ean, f.ean)                                        as ean,
         f.nombre, f.marca, f.precio, f.precio_lista, f.en_promo, f.promo_texto,
         f.disponible, f.url, f.gramaje_g, f.imagen_url
    from jsonb_to_recordset(p_filas) as f(retailer_id text, zona_id text, ean text, nombre text, marca text,
         precio numeric, precio_lista numeric, en_promo boolean, promo_texto text, disponible boolean,
         url text, gramaje_g numeric, imagen_url text)
    left join equivalencias eq
           on eq.retailer_id = f.retailer_id and f.ean = 'SKU-' || f.retailer_id || '-' || eq.sku_retailer
   where f.ean is not null
     and f.retailer_id in (select id from retailers)
     and coalesce(nullif(f.zona_id, ''), 'web') in (select id from zonas);

  insert into productos (ean, nombre, marca, gramaje_g, imagen_url)
  select distinct on (l.ean) l.ean, l.nombre, l.marca, l.gramaje_g, l.imagen_url
    from _lote l
   order by l.ean, (l.zona_id = 'web') desc
  on conflict (ean) do update
    set imagen_url = coalesce(productos.imagen_url, excluded.imagen_url),
        gramaje_g  = coalesce(productos.gramaje_g,  excluded.gramaje_g),
        marca      = coalesce(productos.marca,      excluded.marca);

  insert into precios (fecha, retailer_id, zona_id, ean, nombre_retailer, precio, precio_lista,
                       en_promo, promo_texto, disponible, url, gramaje_g, precio_kg)
  select distinct on (l.retailer_id, l.zona_id, l.ean)
         p_fecha, l.retailer_id, l.zona_id, l.ean, l.nombre, l.precio, coalesce(l.precio_lista, l.precio),
         coalesce(l.en_promo, false), l.promo_texto, coalesce(l.disponible, true), l.url, l.gramaje_g,
         case when l.gramaje_g > 0 and l.precio > 0 then round(l.precio / l.gramaje_g * 1000, 2) end
    from _lote l
   order by l.retailer_id, l.zona_id, l.ean
  on conflict (fecha, retailer_id, zona_id, ean) do update
    set nombre_retailer = excluded.nombre_retailer, precio = excluded.precio,
        precio_lista = excluded.precio_lista, en_promo = excluded.en_promo,
        promo_texto = excluded.promo_texto, disponible = excluded.disponible,
        url = excluded.url, gramaje_g = excluded.gramaje_g, precio_kg = excluded.precio_kg,
        capturado_at = now();
  get diagnostics n = row_count;

  drop table _lote;
  delete from productos pr using equivalencias e
   where pr.ean = 'SKU-' || e.retailer_id || '-' || e.sku_retailer;
  insert into corridas (workflow, fecha, filas, detalle) values ('recolector', p_fecha, n, p_detalle);
  return n;
end $$;

-- Alertas: cada cadena se compara contra su captura anterior EN LA MISMA ZONA.
create or replace function generar_alertas(p_fecha date, p_umbral numeric default 1.0)
returns setof alertas language plpgsql as $$
begin
  delete from alertas where fecha = p_fecha;

  insert into alertas (fecha, tipo, retailer_id, zona_id, ean, nombre, precio_anterior, precio_nuevo, variacion_pct, detalle)
  with hoy as (
    select * from precios where fecha = p_fecha
  ), ret_hoy as (           -- solo cadena+zona que hoy respondieron (si una falló, no dispara falsas alertas)
    select distinct retailer_id, zona_id from hoy
  ), ant_fecha as (
    select retailer_id, zona_id, max(fecha) as f from precios where fecha < p_fecha group by retailer_id, zona_id
  ), ant as (
    select p.* from precios p
      join ant_fecha a on a.retailer_id = p.retailer_id and a.zona_id = p.zona_id and p.fecha = a.f
  ), comp as (
    select coalesce(h.retailer_id, a.retailer_id)           as retailer_id,
           coalesce(h.zona_id, a.zona_id)                   as zona_id,
           coalesce(h.ean, a.ean)                           as ean,
           coalesce(h.nombre_retailer, a.nombre_retailer)   as nombre,
           a.precio as p_ant, h.precio as p_hoy,
           a.en_promo as promo_ant, h.en_promo as promo_hoy,
           a.disponible as disp_ant, h.disponible as disp_hoy,
           h.promo_texto,
           (h.ean is not null) as en_hoy, (a.ean is not null) as en_ant
      from hoy h
      full join ant a on a.retailer_id = h.retailer_id and a.zona_id = h.zona_id and a.ean = h.ean
     where (coalesce(h.retailer_id, a.retailer_id), coalesce(h.zona_id, a.zona_id))
           in (select retailer_id, zona_id from ret_hoy)
  )
  select p_fecha, t.tipo, c.retailer_id, c.zona_id, c.ean, c.nombre, c.p_ant, c.p_hoy,
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
      (case when c.en_hoy and not c.en_ant
                 and exists (select 1 from ant_fecha af where af.retailer_id = c.retailer_id and af.zona_id = c.zona_id)
                 and not exists (select 1 from precios x where x.retailer_id = c.retailer_id and x.zona_id = c.zona_id
                                   and x.ean = c.ean and x.fecha < p_fecha) then 'nuevo_sku' end, null)
    ) as t(tipo, detalle)
   where t.tipo is not null;

  return query select * from alertas where fecha = p_fecha
               order by tipo, abs(coalesce(variacion_pct, 0)) desc;
end $$;

-- ---------- 8. Vistas ----------
drop view if exists v_precios_hoy, v_indice_retailer, v_tendencia, v_alertas, v_precios, v_fechas, v_productos cascade;

create view v_productos as
select pr.ean, coalesce(pr.nombre_corto, pr.nombre) as producto, pr.marca,
       coalesce(m.tipo, 'pepsico') as tipo_marca, m.fabricante,
       pr.variedad, pr.segmento, pr.gramaje_g, t.nombre as tamano, pr.imagen_url
  from productos pr
  left join marcas m  on m.nombre = pr.marca
  left join tamanos t on pr.gramaje_g between t.desde_g and t.hasta_g;

create view v_precios as
select p.fecha, p.retailer_id, r.nombre as retailer, p.zona_id, z.nombre as zona, p.ean,
       coalesce(pr.nombre_corto, p.nombre_retailer) as producto,
       pr.marca, coalesce(m.tipo, 'pepsico') as tipo_marca, m.fabricante,
       pr.variedad, pr.segmento,
       coalesce(pr.gramaje_g, p.gramaje_g) as gramaje_g, t.nombre as tamano,
       p.precio, p.precio_lista, p.en_promo, p.promo_texto, p.disponible, p.precio_kg,
       p.url, pr.imagen_url
  from precios p
  join retailers r on r.id = p.retailer_id
  join zonas z     on z.id = p.zona_id
  left join productos pr on pr.ean = p.ean
  left join marcas m     on m.nombre = pr.marca
  left join tamanos t    on coalesce(pr.gramaje_g, p.gramaje_g) between t.desde_g and t.hasta_g;

-- Precios de un día en una zona (la usa el dashboard).
--   · p_fecha vacío = último día capturado.
--   · Las cadenas sin precio propio en la zona aparecen con su precio "web" (alcance = 'web').
--   · Suma el precio anterior (misma cadena y zona), el sugerido vigente y el diferencial.
create or replace function precios_del_dia(p_fecha date default null, p_zona text default 'web')
returns table (fecha date, retailer_id text, retailer text, zona_id text, zona text, alcance text, ean text,
               producto text, marca text, tipo_marca text, fabricante text, variedad text, segmento text,
               gramaje_g numeric, tamano text, precio numeric, precio_lista numeric, en_promo boolean,
               promo_texto text, disponible boolean, precio_kg numeric, url text, imagen_url text,
               precio_anterior numeric, var_pct numeric, sugerido numeric, dif_sugerido_pct numeric)
language sql stable security definer set search_path = public as $$
  with d as (
    select coalesce(p_fecha, (select max(x.fecha) from precios x)) as f
  ), con_zona as (
    select distinct x.retailer_id from precios x, d where x.fecha = d.f and x.zona_id = p_zona
  ), base as (
    select v.*, case when v.zona_id = p_zona then 'zona' else 'web' end as alcance
      from v_precios v, d
     where v.fecha = d.f
       and (v.zona_id = p_zona
            or (v.zona_id = 'web' and v.retailer_id not in (select c.retailer_id from con_zona c)))
  )
  select b.fecha, b.retailer_id, b.retailer, b.zona_id, b.zona, b.alcance, b.ean, b.producto, b.marca,
         b.tipo_marca, b.fabricante, b.variedad, b.segmento, b.gramaje_g, b.tamano, b.precio, b.precio_lista,
         b.en_promo, b.promo_texto, b.disponible, b.precio_kg, b.url, b.imagen_url,
         prev.precio,
         case when prev.precio > 0 and b.precio > 0 then round((b.precio / prev.precio - 1) * 100, 2) end,
         s.sugerido,
         case when s.sugerido > 0 and b.precio > 0 then round((b.precio / s.sugerido - 1) * 100, 2) end
    from base b
    left join lateral (
         select x.precio from precios x
          where x.retailer_id = b.retailer_id and x.zona_id = b.zona_id and x.ean = b.ean
            and x.fecha < b.fecha and x.precio > 0
          order by x.fecha desc limit 1) prev on true
    left join lateral (
         select sugerido_vigente(b.ean, p_zona, b.retailer_id, b.fecha) as sugerido) s on true;
$$;

-- Compatibilidad (mail, analista): último día, zona "web".
create view v_precios_hoy as select * from precios_del_dia(null, 'web');

-- Días y zonas con datos (selector de fecha del dashboard)
create view v_fechas as
select p.fecha, p.zona_id, count(*) as registros, count(distinct p.retailer_id) as cadenas
  from precios p group by p.fecha, p.zona_id;

-- Índice de precios por cadena y zona: 100 = mediana del mercado para el mismo EAN ese día en esa zona
-- (solo productos PepsiCo presentes en 3 o más cadenas).
create view v_indice_retailer as
with base as (
  select p.fecha, p.zona_id, p.retailer_id, p.ean, p.precio
    from precios p
    left join productos pr on pr.ean = p.ean
    left join marcas m on m.nombre = pr.marca
   where p.precio > 0 and coalesce(m.tipo, 'pepsico') = 'pepsico'
), med as (
  select fecha, zona_id, ean, percentile_cont(0.5) within group (order by precio) as mediana
    from base group by fecha, zona_id, ean having count(*) >= 3
)
select b.fecha, b.zona_id, b.retailer_id, r.nombre as retailer,
       round(avg(b.precio / m.mediana)::numeric * 100, 1) as indice,
       count(*) as skus_comparables
  from base b join med m using (fecha, zona_id, ean) join retailers r on r.id = b.retailer_id
 group by b.fecha, b.zona_id, b.retailer_id, r.nombre;

-- Igual que el índice, pero para una zona completando con el precio "web" de las cadenas sin dato zonal.
create or replace function indice_por_zona(p_zona text default 'web', p_desde date default (current_date - 60))
returns table (fecha date, retailer_id text, retailer text, indice numeric, skus_comparables bigint)
language sql stable security definer set search_path = public as $$
  with con_zona as (
    select distinct x.fecha, x.retailer_id from precios x where x.zona_id = p_zona and x.fecha >= p_desde
  ), base as (
    select p.fecha, p.retailer_id, p.ean, p.precio
      from precios p
      left join productos pr on pr.ean = p.ean
      left join marcas m on m.nombre = pr.marca
     where p.precio > 0 and p.fecha >= p_desde and coalesce(m.tipo, 'pepsico') = 'pepsico'
       and (p.zona_id = p_zona
            or (p.zona_id = 'web' and not exists (
                  select 1 from con_zona c where c.fecha = p.fecha and c.retailer_id = p.retailer_id)))
  ), med as (
    select b.fecha, b.ean, percentile_cont(0.5) within group (order by b.precio) as mediana
      from base b group by b.fecha, b.ean having count(*) >= 3
  )
  select b.fecha, b.retailer_id, r.nombre,
         round(avg(b.precio / m.mediana)::numeric * 100, 1), count(*)
    from base b join med m on m.fecha = b.fecha and m.ean = b.ean
    join retailers r on r.id = b.retailer_id
   group by b.fecha, b.retailer_id, r.nombre
   order by b.fecha;
$$;

create view v_tendencia as
select p.fecha, p.zona_id, p.retailer_id, r.nombre as retailer, pr.marca,
       count(*) as skus,
       round(avg(p.precio_kg), 0) as precio_kg_prom,
       round(100.0 * count(*) filter (where p.en_promo) / count(*), 1) as pct_promo,
       count(*) filter (where not p.disponible) as sin_stock
  from precios p join retailers r on r.id = p.retailer_id
  left join productos pr on pr.ean = p.ean
 group by p.fecha, p.zona_id, p.retailer_id, r.nombre, pr.marca;

create view v_alertas as
select a.*, r.nombre as retailer, z.nombre as zona, pr.marca,
       coalesce(m.tipo, 'pepsico') as tipo_marca, pr.gramaje_g
  from alertas a
  join retailers r on r.id = a.retailer_id
  join zonas z     on z.id = a.zona_id
  left join productos pr on pr.ean = a.ean
  left join marcas m     on m.nombre = pr.marca;

-- Diferencial contra el sugerido, resumido por segmento (mail, analista).
create or replace function diferencial_por_segmento(p_fecha date default null, p_zona text default 'web')
returns table (segmento text, retailer text, skus bigint, dif_prom_pct numeric, sobre_sugerido bigint, bajo_sugerido bigint)
language sql stable security definer set search_path = public as $$
  select coalesce(d.segmento, 'Sin segmento'), d.retailer, count(*),
         round(avg(d.dif_sugerido_pct), 1),
         count(*) filter (where d.dif_sugerido_pct >  1),
         count(*) filter (where d.dif_sugerido_pct < -1)
    from precios_del_dia(p_fecha, p_zona) d
   where d.dif_sugerido_pct is not null and d.tipo_marca = 'pepsico'
   group by 1, 2 order by 1, 2;
$$;

-- ---------- 9. Resumen diario (mail): los cambios iguales en varias zonas se juntan en una línea ----------
create or replace function resumen_diario(p_fecha date, p_umbral numeric default 1.0)
returns jsonb language plpgsql as $$
declare r jsonb; n_zonas integer;
begin
  perform generar_alertas(p_fecha, p_umbral);
  select count(distinct zona_id) into n_zonas from precios where fecha = p_fecha;

  select jsonb_build_object(
    'fecha',          p_fecha,
    'fecha_anterior', (select max(fecha) from precios where fecha < p_fecha),
    'skus',           (select count(distinct ean) from precios where fecha = p_fecha),
    'registros',      (select count(*) from precios where fecha = p_fecha),
    'zonas',          n_zonas,
    'por_retailer',   '[]'::jsonb,
    'indice',         coalesce((
        select jsonb_agg(jsonb_build_object('retailer', retailer, 'indice', indice,
                                            'skus_comparables', skus_comparables) order by indice)
          from (select retailer, round(avg(indice), 1) as indice, max(skus_comparables) as skus_comparables
                  from v_indice_retailer where fecha = p_fecha group by retailer) i), '[]'::jsonb),
    'vs_sugerido',    coalesce((
        select jsonb_agg(to_jsonb(d)) from diferencial_por_segmento(p_fecha, 'web') d), '[]'::jsonb)
  ) into r;

  with g as (
    select a.tipo, a.retailer, a.marca, a.nombre, a.precio_anterior, a.precio_nuevo, a.variacion_pct, a.detalle,
           count(*) as n, string_agg(a.zona, ', ' order by a.zona) as zonas
      from v_alertas a
     where a.fecha = p_fecha
     group by a.tipo, a.retailer, a.marca, a.nombre, a.ean, a.precio_anterior, a.precio_nuevo, a.variacion_pct, a.detalle
  )
  select r || jsonb_build_object(
    'conteo',  coalesce((select jsonb_object_agg(tipo, c) from (select tipo, count(*) c from g group by tipo) s), '{}'::jsonb),
    'alertas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'tipo', tipo,
                 'retailer', retailer || case when n_zonas <= 1 then ''
                                              when n >= n_zonas then ' · todas las zonas'
                                              else ' · ' || zonas end,
                 'marca', marca, 'nombre', nombre,
                 'precio_anterior', precio_anterior, 'precio_nuevo', precio_nuevo,
                 'variacion_pct', variacion_pct, 'detalle', detalle)
                 order by tipo, abs(coalesce(variacion_pct, 0)) desc)
          from g), '[]'::jsonb))
  into r;

  r := jsonb_set(r, '{por_retailer}', coalesce((
        select jsonb_agg(x order by x->>'retailer') from (
          select jsonb_build_object('retailer', r2.nombre, 'skus', count(distinct p.ean),
                   'zonas', count(distinct p.zona_id),
                   'en_promo', count(distinct p.ean) filter (where p.en_promo),
                   'sin_stock', count(distinct p.ean) filter (where not p.disponible)) as x
            from precios p join retailers r2 on r2.id = p.retailer_id
           where p.fecha = p_fecha group by r2.nombre) s), '[]'::jsonb));
  return r;
end $$;

-- ---------- 10. Reporte semanal (suma zona, tipo de marca y sugerido) ----------
drop function if exists comparativo_semanal(date);
create or replace function comparativo_semanal(p_fecha date)
returns table (marca text, tipo_marca text, producto text, ean text, gramaje_g numeric, segmento text, tamano text,
               retailer text, zona text, precio_hoy numeric, precio_hace_7d numeric, var_7d_pct numeric,
               precio_kg numeric, sugerido numeric, dif_sugerido_pct numeric,
               en_promo boolean, promo_texto text, disponible boolean, url text)
language sql stable as $$
  with f as (
    select max(fecha) as f from precios where fecha <= p_fecha
  ), hoy as (
    select v.* from v_precios v, f where v.fecha = f.f
  ), ref as (
    select distinct on (x.retailer_id, x.zona_id, x.ean) x.retailer_id, x.zona_id, x.ean, x.precio
      from precios x
     where x.fecha <= p_fecha - 7 and x.fecha >= p_fecha - 14 and x.precio > 0
     order by x.retailer_id, x.zona_id, x.ean, x.fecha desc
  )
  select h.marca, h.tipo_marca, h.producto, h.ean, h.gramaje_g, h.segmento, h.tamano, h.retailer, h.zona,
         h.precio, ref.precio,
         case when ref.precio > 0 and h.precio > 0 then round((h.precio / ref.precio - 1) * 100, 1) end,
         h.precio_kg, s.sug,
         case when s.sug > 0 and h.precio > 0 then round((h.precio / s.sug - 1) * 100, 1) end,
         h.en_promo, h.promo_texto, h.disponible, h.url
    from hoy h
    left join ref on ref.retailer_id = h.retailer_id and ref.zona_id = h.zona_id and ref.ean = h.ean
    left join lateral (select sugerido_vigente(h.ean, h.zona_id, h.retailer_id, h.fecha) as sug) s on true
   order by 1, 3, 8, 9;
$$;

-- ---------- 11. Seguridad ----------
alter table zonas             enable row level security;
alter table retailer_zonas    enable row level security;
alter table equivalencias     enable row level security;
alter table tamanos           enable row level security;
alter table precios_sugeridos enable row level security;

do $$
declare t text;
begin
  foreach t in array array['zonas','retailer_zonas','equivalencias','tamanos','precios_sugeridos'] loop
    execute format('drop policy if exists lectura_publica on %I', t);
    execute format('create policy lectura_publica on %I for select to anon using (true)', t);
    if exists (select 1 from pg_roles where rolname = 'analista_ro') then
      execute format('drop policy if exists lectura_analista on %I', t);
      execute format('create policy lectura_analista on %I for select to analista_ro using (true)', t);
    end if;
  end loop;
  if exists (select 1 from pg_roles where rolname = 'analista_ro') then
    grant select on all tables in schema public to analista_ro;
  end if;
end $$;

grant select on zonas, retailer_zonas, tamanos, precios_sugeridos to anon;
grant select on v_precios, v_precios_hoy, v_indice_retailer, v_tendencia, v_alertas, v_fechas, v_productos to anon;
grant execute on function precios_del_dia(date, text), indice_por_zona(text, date),
                          diferencial_por_segmento(date, text), sugerido_vigente(text, text, text, date) to anon;
-- Las funciones que escriben quedan sólo para n8n (conexión Postgres).
revoke execute on function cargar_sugeridos(jsonb, date, text) from public, anon;
revoke execute on function ingestar_precios(jsonb, date, jsonb, jsonb) from public, anon;

notify pgrst, 'reload schema';
