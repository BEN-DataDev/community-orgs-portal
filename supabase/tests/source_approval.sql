-- Run inside a transaction after setting test.ingestion_operator to a platform admin.
do $$
declare token text; doc jsonb; admin_id text := current_setting('test.ingestion_operator');
begin
 insert into ingestion.sources(source_id,resource_id,enabled,metadata) values('source-approval-test','fixture',false,'{}');
 perform set_config('request.jwt.claims','{}',true);
 begin
  perform community_orgs.ingestion_source_approvals();
  raise exception 'Unauthenticated read allowed';
 exception when insufficient_privilege then null; end;
 begin
  perform community_orgs.set_ingestion_source_enabled('source-approval-test','fixture',true,'bad','test');
  raise exception 'Unauthenticated write allowed';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','aal','aal2')::text,true);
 doc := community_orgs.ingestion_source_approvals();
 select value->>'token' into token from jsonb_array_elements(doc) where value->>'source_id'='source-approval-test';
 perform community_orgs.set_ingestion_source_enabled('source-approval-test','fixture',true,token,'Reviewed test evidence');
 if not (select enabled from ingestion.sources where source_id='source-approval-test') then raise exception 'Enable failed'; end if;
 if (select count(*) from ingestion.source_approval_events where source_id='source-approval-test')<>1 then raise exception 'Missing audit'; end if;
 begin
  perform community_orgs.set_ingestion_source_enabled('source-approval-test','fixture',false,token,'stale');
  raise exception 'Stale token accepted';
 exception when serialization_failure then null; end;
 select value->>'token' into token from jsonb_array_elements(community_orgs.ingestion_source_approvals()) where value->>'source_id'='source-approval-test';
 begin
  perform community_orgs.set_ingestion_source_enabled('source-approval-test','fixture',false,token,' ');
  raise exception 'Empty reason accepted';
 exception when invalid_parameter_value then null; end;
 perform community_orgs.set_ingestion_source_enabled('source-approval-test','fixture',false,token,'Pause test');
 if (select enabled from ingestion.sources where source_id='source-approval-test') then raise exception 'Pause failed'; end if;
 if has_table_privilege('authenticated','ingestion.source_approval_events','SELECT') then raise exception 'Private audit exposed'; end if;
end $$;
