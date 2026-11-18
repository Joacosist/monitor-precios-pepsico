# Monitor de Precios · Snacks PepsiCo

Sistema de agentes en **n8n** que todos los días releva los precios de **Lay's, Doritos, 3D, Cheetos, Tostitos, Twistos y Pehuamar** (todas las variedades y gramajes) en **Carrefour, Jumbo, Disco, Vea, Día, ChangoMás y Coto**. Los guarda en **Supabase**, detecta cambios, te manda un **mail a las 9:00** y los muestra en un **dashboard** con descarga a Excel y chat con IA.

```
 7:47  ① Recolector ──► Supabase (precios)
 8:31  ② Normalizador (Claude Haiku) ──► productos limpios (variedad, segmento, gramaje)
 9:00  ③ Alertas + mail diario (Claude Sonnet) ──► Outlook
 Lun   ⑤ Reporte semanal + Excel adjunto ──► Outlook
 24/7  ④ Analista (chat) ◄── Dashboard (HTML) ──► Supabase (lectura)
```

## Qué hay en esta carpeta

| Archivo | Para qué |
|---|---|
| `sql/01_esquema.sql` | Tablas, funciones y vistas. Se pega en Supabase. |
| `sql/02_rol_analista.sql` | Usuario de solo lectura para el agente de chat. |
| `sql/03_mejoras_v2.sql` | Zonas, competencia, tamaños, precio sugerido e historial. Se corre después del 01. |
| `n8n/1_recolector.json` … `6_lector_precio_sugerido.json` | Los 6 workflows para importar en n8n. |
| `dashboard/index.html` | El dashboard (una sola página). |

## Los 5 agentes

1. **Recolector**: consulta la API pública de catálogo VTEX de Carrefour, Jumbo, Disco, Vea, Día y ChangoMás, y el buscador de Coto Digital (que devuelve JSON). Filtra sólo las 7 marcas, toma precio actual, precio "antes", promo, stock, gramaje y EAN.
2. **Normalizador (IA)**: Claude Haiku limpia los nombres ("Nachos sabor a queso Doritos 200 g." pasa a "Doritos Queso 200g") y asigna variedad, segmento y gramaje. Así el mismo producto se compara igual en todas las cadenas.
3. **Alertas + mail diario**: compara contra la captura anterior y detecta subas, bajas, promos nuevas o terminadas, quiebres de stock, reposiciones y SKUs nuevos. Claude Sonnet escribe "lo importante" del día y n8n manda el mail.
4. **Analista (chat)**: un agente con Claude que responde preguntas desde el dashboard consultando la base (por ejemplo, *"¿dónde está más barato Doritos 77g?"*).
5. **Reporte semanal**: todos los lunes, un análisis de la semana con un Excel adjunto (producto × cadena, variación a 7 días).

---

## Novedades v2 (noviembre 2026)

| Qué | Cómo funciona |
|---|---|
| **Precios por zona** | Tabla `zonas` (provincias + "web"). El Recolector guarda el precio web general y, para las cadenas que cambian el precio según la ubicación, el precio en cada zona activa. El dashboard tiene selector de **Zona** y la pestaña **Comparar zonas**. |
| **La Anónima** | Nueva cadena. No publica el EAN en el listado: se lee una vez de la ficha de cada producto (tabla `equivalencias`). |
| **Competencia** | 5 Hispanos, Pringles, Krachitos, Saladix y marcas propias de las cadenas (tabla `marcas`, columna `tipo`). Pestaña **Competencia**: precio por kilo por segmento y tamaño (medium / large bag), con apertura por marca y producto. |
| **Precio sugerido** | Botón **⬆ Precio sugerido**: subís el Excel/CSV de PepsiCo, se empareja por EAN (y con IA las filas sin EAN) y se guarda en `precios_sugeridos`. Pestaña **Sugerido vs. cadena** con el diferencial por segmento. |
| **Días anteriores** | Selector de **Día** con flechas para moverse entre los días con datos. |

### Cómo actualizar (≈ 15 minutos)

1. **Supabase → SQL Editor**: pegá todo `sql/03_mejoras_v2.sql` y tocá **Run**. No borra nada: los precios que ya tenías quedan en la zona "web".
2. **n8n**: importá de nuevo los workflows `1` a `5` (reemplazan a los anteriores: desactivá o borrá los viejos) y el nuevo `6_lector_precio_sugerido.json`. Volvé a elegir las credenciales en los nodos con ⚠ y a cargar `DESTINATARIO` en "Configuración" (workflows 3 y 5).
3. **Workflow 6**: en "Validar pedido" cambiá `CLAVE`, activalo y copiá la Production URL del webhook.
4. **Dashboard**: reemplazá `dashboard/index.html`. En `config.local.js` agregá `WEBHOOK_SUGERIDOS_LOCAL` y `CLAVE_SUGERIDOS_LOCAL` (ver `config.example.js`). Sin eso el sugerido se guarda sólo en tu navegador.
5. Ejecutá a mano **1 · Recolector** y después **2 · Normalizador** (varias veces la primera vez: hay muchas marcas nuevas). En el último nodo del Recolector, `por_zona` muestra cuántos precios se guardaron por cadena y zona, y `sin_cobertura` las zonas donde una cadena no entrega.

