begin;

do $$
declare
  actor uuid := '00000000-0000-4000-8000-000000009901';
  canonical uuid := '00000000-0000-4000-8000-000000009902';
  nsw_match uuid := '00000000-0000-4000-8000-000000009903';
  nsw_distinct uuid := '00000000-0000-4000-8000-000000009904';
  excluded uuid := '00000000-0000-4000-8000-000000009905';
  abr_release bigint;
  nsw_release bigint;
  acnc_run bigint;
  record bigint;
  version bigint;
  publication uuid;
  correction uuid;
  result jsonb;
begin
  insert into auth.users(id) values(actor);
  insert into ingestion.sources(source_id,resource_id,metadata,enabled) values
    ('correction-test-abr','fixture','{}',true),
    ('correction-test-acnc','fixture','{}',true),
    ('correction-test-nsw','fixture','{}',true);
  insert into ingestion.registry_seed_releases(
    source_id,resource_id,release_key,parser_version,observed_at,completion,scope,manifest,
    manifest_sha256,candidate_sha256,expected_part_count,completed_part_count,candidate_count,
    retention_policy
  ) values (
    'correction-test-abr','fixture','abr','test',now(),'complete',
    '{"kind":"configured-registry-scope","complete_snapshot":true,"snapshot_series":"test","selection":{}}',
    '{}',repeat('a',64),repeat('b',64),1,1,2,'{"class":"hold","basis":"test"}'
  ) returning id into abr_release;
  insert into ingestion.registry_seed_releases(
    source_id,resource_id,release_key,parser_version,observed_at,completion,scope,manifest,
    manifest_sha256,candidate_sha256,expected_part_count,completed_part_count,candidate_count,
    retention_policy
  ) values (
    'correction-test-nsw','fixture','nsw','test',now(),'complete',
    '{"kind":"configured-registry-scope","complete_snapshot":true,"snapshot_series":"test","selection":{}}',
    '{}',repeat('c',64),repeat('d',64),1,1,2,'{"class":"hold","basis":"test"}'
  ) returning id into nsw_release;
  insert into ingestion.ingestion_runs(source_id,resource_id,run_key,completion,observed_at,envelope)
    values('correction-test-acnc','fixture','acnc','complete',now(),'{}') returning id into acnc_run;
  insert into ingestion.source_records(source_id,resource_id,native_id)
    values('correction-test-acnc','fixture','51824753556') returning id into record;
  insert into ingestion.source_record_versions(record_id,parser_version,content_hash,payload)
    values(record,'test',repeat('e',64),'{}') returning id into version;
  insert into ingestion.run_records(run_id,version_id) values(acnc_run,version);
  insert into ingestion.field_assertions(version_id,field,value) values
    (version,'entity_name',to_jsonb('Test Community Incorporated'::text)),
    (version,'abn',to_jsonb('51824753556'::text)),
    (version,'website',to_jsonb('https://example.test'::text)),
    (version,'pbi','true');

  insert into ingestion.full_seed_publications(
    abr_release_id,acnc_run_id,nsw_release_id,status,source_row_count,canonical_count,
    selection_sha256,reason,prepared_by,published_at
  ) values (
    abr_release,acnc_run,nsw_release,'published',4,4,repeat('f',64),'fixture',actor,now()+interval '1 hour'
  ) returning publication_id into publication;

  insert into community_orgs.organisations(org_id,entity_name,slug,is_public,inserted_by,last_edited_by) values
    (canonical,'Test Community Incorporated','correction-canonical',true,actor,actor),
    (nsw_match,'TEST COMMUNITY INCORPORATED','correction-match',true,actor,actor),
    (nsw_distinct,'Distinct Association Incorporated','correction-distinct',true,actor,actor),
    (excluded,'Fixture Sole Trader','correction-excluded',true,actor,actor);
  insert into community_orgs.legal_details(
    org_id,abn,entity_type,incorporation_number,incorporation_status,
    incorporation_registration_date,inserted_by,last_edited_by
  ) values
    (canonical,'51824753556','{"code":"OIE","text":"Other Incorporated Entity"}',null,null,null,actor,actor),
    (nsw_match,null,'Incorporated Association','INC-9901',true,'2020-01-02',actor,actor),
    (nsw_distinct,null,'Incorporated Association','INC-9902',true,'2021-02-03',actor,actor),
    (excluded,'51824753556','{"code":"IND","text":"Individual/Sole Trader"}',null,null,null,actor,actor);
  insert into ingestion.full_seed_items(
    publication_id,canonical_key,organisation_id,existing_organisation,entity_name,abn,
    entity_type,incorporation_number,incorporation_status,incorporation_registration_date,
    website,source_refs,applied_at
  ) values
    (publication,'abn:51824753556',canonical,false,'Test Community Incorporated','51824753556',
      '{"code":"OIE","text":"Other Incorporated Entity"}',null,null,null,
      'https://example.test',jsonb_build_object('abr_version_id',1,'acnc_version_id',version),now()),
    (publication,'incorporated_association:AU-NSW:INC-9901',nsw_match,false,
      'TEST COMMUNITY INCORPORATED',null,'Incorporated Association','INC-9901',true,'2020-01-02',
      null,'{"nsw_version_id":1}',now()),
    (publication,'incorporated_association:AU-NSW:INC-9902',nsw_distinct,false,
      'Distinct Association Incorporated',null,'Incorporated Association','INC-9902',true,'2021-02-03',
      null,'{"nsw_version_id":2}',now()),
    (publication,'abn:11111111111',excluded,false,'Fixture Sole Trader','11111111111',
      '{"code":"IND","text":"Individual/Sole Trader"}',null,null,null,null,
      '{"abr_version_id":2}',now());
  insert into ingestion.identifier_keys(
    scheme,jurisdiction,normalized_value,holder,state,evidence,reviewed_by
  ) values
    ('abn','AU','51824753556',canonical,'verified',jsonb_build_object('full_seed_publication_id',publication),actor),
    ('incorporated_association','AU-NSW','INC-9901',nsw_match,'verified',jsonb_build_object('full_seed_publication_id',publication),actor),
    ('incorporated_association','AU-NSW','INC-9902',nsw_distinct,'verified',jsonb_build_object('full_seed_publication_id',publication),actor);

  result:=ingestion.prepare_seed_publication_correction(publication,'fixture correction');
  correction:=(result->>'correction_id')::uuid;
  if result->>'keep'<>'2' or result->>'merge'<>'1' or result->>'remove'<>'1' then
    raise exception 'Unexpected correction inventory: %',result;
  end if;
  result:=ingestion.apply_seed_publication_correction_managed_batch(correction,10);
  if result->>'status'<>'applied' then raise exception 'Correction did not finish: %',result; end if;
  if exists(select 1 from community_orgs.organisations where org_id in (nsw_match,excluded))
     or not exists(select 1 from community_orgs.organisations where org_id in (canonical,nsw_distinct)) then
    raise exception 'Correction retained or removed the wrong organisations';
  end if;
  if not exists(select 1 from community_orgs.legal_details where org_id=canonical
      and entity_type='Other Incorporated Entity' and incorporation_number='INC-9901') then
    raise exception 'Merged legal details are incomplete';
  end if;
  if not exists(select 1 from ingestion.identifier_keys where normalized_value='INC-9901' and holder=canonical) then
    raise exception 'NSW identifier was not moved to the canonical organisation';
  end if;
  if not exists(select 1 from community_orgs.acnc_register_details
      where org_id=canonical and source_record_id=record and pbi and is_public) then
    raise exception 'Complete mapped ACNC facts were not published';
  end if;
  if not exists(select 1 from community_orgs.contact_info
      where org_id=canonical and website='https://example.test') then
    raise exception 'ACNC website was not published';
  end if;
end $$;

rollback;

select 'Scoped seed correction, NSW merge and ACNC enrichment passed' as result;
