-- Synthetic P14 acceptance; all data and evidence roll back.
begin;
insert into auth.users(id,email,created_at,updated_at) values('00000000-0000-4000-8000-000000001401','p14-verification@example.invalid',now(),now());
insert into ingestion.operators values('00000000-0000-4000-8000-000000001401',now());
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
 ('00000000-0000-4000-8000-000000001411','Identity one','p14-one',false),
 ('00000000-0000-4000-8000-000000001412','Identity two','p14-two',false),
 ('00000000-0000-4000-8000-000000001413','Identity branch','p14-branch',false);
insert into community_orgs.legal_details(org_id,abn,incorporation_number) values
 ('00000000-0000-4000-8000-000000001411','51 824 753 556','0000123'),
 ('00000000-0000-4000-8000-000000001411','00000000000',null),
 ('00000000-0000-4000-8000-000000001412','51 824 753 556','0000123');
insert into ingestion.sources values('acnc-register','identity-fixture','{}',true);
do $$
declare
 org1 uuid:='00000000-0000-4000-8000-000000001411'; org2 uuid:='00000000-0000-4000-8000-000000001412';
 branch uuid:='00000000-0000-4000-8000-000000001413';
 evidence jsonb:='{"reference":"synthetic-registry-evidence","authority":"fixture registry","holder_name":"Identity one","qualified_registry_review":true,"observed_at":"2026-09-18T00:00:00Z"}';
 e jsonb:='{"contract_version":"1.0","source_id":"acnc-register","resource_id":"identity-fixture","run_id":"identity-one","parser_version":"v1","observed_at":"2026-09-18T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"identity-fixture","run_id":"identity-one","native_id":"1","parser_version":"v1","observed_at":"2026-09-18T00:00:00Z","raw":{},"assertions":[{"field":"entity_name","value":"Identity one"},{"field":"abn","value":"51824753556"},{"field":"website","value":"https://identity.example"}]}]}';
 runid text; ver text; rec bigint; result jsonb; n bigint; c uuid; fields jsonb; keyrev integer;