### Zonas

- Vienen **activas** CABA, GBA (Pilar), Buenos Aires interior, Córdoba, Santa Fe, Mendoza, Neuquén y Tucumán. El resto de las provincias está cargado pero apagado: `update zonas set activo = true where id = 'salta';`
- Cada zona usa un **código postal de referencia** (columna `cp`). Podés cambiarlo, o agregar zonas más finas (por ciudad) insertando filas.
- Cómo regionaliza cada cadena (columna `retailers.modo_zona`):
  - **Carrefour, ChangoMás, Día** (`cp`): el precio depende del código postal. Funciona solo.
  - **Jumbo, Disco, Vea** (`sc`): el precio depende de la sucursal elegida. Hay que cargar el número de sucursal de cada zona en `retailer_zonas.sc` (es el valor `sc=` que usa el sitio al elegir una tienda). Hasta entonces se guarda sólo su precio web.
  - **Coto, La Anónima** (`ninguno`): se guarda sólo el precio web. Coto Digital publica una única lista de precios online.
- En el dashboard, si una cadena no tiene precio propio para la zona elegida se muestra su precio web con la marca **web**.

### Competencia y tamaños

- Sumar una marca: una fila en `marcas` con `tipo = 'competencia'`. `termino` admite varias búsquedas separadas por `|`; `alias` son otros nombres con los que las cadenas publican la marca.
- Las marcas propias (`tipo = 'marca_propia'`) sólo se buscan en su cadena (`solo_retailer`) y sólo se guardan los snacks. Los `alias` cargados son una primera aproximación: revisalos después de la primera corrida.
- Rangos de tamaño en la tabla `tamanos`: Single (< 60 g), Medium bag (60 a 120 g), Large bag (121 a 300 g), XL (> 300 g).
- "Ponderado por presencia": no hay datos de ventas, así que un producto publicado en 6 cadenas pesa 6 veces en el precio por kilo promedio.

### Precio sugerido

- El archivo necesita al menos una columna de **precio** y una de **EAN** o **descripción**. Opcional: una columna de zona (si un precio vale sólo para una zona).
- Las filas con EAN se emparejan sin IA. Las que no tienen EAN se pueden emparejar con Claude Haiku (botón ✨); conviene revisarlas antes de guardar.
- Cada carga tiene una fecha "vigente desde": al mirar un día anterior se usa el sugerido que regía ese día.

---

## Puesta en marcha (≈ 30 minutos)

### Paso 1 · Supabase (base de datos)

