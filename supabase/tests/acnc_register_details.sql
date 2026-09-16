-- Run after F02 migration against an isolated database. Everything is rolled back.
begin;
insert into community_orgs.organisations(org_id, entity_name, slug, is_public)
values ('00000000-0000-0000-0000-000000000f02', 'F02 test', 'f02-test', true);
insert into ingestion.sources(source_id, resource_id, metadata) values ('acnc-register', 'f02-test', '{}');
insert into ingestion.source_records(source_id, resource_id, native_id)
values ('acnc-register', 'f02-test', 'test');
insert into community_orgs.acnc_register_details(org_id, source_record_id, administrative_address,
 financial_year_end, pbi, purposes, other_names_text)
select '00000000-0000-0000-0000-000000000f02', id,
 '{"line_1":"One","line_2":"Two","line_3":"Three","postcode":"0800"}',
 '{"month":2,"day":29}', false, '{"advancing_health":false}', repeat('name;',1000)
from ingestion.source_records where resource_id='f02-test';
do $$ begin
 if community_orgs.acnc_calendar_valid('{"month":4,"day":31}')
 or community_orgs.acnc_calendar_valid('{"month":null,"day":1}')
 or community_orgs.acnc_calendar_valid('{"month":2,"day":1.5}')
 or community_orgs.acnc_object_valid('{"unexpected":true}', array['act'], 'boolean')
 or community_orgs.acnc_object_valid('{"act":"N"}', array['act'], 'boolean')
 then raise exception 'invalid object accepted'; end if;
 begin
  update community_orgs.acnc_register_details set responsible_person_count=-1;
  raise exception 'negative count accepted';
 exception when check_violation then null; end;
 begin
  update community_orgs.acnc_register_details set financial_year_end='{"month":4,"day":31}';
  raise exception 'invalid calendar accepted';
 exception when check_violation then null; end;
end $$;
set local role anon;
do $$ begin
 if exists(select org_id from community_orgs.acnc_register_details) then
  raise exception 'private projection leaked'; end if;
 begin
  perform source_record_id from community_orgs.acnc_register_details;
  raise exception 'private identity leaked';
 exception when insufficient_privilege then null; end;
 begin
  update community_orgs.acnc_register_details set is_public=true;
  raise exception 'anonymous write allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
update community_orgs.acnc_register_details set is_public=true;
set local role authenticated;
do $$ begin
 if not exists(select org_id from community_orgs.acnc_register_details
  where pbi=false and purposes->'advancing_health'='false'::jsonb
  and administrative_address->>'postcode'='0800' and length(other_names_text)=5000)
 then raise exception 'public values lost'; end if;
 begin
  update community_orgs.acnc_register_details set pbi=true;
  raise exception 'authenticated write allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
update community_orgs.organisations set is_public=false
where org_id='00000000-0000-0000-0000-000000000f02';
set local role anon;
do $$ begin
 if exists(select org_id from community_orgs.acnc_register_details) then
  raise exception 'private organisation leaked'; end if;
end $$;
reset role;
rollback;
