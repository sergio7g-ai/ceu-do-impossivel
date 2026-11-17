-- O Céu do Impossível · avaliação final (3 perguntas, 1 a 5). Corre uma vez no SQL Editor.

-- 1) a tecla A no ecrã do céu liga/desliga a avaliação de um encontro
alter table public.votacao add column if not exists aval boolean not null default false;

-- 2) respostas (privadas: ninguém lê pelo site; só o painel, com código)
create table if not exists public.avaliacoes (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  sessao      uuid not null,
  zona        smallint not null,
  perfil      text not null check (perfil in ('dirigente','caminheiro')),
  agrupamento text,
  q1 smallint not null check (q1 between 1 and 5),
  q2 smallint not null check (q2 between 1 and 5),
  q3 smallint not null check (q3 between 1 and 5),
  unique (sessao, zona, perfil)
);
alter table public.avaliacoes enable row level security;
drop policy if exists "avaliar com a avaliacao aberta" on public.avaliacoes;
create policy "avaliar com a avaliacao aberta" on public.avaliacoes for insert to anon
with check (exists (select 1 from public.votacao v where v.zona = avaliacoes.zona and v.aval));
revoke all on public.avaliacoes from anon;
grant insert on public.avaliacoes to anon;

-- 3) controlo (mesmo código CNE): aval_abrir / aval_fechar
create or replace function public.ceu_controlo(codigo text, p_zona int, acao text, p_estrelas int[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
begin
  if upper(coalesce(codigo,'')) <> 'CNE' then raise exception 'codigo errado'; end if;
  if acao = 'abrir' then
    update public.votacao set estado='aberta', estrelas=p_estrelas::smallint[], ronda=ronda+1, atualizada=now() where zona=p_zona;
  elsif acao = 'parar' then
    update public.votacao set estado='parada', atualizada=now() where zona=p_zona;
  elsif acao = 'fechar' then
    update public.votacao set estado='fechada', atualizada=now() where zona=p_zona;
  elsif acao = 'aval_abrir' then
    update public.votacao set aval=true, atualizada=now() where zona=p_zona;
  elsif acao = 'aval_fechar' then
    update public.votacao set aval=false, atualizada=now() where zona=p_zona;
  end if;
end $$;
grant execute on function public.ceu_controlo(text,int,text,int[]) to anon;

-- 4) o painel passa a receber também as avaliações e o estado (aberta/fechada) de cada encontro
create or replace function public.dash_dados(p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; c jsonb; v jsonb; e jsonb;
begin
  if upper(coalesce(p_codigo,'')) <> 'CNE' then
    perform pg_sleep(1);
    raise exception 'codigo errado';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('t',created_at,'z',zona,'a',agrupamento,'s',seccao,'y',anos,'d',duelos)),'[]'::jsonb) into r from respostas;
  select coalesce(jsonb_agg(jsonb_build_object('t',created_at,'z',zona,'a',agrupamento,'n',n_clan,'o',ordem,'cc',cenaculo_cumpre,'cr',cenaculo_razoes,'cm',cenaculo_melhorar,'ro',cenaculo_razoes_outro,'mo',cenaculo_melhorar_outro)),'[]'::jsonb) into c from caminheiros;
  select coalesce(jsonb_agg(jsonb_build_object('t',created_at,'z',zona,'p',perfil,'a',agrupamento,'q',jsonb_build_array(q1,q2,q3))),'[]'::jsonb) into v from avaliacoes;
  select coalesce(jsonb_agg(jsonb_build_object('z',zona,'on',aval)),'[]'::jsonb) into e from votacao;
  return jsonb_build_object('respostas',r,'caminheiros',c,'avaliacoes',v,'aval',e);
end $$;
revoke all on function public.dash_dados(text) from public;
grant execute on function public.dash_dados(text) to anon, authenticated;
