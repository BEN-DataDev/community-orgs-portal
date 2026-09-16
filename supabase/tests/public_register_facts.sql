-- Requires emit_complete_fixture.py output in this session. Synthetic rollback-only.
begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000f04');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000f04');
insert into ingestion.sources(source_id,resource_id,metadata,enabled) values
 ('acnc-register','f03-complete','{"public_title":"Register A","public_url":"https://example.org/register","public_licence":"CC BY","public_licence_url":"https://example.org/licence"}',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f04","aal":"aal2"}',true);
do $$
declare e jsonb:=current_setting('test.f03_envelope')::jsonb; row jsonb; run text; ver text; org uuid;
 fields jsonb; approval uuid; original_approval uuid; facts jsonb; f jsonb; pub_count integer;
begin
 -- Private raw values and reviewer notes must never appear in public results.
 e:=jsonb_set(e,'{records,0,raw,private_note}','"RAW_PRIVATE_SENTINEL"');
 run:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=run::bigint;
 perform community_orgs.save_ingestion_review(run,ver,0,'create',null,'REVIEW_PRIVATE_SENTINEL');
 fields:=community_orgs.ingestion_field_preview(run,ver)->'fields';
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields);
 original_approval:=approval;
 org:=community_orgs.publish_ingestion_fields(approval);
 perform set_config('test.f04_org',org::text,true);
 set local role anon;
 perform set_config('request.jwt.claims','{}',true);
 facts:=community_orgs.organisation_register_facts(org);
 if jsonb_array_length(facts)<>62 then raise exception 'Anonymous fact coverage incomplete'; end if;
 if not facts @> '[{"field":"pbi","value":false},{"field":"responsible_person_count","value":7},
  {"field":"financial_year_end","value":{"month":6,"day":30}},{"field":"date_established","effective_date":"1968-05-23"},
  {"field":"administrative_address","value":{"line_3":"Synthetic Address Line 3","postcode":"0800"}}]' then raise exception 'Typed public values lost'; end if;
 if exists(select 1 from jsonb_array_elements(facts) x where x->>'observed_at'<>'2026-09-16T00:00:00+00:00') then raise exception 'Observation timestamp replaced'; end if;
 if exists(select 1 from jsonb_array_elements(facts) x, jsonb_object_keys(x) k
  where k not in ('field','section','label','kind','value','source_title','source_url','resource_id','licence','licence_url',
                 'observed_at','published_at','effective_date','unchanged_since_import','retained_address_components'))
  or facts::text like '%PRIVATE_SENTINEL%' then raise exception 'Private evidence exposed'; end if;
 if not exists(select org_id from community_orgs.acnc_register_details where org_id=org and pbi=false) then raise exception 'Anonymous published projection unreadable'; end if;
 begin perform payload from ingestion.source_record_versions; raise exception 'Raw versions publicly readable'; exception when insufficient_privilege then null; end;
 begin perform source_record_id from community_orgs.acnc_register_details; raise exception 'Internal identity publicly readable'; exception when insufficient_privilege then null; end;
 begin perform community_orgs.ingestion_field_preview(run,ver); raise exception 'Private preview publicly callable'; exception when insufficient_privilege then null; end;
 reset role;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f04","aal":"aal2"}',true);

 -- A hidden register projection is excluded independently of parent visibility.
 update community_orgs.acnc_register_details set is_public=false where org_id=org;
 set local role anon;
 if jsonb_array_length(community_orgs.organisation_register_facts(org))<>5
  or exists(select org_id from community_orgs.acnc_register_details where org_id=org)
 then raise exception 'Hidden register projection leaked'; end if;
 if community_orgs.organisation_register_facts('00000000-0000-0000-0000-000000000000')<>'[]' then raise exception 'Unknown organisation has public facts'; end if;
 reset role;
 update community_orgs.acnc_register_details set is_public=true where org_id=org;

 -- Disagreement: an explicitly linked distinct source identity retains its own values.
 row:=jsonb_set(jsonb_set(e->'records'->0,'{native_id}','"f04-second"'),'{run_id}','"f04-second"');
 row:=jsonb_set(row,'{assertions}','[{"field":"pbi","value":true},{"field":"charity_size","value":"Large"}]');
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f04-second"'),'{records}',jsonb_build_array(row));
 run:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=run::bigint;
 perform community_orgs.save_ingestion_review(run,ver,0,'link',org,'Explicit independent source link');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run,ver,org)->'fields') x where x->>'status'='new';
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields,org);
 -- Approved but unpublished observations remain invisible.
 set local role anon;
 if jsonb_array_length(community_orgs.organisation_register_facts(org))<>62 then raise exception 'Unpublished approval exposed'; end if;
 reset role;
 perform community_orgs.publish_ingestion_fields(approval);
 set local role anon;
 facts:=community_orgs.organisation_register_facts(org);
 if (select count(*) from jsonb_array_elements(facts) x where x->>'field'='pbi')<>2
  or not facts @> '[{"field":"pbi","value":false},{"field":"pbi","value":true}]' then raise exception 'Source disagreement collapsed'; end if;
 reset role;

 -- A new observation of the same source/field replaces its old public observation only.
 row:=jsonb_set(jsonb_set(row,'{run_id}','"f04-latest"'),'{assertions}','[{"field":"charity_size","value":"Medium"}]');
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f04-latest"'),'{records}',jsonb_build_array(row));
 run:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=run::bigint;
 perform community_orgs.save_ingestion_review(run,ver,0,'link',org,'New observation');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run,ver,org)->'fields') x where x->>'status'='changed';
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields,org);
 perform community_orgs.publish_ingestion_fields(approval);
 set local role anon;
 facts:=community_orgs.organisation_register_facts(org);
 if facts @> '[{"field":"charity_size","value":"Large"}]'
 or not facts @> '[{"field":"charity_size","value":"Small"},{"field":"charity_size","value":"Medium"}]' then raise exception 'Superseded observation still public'; end if;
 reset role;
 -- Exports are captured under the anon role for the page/browser harness.
 set local role anon;
 perform set_config('test.f04_public',jsonb_build_object('facts',facts,'organisation',
  (select to_jsonb(o) from community_orgs.organisations o where org_id=org))::text,true);
 reset role;
 select x into f from jsonb_array_elements(community_orgs.ingestion_field_preview(run,ver,org)->'fields') x where x->>'field'='pbi';
 perform community_orgs.suppress_ingestion_content(run,ver,'pbi','PRIVATE_SUPPRESSION_REASON',jsonb_build_object('organisation_id',org,'field',f));
 set local role anon;
 facts:=community_orgs.organisation_register_facts(org);
 if exists(select 1 from jsonb_array_elements(facts) x where x->>'field'='pbi')
 or exists(select org_id from community_orgs.acnc_register_details where org_id=org and pbi is not null) then raise exception 'Suppressed values leaked'; end if;
 perform set_config('test.f04_suppressed',jsonb_build_object('facts',facts,'organisation',
  (select to_jsonb(o) from community_orgs.organisations o where org_id=org))::text,true);
 reset role;
 perform community_orgs.suppress_ingestion_content(run,ver,'*','PRIVATE_WITHDRAWAL_REASON',jsonb_build_object('organisation_id',org));
 begin perform community_orgs.publish_ingestion_fields(original_approval); raise exception 'Withdrawal replay accepted'; exception when insufficient_privilege then null; end;
 set local role anon;
 facts:=community_orgs.organisation_register_facts(org);
 if facts<>'[]' or exists(select org_id from community_orgs.organisations where org_id=org)
 or exists(select org_id from community_orgs.acnc_register_details where org_id=org) then raise exception 'Withdrawn organisation leaked'; end if;
 perform set_config('test.f04_withdrawn',jsonb_build_object('facts',facts,'organisation',
  (select to_jsonb(o) from community_orgs.organisations o where org_id=org))::text,true);
 reset role;
 raise notice 'F04 anonymous typed facts, approvals, disagreements, latest observations, private evidence, suppression and withdrawal passed';
end $$;
-- One machine-readable row; only values obtained under SET ROLE anon are exported.
select jsonb_build_object('public',current_setting('test.f04_public')::jsonb,
 'suppressed',current_setting('test.f04_suppressed')::jsonb,
 'withdrawn',current_setting('test.f04_withdrawn')::jsonb) as f04_browser_fixture;
rollback;
