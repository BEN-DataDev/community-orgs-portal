-- Complete the isolated harness with the portal's ordinary owner-grant hook.
insert into community_orgs.roles(name) values ('owner');
create trigger test_owner_grant after insert on community_orgs.organisations
 for each row execute function community_orgs.grant_owner_on_organisation_insert();