1. Entrá a [supabase.com](https://supabase.com) y creá un proyecto gratis (región: São Paulo). **Guardá la contraseña de la base.**
2. Andá a **SQL Editor → New query**, pegá todo `sql/01_esquema.sql` y tocá **Run**.
3. Abrí `sql/02_rol_analista.sql`, cambiá `CAMBIAR_ESTA_CLAVE` por una contraseña tuya, pegalo y tocá **Run**.
4. Anotá estos datos de **Project Settings**:
   - **Connect → Session pooler**: host (`aws-0-sa-east-1.pooler.supabase.com`), puerto `5432`, usuario (`postgres.xxxxxxxx`) y base `postgres`.
   - **API**: la **Project URL** y la clave **anon public**.

> Usá el **Session pooler** y no la conexión directa: la directa es IPv6 y muchos servidores de n8n no la soportan.

### Paso 2 · Credenciales en n8n

En n8n, andá a **Credentials → Add credential** y creá estas cinco:

| Nombre sugerido | Tipo | Datos |
|---|---|---|
| `Supabase Postgres` | **Postgres** | Host y usuario del pooler, base `postgres`, la contraseña del proyecto, puerto 5432, **SSL: Require** |
| `Supabase solo lectura` | **Postgres** | Igual, pero con usuario `analista_ro.xxxxxxxx` (el mismo sufijo del pooler) y la clave del paso 1.3 |
| `Anthropic header` | **Header Auth** | Name: `x-api-key` · Value: tu API key de [console.anthropic.com](https://console.anthropic.com) |
| `Anthropic` | **Anthropic API** | La misma API key (la usa el agente de chat) |
| `Outlook` | **Microsoft Outlook OAuth2** | Iniciar sesión con tu cuenta |

> **Sobre Outlook de PepsiCo:** es muy probable que IT tenga que aprobar la conexión ("Need admin approval"). Si te frena, en los workflows 3 y 5 hay un nodo **"Enviar por SMTP (alternativa)"** desactivado. Activalo, desactivá el de Outlook y mandá el mail **desde** una cuenta personal (por ejemplo, Gmail con [contraseña de aplicación](https://myaccount.google.com/apppasswords)) **hacia** tu mail de PepsiCo.

### Paso 3 · Importar los workflows

Para cada archivo de `n8n/`: **Workflows → ⋯ → Import from file**. Después, en cada nodo con ⚠ elegí la credencial que corresponde:

- Nodos Postgres (Config, Guardar…, Resumen…): `Supabase Postgres`.
- Nodos "Claude" (HTTP Request): `Anthropic header`.
- Workflow 4: "Claude Sonnet" usa `Anthropic` y "consultar_base" usa `Supabase solo lectura`.
- Nodos de mail: `Outlook`.

**Editá el nodo "Configuración"** en los workflows 3 y 5: poné tu mail en `DESTINATARIO` (y el link del dashboard cuando lo tengas).

### Paso 4 · Primera prueba (en orden)

1. Abrí **1 · Recolector** y tocá **Execute workflow**. Tarda entre 1 y 3 minutos. El último nodo tiene que mostrar `filas_guardadas` > 0. En Supabase → Table editor → `precios` ya vas a ver datos.
2. **2 · Normalizador → Execute** (hasta 150 productos por corrida; si hay más, ejecutalo de nuevo).
3. **3 · Alertas y mail → Execute**: te llega el mail. El primer día dice "Primera captura", porque las alertas aparecen a partir del segundo día.
4. **4 · Analista**: activalo con el switch **Active** y copiá la **Production URL** del nodo Webhook.
5. Activá también los workflows 1, 2, 3 y 5. A partir de ahí corren solos todos los días.

### Paso 5 · Dashboard

1. Abrí `dashboard/index.html` con un editor de texto (Bloc de notas sirve) y completá las 3 líneas del principio:
   ```js
   const SUPABASE_URL      = 'https://xxxxxxxx.supabase.co';
   const SUPABASE_ANON_KEY = 'eyJhbGciOi...';     // anon public (es pública, no pasa nada)
   const WEBHOOK_ANALISTA  = 'https://tu-n8n/webhook/analista-precios';
   ```
2. Hacé doble clic para abrirlo en el navegador. Sin completar nada, muestra **datos de demostración** (sirve para presentar).
3. Para tener un link: entrá a [app.netlify.com/drop](https://app.netlify.com/drop) y arrastrá la carpeta `dashboard`. Ese link lo pegás en `LINK_DASHBOARD` de los workflows 3 y 5.

El dashboard tiene filtros por marca, segmento, cadena y búsqueda; KPIs; el índice de precios por cadena; el feed de cambios; una matriz producto × cadena (verde = más barato, rojo = más caro, PROMO, ✕ = sin stock); historial por producto (tocá una fila); el botón **Descargar Excel** (4 hojas: precios, matriz, cambios e índice); y el chat con el analista.

---

## Cómo leer los datos

- **Precio**: el de la góndola online con la rebaja directa aplicada. Las promos tipo "2do al 70%" no cambian el precio unitario: quedan marcadas en `promo_texto`.
- **Índice de precios**: para cada producto que está en 3 o más cadenas se calcula la mediana del mercado (= 100). Una cadena con índice 95 está, en promedio, 5% más barata.
- **Quiebre**: el producto figura sin stock online o dejó de aparecer en el sitio. Si una cadena entera falla un día, no se generan alertas falsas para esa cadena.
- Los precios online pueden diferir de los de una sucursal física puntual.

## Personalizar

- **Sumar o quitar cadenas/marcas**: editá las tablas `retailers` y `marcas` en Supabase (columna `activo`). No hace falta tocar n8n. Cualquier cadena con VTEX se suma con `plataforma = 'vtex'` y su dominio.
- **Sensibilidad de las alertas**: `UMBRAL_VARIACION_PCT` en el nodo Configuración (por defecto 1%).
- **Horarios**: el nodo programado de cada workflow (zona horaria Buenos Aires).

## Si algo falla

| Síntoma | Qué revisar |
|---|---|
| `filas_guardadas: 0` | Mirá la salida de "Parsear y filtrar" → `errores`. Si dice "no es JSON", el sitio bloqueó temporalmente: probá más tarde o subí `batchInterval` en "Consultar sitios". |
| Error de conexión a Postgres | Usá el **Session pooler** (no "Direct connection") y SSL "Require". |
| El nodo Claude da 401 | La credencial Header Auth tiene que llamarse exactamente `x-api-key`. |
| El modelo no existe | En el nodo, cambiá `model` por uno disponible en tu cuenta (por ejemplo, `claude-sonnet-5-5` o `claude-haiku-5-5`). |
| Outlook pide aprobación de administrador | Usá el nodo SMTP alternativo (ver Paso 2). |
| El chat dice "no está conectado" | Falta `WEBHOOK_ANALISTA` en el dashboard o el workflow 4 no está activo. |

**Costo estimado de IA**: menos de USD 1 por mes (Haiku normaliza sólo productos nuevos; Sonnet escribe 1 mail por día y responde el chat).
