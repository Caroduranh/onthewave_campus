# On the Wave · Campus

Tu propia plataforma de estudiantes, estilo Canvas: cursos, inscripciones, tareas semanales y journals con texto, audio y video de YouTube.

- **`index.html`**: la app completa (un solo archivo).
- **`wave.png`**: el logo de On the Wave (el mismo de tu página). Súbelo junto a `index.html`.
- **`supabase/schema.sql`**: la base de datos, con la seguridad ya configurada.

Si abres `index.html` sin configurar nada, arranca en **modo demo** con datos de ejemplo y un botón para ver la app como profe o como estudiante.

---

## Instalación (unos 20 minutos)

### 1. Crea el proyecto en Supabase
1. En supabase.com, crea un **New project** llamado `on-the-wave` (aparte de Grid-lab).
2. Ve a **SQL Editor → New query**, pega todo el contenido de `supabase/schema.sql` y dale **Run**.
   Esto crea las tablas, la seguridad y el espacio para los audios (bucket `journal`).

### 2. Configura el login
En **Authentication**:
- **Sign In / Providers → Email**: deja activado **Confirm email**. Esto es importante: así nadie puede crear una cuenta con el email de otra persona.
- **URL Configuration**: en **Site URL** pon la dirección donde va a vivir el campus (paso 4), por ejemplo `https://caroduranh.github.io/campus/`. Agrega esa misma URL en **Redirect URLs**.
- **Emails → SMTP Settings**: conecta **Resend**, igual que en GridJam (puedes usar un remitente como `campus@…`). Sin esto, Supabase solo deja enviar unos pocos emails por hora.
- (Opcional) **Emails → Templates**: traduce al español los emails de "Confirm signup" y "Reset password".

### 3. Conecta la app
En **Project Settings → API**, copia la **Project URL** y la clave **anon / publishable**. Pégalas al inicio de `index.html`:

```js
const CONFIG = {
  SUPABASE_URL: 'https://xxxx.supabase.co',
  SUPABASE_ANON_KEY: 'eyJ…',
  TEACHER_NAME: 'Caro'
};
```
La clave anon es pública: no pasa nada si está en GitHub, porque la seguridad está en la base de datos. **Nunca** pegues la `service_role`.

### 4. Publica
Crea un repo en GitHub (por ejemplo `campus`), sube `index.html` y `wave.png` y activa **Settings → Pages**. Queda en `caroduranh.github.io/campus`. Cuando compres el dominio de On the Wave, puedes apuntar `campus.tudominio.com` a ese repo, igual que hiciste con play.gridjam.app.
Si cambias de URL, actualiza también la **Site URL** en Supabase.

### 5. Crea tu cuenta de profe
Abre el campus y crea tu cuenta con `info@caroduran.co`. Como tu email ya está en la lista del equipo (tabla `staff`), no necesitas código y quedas como profe automáticamente. Hazlo apenas corras el SQL.

Para que Cindy (u otra profe) también entre como profe, antes de que se registre corre en el SQL Editor:
```sql
insert into public.staff values ('email-de-cindy@ejemplo.com');
```
Si ya tenía cuenta, corre además:
```sql
update public.profiles set role = 'teacher' where email = 'email-de-cindy@ejemplo.com';
```

---

## Cómo se usa

**Tú (profe)**
1. **+ Nuevo curso**, por ejemplo "Curso DJ · Diciembre".
2. En **Estudiantes** está el **código de inscripción** del curso (por ejemplo `OTW-DJ7K2P`). Toca **Copiar invitación** y pégala en WhatsApp: el mensaje trae el link con el código ya puesto. Con ese código crean su cuenta y quedan inscritos en ese curso.
   - **Pausar código**: nadie más se puede inscribir (útil cuando el grupo se llena).
   - **Generar código nuevo**: si el código se compartió de más, el anterior deja de servir. Los que ya están inscritos no se afectan.
   - También puedes inscribir por email: esa persona se registra sin código.
3. En **Tareas**, crea la tarea de la semana. Queda como **borrador** hasta que la publiques.
4. Para no empezar de cero cada semana, usa **Duplicar**: copia la tarea a la semana siguiente o a otro curso, como cuando duplicas tu plantilla de Practice Journal en Canvas.
5. En el inicio, **Por revisar** te muestra cada journal nuevo. Puedes responder con texto o con un audio que grabes ahí mismo.

**Estudiantes**
- Solo pueden crear cuenta con un código válido o si ya los inscribiste por email. Cualquier otra persona es rechazada por la base de datos (no solo por la pantalla).
- Si después se inscriben a otro curso, escriben el nuevo código en su inicio, en **¿Te inscribiste a otro curso?**.
- Ven sus cursos, lo que tienen **pendiente** y cuándo hay **nuevo feedback**.
- Cada tarea es un hilo privado entre el estudiante y tú. Pueden escribir, grabar o subir un audio, y pegar el link de su video de YouTube.
- **Videos por YouTube**: suben el video como **Oculto** (solo lo ve quien tenga el link), pegan el link y el video aparece listo para ver dentro del journal. En la app hay una guía de 4 pasos para hacerlo. Así no gastas espacio de Supabase y los videos cargan rápido en cualquier celular.

---

## Bueno saber
- **Plan gratis de Supabase**: 1 GB para archivos y 50 MB por archivo. Como en Supabase solo se guardan audios, alcanza para miles de entregas. Si el campus crece, el plan Pro ($25/mes) da 100 GB.
- Los proyectos gratis de Supabase **se pausan si pasan 7 días sin uso**. Durante los cursos no pasa, pero en vacaciones puede pausarse. Se reactiva desde el dashboard.
- Si quitas a un estudiante de un curso, sus journals se guardan. Si vuelves a inscribirlo, los recupera.
- **Archivar** un curso lo quita del inicio de los estudiantes sin borrar nada.