begin
 if ingestion.normalize_identifier('abn','AU','51 824 753 556')<>'51824753556'
  or ingestion.normalize_identifier('abn','AU','00000000000') is not null
  or ingestion.normalize_identifier('abn','AU','51-824753556') is not null
  or ingestion.normalize_identifier('abn','AU','５１８２４７５３５５６') is not null
  or ingestion.normalize_identifier('acn','AU','000012345') is not null
  or ingestion.normalize_identifier('incorporated_association','AU-VIC','0000123') is not null
  or ingestion.normalize_identifier('incorporated_association','AU-NSW','0000123')<>'0000123' then raise exception 'Normalizer contract failed'; end if;
 perform ingestion.backfill_identity_evidence();
 select count(*) into n from ingestion.identifier_claims;
 if ingestion.backfill_identity_evidence()<>0 or n<>(select count(*) from ingestion.identifier_claims)
  or exists(select 1 from ingestion.identifier_keys where holder in (org1,org2,branch)) or exists(select 1 from ingestion.identifier_claims where org_id in (org1,org2,branch) and verification<>'unverified') then raise exception 'Backfill promoted or duplicated legacy identity'; end if;
 if (select count(*) from ingestion.identifier_claims where scheme='incorporated_association' and jurisdiction is null and org_id in (org1,org2))<>2 then raise exception 'Backfill invented jurisdiction'; end if;
 runid:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=runid::bigint;
 select record_id into rec from ingestion.source_record_versions where id=ver::bigint;
 if ingestion.match_identity(ver::bigint)->>'status'<>'review' then raise exception 'Unverified ABN matched'; end if;
 set local role authenticated;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.ingestion_identity_inventory(); raise exception 'Expected access denial'; exception when insufficient_privilege then null; end;
 begin perform community_orgs.review_entity_identity(org1,1,'legal_entity',evidence); raise exception 'Expected access denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000001401","aal":"aal2"}',true);
 perform community_orgs.review_entity_identity(org1,1,'legal_entity',evidence);
 perform community_orgs.review_entity_identity(org2,1,'legal_entity',evidence);
 perform community_orgs.review_entity_identity(branch,1,'branch',evidence);
 begin perform community_orgs.review_identifier_identity(org1,'abn','AU','00000000000',0,'verified',evidence); raise exception 'Expected invalid checksum denial'; exception when invalid_parameter_value then null; end;
 begin perform community_orgs.review_identifier_identity(branch,'abn','AU','51824753556',0,'verified',evidence); raise exception 'Expected branch holder denial'; exception when invalid_parameter_value then null; end;
 result:=community_orgs.review_identifier_identity(org1,'abn','AU','51824753556',0,'verified',evidence);
 begin perform community_orgs.review_identifier_identity(org1,'abn','AU','53004085616',0,'verified',evidence); raise exception 'Expected one-active-ABN denial'; exception when invalid_parameter_value then null; end;
 result:=community_orgs.ingestion_review_queue(runid,ver);
 if result->'detail'->'identity_match'->>'organisation_id'<>org1::text or result->'candidates'->0->>'reason'<>'Verified exact ABN' then raise exception 'Canonical match missing'; end if;
 begin perform community_orgs.save_ingestion_review(runid,ver,0,'create',null,'Duplicate'); raise exception 'Expected duplicate create denial'; exception when serialization_failure then null; end;
 perform community_orgs.save_ingestion_review(runid,ver,0,'link',org1,'Exact registry identity');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(runid,ver,org1)->'fields') x where x->>'field'='website';
 c:=community_orgs.approve_ingestion_fields(runid,ver,1,fields,org1);
 perform community_orgs.review_entity_identity(org2,2,'legal_entity',evidence);
 begin perform community_orgs.publish_ingestion_fields(c); raise exception 'Expected stale classification denial'; exception when serialization_failure then null; end;
 c:=community_orgs.approve_ingestion_fields(runid,ver,1,fields,org1);
 if community_orgs.publish_ingestion_fields(c)<>org1 or community_orgs.publish_ingestion_fields(c)<>org1 then raise exception 'Publication replay changed target'; end if;
 reset role;
 -- Same native ID with changed identity is a new version and must be held.
 e:=jsonb_set(jsonb_set(jsonb_set(e,'{run_id}','"identity-changed"'),'{records,0,run_id}','"identity-changed"'),'{records,0,assertions,1,value}','"53004085616"');
 n:=ingestion.stage_acnc(e);
 if (select ingestion.match_identity(version_id)->>'status' from ingestion.run_records where run_id=n)<>'hold' then raise exception 'Native-ID reuse not held'; end if;
 -- Existing source links do not mask contradictory strong identifiers.
 insert into ingestion.source_links(record_id,organisation_id) values(rec,org1) on conflict do nothing;
 set local role authenticated;
 perform community_orgs.review_identifier_identity(org2,'incorporated_association','AU-NSW','0000123',0,'verified',evidence);
 reset role;
 insert into ingestion.field_assertions(version_id,field,value) values(ver::bigint,'csv_incorporation_jurisdiction','"NSW"'),(ver::bigint,'csv_incorporation_number','"0000123"');
 if ingestion.match_identity(ver::bigint)->>'status'<>'hold' then raise exception 'Contradictory keys not held'; end if;
 set local role authenticated;
 begin perform community_orgs.save_ingestion_review(runid,ver,1,'link',org1,'Ignore conflict'); raise exception 'Expected conflict hold'; exception when invalid_parameter_value then null; end;
 perform community_orgs.save_ingestion_review(runid,ver,1,'defer',null,'Conflicting evidence');
 reset role;
 delete from ingestion.field_assertions where version_id=ver::bigint and field like 'csv_incorporation%';
 insert into ingestion.field_assertions(version_id,field,value) values(ver::bigint,'csv_entity_kind','"branch"');
 if ingestion.match_identity(ver::bigint)->>'status'<>'hold' then raise exception 'Branch merged with holder'; end if;
 update ingestion.field_assertions set value='"service"' where version_id=ver::bigint and field='csv_entity_kind';
 if ingestion.match_identity(ver::bigint)->>'status'<>'hold' then raise exception 'Service merged with holder'; end if;
 delete from ingestion.field_assertions where version_id=ver::bigint and field='csv_entity_kind';
 -- An independent provider/resource identity must resolve via the full key.
 delete from ingestion.source_links where record_id=rec;
 delete from ingestion.field_assertions where version_id=ver::bigint and field='abn';
 insert into ingestion.field_assertions(version_id,field,value) values(ver::bigint,'csv_incorporation_jurisdiction','"NSW"'),(ver::bigint,'csv_incorporation_number','"0000123"');
 if ingestion.match_identity(ver::bigint)->>'organisation_id'<>org2::text then raise exception 'Scoped incorporation did not match'; end if;
 update ingestion.field_assertions set value='"123"' where version_id=ver::bigint and field='csv_incorporation_number';
 if ingestion.match_identity(ver::bigint)->>'status'<>'review' then raise exception 'Leading zeros lost'; end if;
 update ingestion.field_assertions set value='"VIC"' where version_id=ver::bigint and field='csv_incorporation_jurisdiction';
 if ingestion.match_identity(ver::bigint)->>'status'<>'review' then raise exception 'Unsupported jurisdiction matched'; end if;
 delete from ingestion.field_assertions where version_id=ver::bigint and field like 'csv_incorporation%';
 insert into ingestion.field_assertions(version_id,field,value) values(ver::bigint,'abn','"51824753556"');
 insert into ingestion.source_links(record_id,organisation_id) values(rec,org1);
 update community_orgs.legal_details set abn='51824753556' where org_id=org1 and abn='51 824 753 556';
 insert into community_orgs.legal_details(org_id) values(org1);
 if (select state from ingestion.identifier_keys where scheme='abn' and holder=org1)<>'verified' then raise exception 'Equivalent display or empty child row disputed identity'; end if;
 -- A competing claim is durable evidence and reserves the original holder.
 set local role authenticated;
 result:=community_orgs.review_identifier_identity(org2,'abn','AU','51824753556',1,'verified',evidence);
 if result->>'status'<>'conflict' or result->>'holder'<>org1::text then raise exception 'Reservation transferred'; end if;
 result:=community_orgs.ingestion_review_queue(runid,ver);
 if result->'detail'->'identity_match'->>'status'<>'hold' then raise exception 'Disputed key matched'; end if;
 perform community_orgs.review_identifier_identity(org1,'abn','AU','51824753556',2,'withdrawn',evidence);
 begin perform community_orgs.review_entity_identity(org1,2,'community_group',evidence); raise exception 'Expected reservation classification denial'; exception when invalid_parameter_value then null; end;
 perform community_orgs.review_identifier_identity(org1,'abn','AU','51824753556',3,'verified',evidence);
 perform community_orgs.review_branch_identity(branch,org1,'2026-01-01',null,evidence);
 begin perform community_orgs.review_branch_identity(branch,org2,'2026-02-01',null,evidence); raise exception 'Expected overlap denial'; exception when invalid_parameter_value then null; end;
 reset role;
 update community_orgs.legal_details set abn='53004085616' where org_id=org1;
 if (select state from ingestion.identifier_keys where scheme='abn' and holder=org1)<>'disputed' then raise exception 'Manual identity edit did not dispute'; end if;
 if has_table_privilege('authenticated','ingestion.identifier_keys','SELECT') or has_function_privilege('authenticated','community_orgs.publish_ingestion_fields_before_identity(uuid)','EXECUTE') or has_function_privilege('ingestion_worker','community_orgs.review_identifier_identity(uuid,text,text,text,integer,text,jsonb)','EXECUTE') then raise exception 'Identity access leaked'; end if;
 -- Exact target XOR is enforced even for privileged internal writers.
 begin update ingestion.source_links set organisation_id=null where record_id=rec; raise exception 'Missing source target accepted'; exception when check_violation then null; end;
 insert into community_orgs.programs_services(program_id,org_id,program_name) values('00000000-0000-4000-8000-000000001499',org1,'Service fixture');
 begin update ingestion.source_links set service_id='00000000-0000-4000-8000-000000001499' where record_id=rec; raise exception 'Multiple source targets accepted'; exception when check_violation then null; end;
 update ingestion.source_links set organisation_id=null,service_id='00000000-0000-4000-8000-000000001499' where record_id=rec;
 if ingestion.match_identity(ver::bigint)->>'status'<>'hold' then raise exception 'Service target released for organisation publication'; end if;
 insert into auth.mfa_factors(id,user_id,status,factor_type,created_at,updated_at) values(gen_random_uuid(),'00000000-0000-4000-8000-000000001401','verified','totp',now(),now());
 set local role authenticated;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000001401","aal":"aal1"}',true);
 begin perform community_orgs.ingestion_identity_inventory(); raise exception 'Expected MFA denial'; exception when insufficient_privilege then null; end;
 reset role;
 raise notice 'P14 normalization, unverified backfill, canonical matching, conflict/branch/service holds, reservation, audit and access passed';
end $$;
rollback;
