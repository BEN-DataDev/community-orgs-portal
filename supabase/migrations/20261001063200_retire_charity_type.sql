-- legal_details.charity_type offered one of PBI, HPC or Other, but a charity can hold
-- several ACNC subtypes and the column was never populated from the register. The
-- portal now shows the ACNC subtypes (purposes plus PBI and HPC) as register facts,
-- so the column is retired. Refuse to drop it if anyone has recorded a value.
begin;

do $$
begin
  if exists (select 1 from community_orgs.legal_details where charity_type is not null) then
    raise exception 'charity_type holds values; review them before retiring the column'
      using errcode = '55000';
  end if;
end $$;

alter table community_orgs.legal_details drop column charity_type;

commit;
