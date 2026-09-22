-- P32 rollback-only directory search regression.
begin;
insert into auth.users values ('00000000-0000-4000-8000-000000003201');
insert into community_orgs.organisations values
 ('00000000-0000-4000-8000-000000003211','Alpha Community Centre','alpha','Public Alpha','2001-01-01',true),
 ('00000000-0000-4000-8000-000000003212','Beta Support Group','beta','Public Beta',null,true),
 ('00000000-0000-4000-8000-000000003213','Hidden Member Group','hidden','Private member record',null,false);
insert into community_orgs.aliases values
 ('00000000-0000-4000-8000-000000003221','00000000-0000-4000-8000-000000003211','Trading Name','Snowy Help'),
 ('00000000-0000-4000-8000-000000003222','00000000-0000-4000-8000-000000003213','Business Name','Private Alias');
insert into community_orgs.legal_details values
 ('00000000-0000-4000-8000-000000003231','00000000-0000-4000-8000-000000003211','Charity','51 824 753 556'),
 ('00000000-0000-4000-8000-000000003232','00000000-0000-4000-8000-000000003213','Association','11 000 000 000');
insert into community_orgs.contact_info values
 ('00000000-0000-4000-8000-000000003241','00000000-0000-4000-8000-000000003211','{"primary":"02 6000 0000"}','alpha@example.test');
insert into community_orgs.user_organisation_roles values
 ('00000000-0000-4000-8000-000000003201','00000000-0000-4000-8000-000000003213',true,null);

do $$
declare result jsonb;
begin
 set local role anon;
 result:=community_orgs.search_organisations('',0,10);
 if result->>'total'<>'2' or jsonb_array_length(result->'organisations')<>2 then
  raise exception 'Anonymous blank directory leaked or omitted rows: %',result; end if;
 result:=community_orgs.search_organisations('snowy',0,10);
 if result->>'total'<>'1' or result->'organisations'->0->>'entity_name'<>'Alpha Community Centre' then
  raise exception 'Alias search failed: %',result; end if;
 if jsonb_array_length(result->'organisations'->0->'legal_details')<>0
  or jsonb_array_length(result->'organisations'->0->'contact_info')<>0 then
  raise exception 'Anonymous search exposed sensitive child rows: %',result; end if;
 result:=community_orgs.search_organisations('51-824-753-556',0,10);
 if result->>'total'<>'0' then raise exception 'Anonymous ABN search exposed legal details: %',result; end if;
 result:=community_orgs.search_organisations('824753',0,10);
 if result->>'total'<>'0' then raise exception 'Partial ABN search was accepted: %',result; end if;
 result:=community_orgs.search_organisations('',1,1);
 if result->>'total'<>'2' or jsonb_array_length(result->'organisations')<>1 then
  raise exception 'Server pagination count failed: %',result; end if;
 result:=community_orgs.search_organisations('private',0,10);
 if result->>'total'<>'0' then raise exception 'Anonymous search leaked private row: %',result; end if;
 reset role;

 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000003201"}',true);
 set local role authenticated;
 result:=community_orgs.search_organisations('51-824-753-556',0,10);
 if result->>'total'<>'1' or result->'organisations'->0->'legal_details'->0->>'abn'<>'51 824 753 556' then
  raise exception 'Registered-user exact normalised ABN search failed: %',result; end if;
 result:=community_orgs.search_organisations('private',0,10);
 if result->>'total'<>'1' or result->'organisations'->0->>'entity_name'<>'Hidden Member Group' then
  raise exception 'Member-visible private search failed: %',result; end if;
 begin
  perform community_orgs.search_organisations(repeat('x',101),0,10);
  raise exception 'Oversized query accepted';
 exception when invalid_parameter_value then null; end;
 reset role;

 if has_function_privilege('service_role','community_orgs.search_organisations(text,integer,integer)','EXECUTE')
  or not has_function_privilege('anon','community_orgs.search_organisations(text,integer,integer)','EXECUTE') then
  raise exception 'Unexpected search function grants'; end if;
 if (select count(*) from pg_indexes where schemaname='community_orgs'
  and indexname in ('organisations_entity_name_trgm_idx','aliases_alias_trgm_idx','legal_details_normalised_abn_idx'))<>3 then
  raise exception 'Directory search indexes missing'; end if;
 raise notice 'P32 RLS-preserving name/alias/exact-ABN search, pagination and visibility passed';
end $$;
rollback;
