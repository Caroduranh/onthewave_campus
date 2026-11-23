-- =====================================================================
--  On the Wave · Campus  —  esquema de base de datos para Supabase
--  Pega TODO este archivo en Supabase → SQL Editor → Run (una sola vez).
-- =====================================================================

-- ---------- PERFILES -------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  email      text unique not null,
  full_name  text not null default '',
  role       text not null default 'student' check (role in ('student','teacher')),
  created_at timestamptz not null default now()
);

-- Equipo de On the Wave: estos emails se registran sin código y quedan como profes.
-- Para agregar a alguien más:  insert into public.staff values ('email@ejemplo.com');
create table if not exists public.staff (email text primary key);
alter table public.staff enable row level security;  -- sin políticas: nadie la lee desde la app
insert into public.staff values ('info@caroduran.co') on conflict do nothing;

-- ¿El usuario actual es profe?
create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher');
$$;

-- ---------- CURSOS E INSCRIPCIONES ----------------------------------
-- Código de inscripción: OTW- + 6 caracteres (sin letras que se confunden como O/0, I/1)
create or replace function public.gen_join_code()
returns text language plpgsql volatile as $$
declare chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; c text := 'OTW-';
begin
  for i in 1..6 loop c := c || substr(chars, 1 + floor(random() * length(chars))::int, 1); end loop;
  return c;
end $$;

