-- P32: RLS-preserving directory search for names, aliases and exact ABNs.
create extension if not exists pg_trgm with schema extensions;

create index if not exists organisations_entity_name_trgm_idx
 on community_orgs.organisations using gin(lower(entity_name) extensions.gin_trgm_ops);
create index if not exists aliases_alias_trgm_idx
 on community_orgs.aliases using gin(lower(alias) extensions.gin_trgm_ops)
 where alias is not null;
create index if not exists legal_details_normalised_abn_idx
 on community_orgs.legal_details((regexp_replace(abn,'[^0-9]','','g')))
 where abn is not null;

create function community_orgs.search_organisations(
 p_query text default '',p_offset integer default 0,p_limit integer default 10
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare q text:=lower(trim(coalesce(p_query,''))); normalised_abn text; result jsonb;
begin
 if length(q)>100 or p_offset not between 0 and 1000000 or p_limit not between 1 and 100 then
  raise exception 'Invalid directory search' using errcode='22023';
 end if;
 normalised_abn:=regexp_replace(q,'[^0-9]','','g');
 with matches as materialized (
  select o.org_id,o.entity_name,o.slug,o.description,o.date_established,o.is_public,
   case
    when length(normalised_abn)=11 and exists(select 1 from community_orgs.legal_details l
      where l.org_id=o.org_id and regexp_replace(l.abn,'[^0-9]','','g')=normalised_abn) then 0
    when q<>'' and lower(o.entity_name)=q then 1
    when q<>'' and exists(select 1 from community_orgs.aliases a
      where a.org_id=o.org_id and lower(a.alias)=q) then 2
    when q='' then 3
    when position(q in lower(o.entity_name))>0 then 3
    else 4 end as search_rank
  from community_orgs.organisations o
  where community_orgs.can_view_org(o.org_id) and (
   q=''
   or position(q in lower(o.entity_name))>0
   or exists(select 1 from community_orgs.aliases a where a.org_id=o.org_id
      and position(q in lower(a.alias))>0)
   or (length(normalised_abn)=11 and exists(select 1 from community_orgs.legal_details l
      where l.org_id=o.org_id and regexp_replace(l.abn,'[^0-9]','','g')=normalised_abn))
  )
 )
 select jsonb_build_object(
  'total',(select count(*) from matches),
  'organisations',coalesce((select jsonb_agg(to_jsonb(page) order by page.search_rank,page.entity_name,page.org_id)
   from (
    select m.*,
     coalesce((select jsonb_agg(jsonb_build_object('alias',a.alias,'alias_type',a.alias_type)
       order by a.alias_type,a.alias) from community_orgs.aliases a where a.org_id=m.org_id),'[]'::jsonb) as aliases,
     coalesce((select jsonb_agg(jsonb_build_object('entity_type',l.entity_type,'abn',l.abn)
       order by l.legal_id) from community_orgs.legal_details l where l.org_id=m.org_id),'[]'::jsonb) as legal_details,
     coalesce((select jsonb_agg(jsonb_build_object('phone',c.phone,'email',c.email)
       order by c.contact_id) from community_orgs.contact_info c where c.org_id=m.org_id),'[]'::jsonb) as contact_info
    from matches m order by m.search_rank,m.entity_name,m.org_id limit p_limit offset p_offset
   ) page),'[]'::jsonb)
 ) into result;
 return result;
end $$;

revoke all on function community_orgs.search_organisations(text,integer,integer) from public;
grant execute on function community_orgs.search_organisations(text,integer,integer) to anon,authenticated;

comment on function community_orgs.search_organisations(text,integer,integer) is
 'RLS-preserving directory search. Child-table RLS controls aliases, legal details and contact details; ABN matching is exact after punctuation removal.';
