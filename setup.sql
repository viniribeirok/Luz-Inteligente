-- Rode este arquivo inteiro UMA vez no Supabase: SQL Editor > New query > Run

-- ============ 1) LUZES (6 cômodos) ============
-- Comando desejado: o site escreve, o ESP32 lê
create table comando (
  id text primary key,                       -- identificador usado pelo ESP32
  nome text not null,
  modo text not null default 'manual' check (modo in ('auto', 'manual')),
  luz boolean not null default false,
  tempo_auto_seg int not null default 120          -- tempo aceso após o último movimento
    check (tempo_auto_seg between 5 and 3600),
  atualizado_por text,
  atualizado_em timestamptz default now()
);

-- Estado real: o ESP32 escreve, o site lê
create table status (
  id text primary key references comando(id),
  luz boolean not null default false,
  movimento boolean not null default false,
  visto_em timestamptz default now()
);

insert into comando (id, nome) values
  ('quarto1',  'Quarto 1'),
  ('quarto2',  'Quarto 2'),
  ('banheiro', 'Banheiro'),
  ('garagem',  'Garagem'),
  ('cozinha',  'Cozinha'),
  ('sala',     'Sala de Estar');

insert into status (id) select id from comando;

-- ============ 2) PERFIS (aprovação de cadastros) ============
create table perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  situacao text not null default 'pendente'
    check (situacao in ('pendente', 'aprovado', 'recusado')),
  admin boolean not null default false,
  criado_em timestamptz default now()
);

-- Funções auxiliares (security definer evita loop nas regras)
create function sou_aprovado() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from perfis where id = auth.uid() and situacao = 'aprovado')
$$;

create function sou_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from perfis
                 where id = auth.uid() and admin and situacao = 'aprovado')
$$;

-- Todo novo cadastro entra como "pendente"
create function novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into perfis (id, email) values (new.id, new.email);
  return new;
end $$;

create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function novo_usuario();

-- Usuários que já existiam antes deste script viram perfis pendentes
insert into perfis (id, email)
select id, email from auth.users
on conflict (id) do nothing;

-- ============ 3) SEGURANÇA (RLS) ============
alter table comando enable row level security;
alter table status  enable row level security;
alter table perfis  enable row level security;

-- Todos leem o comando (o ESP32 usa a chave anon); só APROVADOS alteram
create policy "ler comando" on comando for select using (true);
create policy "so aprovados alteram comando" on comando
  for update to authenticated using (sou_aprovado()) with check (sou_aprovado());

-- O dispositivo atualiza o status; todos podem ler
create policy "ler status" on status for select using (true);
create policy "dispositivo atualiza status" on status
  for update using (true) with check (true);

-- Cada um vê o próprio perfil; o admin vê todos e decide as aprovações
create policy "ver proprio perfil ou admin ve todos" on perfis
  for select to authenticated using (id = auth.uid() or sou_admin());
create policy "admin altera perfis" on perfis
  for update to authenticated using (sou_admin()) with check (sou_admin());

-- Só o ADMIN pode alterar o tempo do modo automático (usuários aprovados comuns não)
create function so_admin_muda_tempo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tempo_auto_seg is distinct from old.tempo_auto_seg
     and auth.uid() is not null and not sou_admin() then
    raise exception 'Somente o administrador pode alterar o tempo do modo automático';
  end if;
  return new;
end $$;

create trigger proteger_tempo
  before update on comando
  for each row execute function so_admin_muda_tempo();

-- ============ 4) TEMPO REAL ============
alter publication supabase_realtime add table comando, status;

-- ============ 5) SEU USUÁRIO ADMIN ============
-- Depois de criar a sua conta no site, troque pelo seu e-mail e rode:
-- update perfis set situacao = 'aprovado', admin = true where email = 'seu@email.com';
