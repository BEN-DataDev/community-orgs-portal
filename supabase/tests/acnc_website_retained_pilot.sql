-- Disposable database ONLY. Caller begins a transaction and privately supplies
-- test.website_pilot_parent, test.website_pilot_v2, test.website_pilot_v3 and
-- test.website_pilot_source. No real data is embedded here. All writes roll back.
do $$
declare parent jsonb:=current_setting('test.website_pilot_parent')::jsonb;
 old jsonb:=current_setting('test.website_pilot_v2')::jsonb;
 replay jsonb:=current_setting('test.website_pilot_v3')::jsonb;
 source jsonb:=current_setting('test.website_pilot_source')::jsonb;
 p bigint; v2 bigint; v3 bigint; before_versions jsonb;
begin
 insert into ingestion.sources(source_id,resource_id,metadata,enabled)
 values(source->>'source_id',source->>'resource_id',source->'metadata',true);
 p:=ingestion.stage_acnc(parent);
 old:=jsonb_set(old,'{reprocessing,parent_run_id}',to_jsonb(p));
 replay:=jsonb_set(replay,'{reprocessing,parent_run_id}',to_jsonb(p));
 v2:=ingestion.stage_acnc_reprocessing(p,old);
 select jsonb_agg(to_jsonb(v) order by v.id) into before_versions from ingestion.source_record_versions v;
 v3:=ingestion.stage_acnc_reprocessing(p,replay);
 if (select completion from ingestion.ingestion_runs where id=v3)<>'complete'
  or (select count(*) from ingestion.run_records where run_id=v3)<>6
  or jsonb_array_length(replay->'quarantine')<>0
  or (select envelope from ingestion.ingestion_runs where id=p)<>parent
  or (select envelope from ingestion.ingestion_runs where id=v2)<>old
  or exists(select 1 from jsonb_array_elements(before_versions) b
    where not exists(select 1 from ingestion.source_record_versions v where to_jsonb(v)=b))
  or (select count(*) from ingestion.source_records where resource_id=parent->>'resource_id')<>6
 then raise exception 'Retained v3 replay changed evidence or failed completeness'; end if;
 if not exists(select 1 from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id
  where rr.run_id=v3 and v.payload->'assertions' @> '[{"field":"website","value":"https://smartrescue.org.au","source_values":{"Charity_Website":"smartrescue.org.au"},"normalisation":{"scheme_inferred":true}}]')
 then raise exception 'Retained bare website not explicitly normalised'; end if;
 if ingestion.stage_acnc_reprocessing(p,replay)<>v3 then raise exception 'Retained retry duplicated run'; end if;
 if exists(select 1 from ingestion.change_sets where run_id=v3) then raise exception 'Replay approved fields'; end if;
 raise notice 'Retained pilot v3: six accepted, zero quarantined, v1/v2 evidence preserved, explicit URL inference, no duplicate identities or approvals';
end $$;
rollback;