create table if not exists public.courses (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text not null default '',
  color       text not null default '#D6B16A',
  archived    boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table public.courses add column if not exists join_code    text not null default public.gen_join_code();
alter table public.courses add column if not exists join_enabled boolean not null default true;
create unique index if not exists courses_join_code_idx on public.courses (upper(join_code));

-- La inscripción es por email: puedes inscribir a alguien antes de que
-- cree su cuenta; cuando se registre con ese email, verá su curso.
create table if not exists public.enrollments (
  id         uuid primary key default gen_random_uuid(),
  course_id  uuid not null references public.courses on delete cascade,
  email      text not null,
  created_at timestamptz not null default now(),
  unique (course_id, email)
);

create or replace function public.enrollment_lower_email()
returns trigger language plpgsql as $$
begin new.email := lower(trim(new.email)); return new; end $$;

drop trigger if exists enrollments_lower_email on public.enrollments;
create trigger enrollments_lower_email
  before insert or update on public.enrollments
  for each row execute function public.enrollment_lower_email();

create or replace function public.is_enrolled(c uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.enrollments e
    where e.course_id = c and e.email = lower(auth.jwt()->>'email')
  );
$$;

-- ---------- REGISTRO SOLO CON CÓDIGO --------------------------------
-- Cada registro nuevo pasa por aquí. Se acepta solo si:
--   · trae un código de curso válido (y queda inscrito en ese curso), o
--   · su email ya estaba inscrito por la profe, o
--   · su email está en la tabla staff (queda como profe).
-- Cualquier otra persona es rechazada por la base de datos.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_email  text := lower(new.email);
  v_code   text := upper(trim(coalesce(new.raw_user_meta_data->>'join_code', '')));
  v_staff  boolean;
  v_course uuid;
begin
  v_staff := exists (select 1 from public.staff where email = v_email);
  if v_code <> '' then
    select id into v_course from public.courses
    where upper(join_code) = v_code and join_enabled and not archived;
  end if;
  if not v_staff and v_course is null
     and not exists (select 1 from public.enrollments where email = v_email) then
    raise exception 'OTW_INVALID_CODE: se necesita un código de inscripción válido';
  end if;

  insert into public.profiles (id, email, full_name, role)
  values (new.id, v_email, coalesce(new.raw_user_meta_data->>'full_name', ''),
          case when v_staff then 'teacher' else 'student' end)
  on conflict (id) do nothing;

  if v_course is not null then
    insert into public.enrollments (course_id, email) values (v_course, v_email)
    on conflict do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- La pantalla de registro revisa el código antes de crear la cuenta
create or replace function public.check_join_code(p_code text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.courses
                 where upper(join_code) = upper(trim(p_code)) and join_enabled and not archived);
$$;

-- Un estudiante que ya tiene cuenta se une a otro curso con su código
create or replace function public.join_course(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_course uuid;
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  select id into v_course from public.courses
  where upper(join_code) = upper(trim(p_code)) and join_enabled and not archived;
  if v_course is null then raise exception 'OTW_INVALID_CODE: código no válido'; end if;
  insert into public.enrollments (course_id, email)
  values (v_course, lower(auth.jwt()->>'email')) on conflict do nothing;
  return v_course;
end $$;

revoke execute on function public.check_join_code(text) from public;
grant  execute on function public.check_join_code(text) to anon, authenticated;
revoke execute on function public.join_course(text) from public;
grant  execute on function public.join_course(text) to authenticated;

-- ---------- TAREAS SEMANALES ----------------------------------------
create table if not exists public.assignments (
  id           uuid primary key default gen_random_uuid(),
  course_id    uuid not null references public.courses on delete cascade,
  week         int  not null default 1,
  title        text not null,
  instructions text not null default '',
  due_date     date,
  published    boolean not null default false,
  created_at   timestamptz not null default now()
);

create or replace function public.can_see_assignment(a uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.assignments x
    where x.id = a and x.published and public.is_enrolled(x.course_id)
  );
$$;

-- ---------- JOURNALS (un hilo por tarea y estudiante) ----------------
create table if not exists public.journal_messages (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments on delete cascade,
  student_id    uuid not null references public.profiles on delete cascade,
  author_id     uuid not null references public.profiles on delete cascade,
  body          text not null default '',
  file_path     text,
  file_name     text,
  file_type     text,
  created_at    timestamptz not null default now()
);
create index if not exists journal_thread_idx
  on public.journal_messages (assignment_id, student_id, created_at);

-- ---------- SEGURIDAD (RLS) -----------------------------------------
alter table public.profiles         enable row level security;
alter table public.courses          enable row level security;
alter table public.enrollments      enable row level security;
alter table public.assignments      enable row level security;
alter table public.journal_messages enable row level security;

-- Perfiles: cada quien ve el suyo; la profe ve todos.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or public.is_teacher());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
-- Un estudiante solo puede cambiar su nombre (nunca su rol)
revoke update on public.profiles from authenticated;
grant  update (full_name) on public.profiles to authenticated;

-- Cursos
drop policy if exists courses_select on public.courses;
create policy courses_select on public.courses for select
  using (public.is_teacher() or public.is_enrolled(id));
drop policy if exists courses_teacher on public.courses;
create policy courses_teacher on public.courses for all
  using (public.is_teacher()) with check (public.is_teacher());

-- Inscripciones
drop policy if exists enroll_select on public.enrollments;
create policy enroll_select on public.enrollments for select
  using (public.is_teacher() or email = lower(auth.jwt()->>'email'));
drop policy if exists enroll_teacher on public.enrollments;
create policy enroll_teacher on public.enrollments for all
  using (public.is_teacher()) with check (public.is_teacher());

-- Tareas: estudiantes solo ven las publicadas de sus cursos
drop policy if exists assign_select on public.assignments;
create policy assign_select on public.assignments for select
  using (public.is_teacher() or (published and public.is_enrolled(course_id)));
drop policy if exists assign_teacher on public.assignments;
create policy assign_teacher on public.assignments for all
  using (public.is_teacher()) with check (public.is_teacher());

-- Mensajes del journal
drop policy if exists msg_select on public.journal_messages;
create policy msg_select on public.journal_messages for select
  using (public.is_teacher()
         or (student_id = auth.uid() and public.can_see_assignment(assignment_id)));
drop policy if exists msg_insert_student on public.journal_messages;
create policy msg_insert_student on public.journal_messages for insert
  with check (student_id = auth.uid() and author_id = auth.uid()
              and public.can_see_assignment(assignment_id));
drop policy if exists msg_delete_own on public.journal_messages;
create policy msg_delete_own on public.journal_messages for delete
  using (author_id = auth.uid());
drop policy if exists msg_teacher on public.journal_messages;
create policy msg_teacher on public.journal_messages for all
  using (public.is_teacher()) with check (public.is_teacher() and author_id = auth.uid());

-- ---------- ARCHIVOS DE AUDIO ---------------------------------------
-- Bucket privado, solo audio. 50 MB por archivo (límite del plan gratis).
-- Los videos van por YouTube (link oculto) y se ven dentro del journal.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('journal', 'journal', false, 52428800, array['audio/*'])
on conflict (id) do update
  set file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Ruta de cada archivo: <id_estudiante>/<id_tarea>/<archivo>
drop policy if exists journal_files_insert on storage.objects;
create policy journal_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'journal'
              and ((storage.foldername(name))[1] = auth.uid()::text or public.is_teacher()));
drop policy if exists journal_files_select on storage.objects;
create policy journal_files_select on storage.objects for select to authenticated
  using (bucket_id = 'journal'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_teacher()));
drop policy if exists journal_files_delete on storage.objects;
create policy journal_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'journal'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_teacher()));

-- =====================================================================
--  Listo. Crea tu cuenta en la app con info@caroduran.co (sin código):
--  quedas como profe automáticamente.
-- =====================================================================
