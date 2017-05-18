
/* initializations */

set @event_id = (select id
  from civicrm_event
  where
    event_type_id = 1 and
    year(start_date) = @year );
set @this_bat = (select start_date from civicrm_event where id = @event_id);


/* fundraising teams */

drop temporary table if exists approved_team;
create temporary table approved_team (
  team_name char(100),
  unique index(team_name) ) character set utf8 collate utf8_unicode_ci;
insert into approved_team select distinct
  bat.team_65
from civicrm_participant part
join civicrm_value_bike_a_thon_16 bat on bat.entity_id = part.id
where
  part.event_id = @event_id and
  part.role_id = 11 /* fundraising team */;


/* rider table -- the central table in this whole script */

drop temporary table if exists rider;
create temporary table rider (
  contact_id int(10) not null,
  rider_sequential_id int(4) not null,
  rider_id int(6),
  first_name varchar(128),
  last_name varchar(128),
  display_name varchar(128),
  part_id int(10) not null,
  part_status char(50),
  part_datetime datetime,
  reg_by_contact_id int(10),
  reg_by_name char(100),
  route char(50),
  reg_level enum('team','adult','youth','child'),
  drupal_user_name char(100),
  pcp_id int(10),
  pcp_url char(200),
  fundr_min decimal(6,2),
  total decimal(7,2),
  overdue_total decimal(7,2),
  total_is_public int(1),
  team_name char(100),
  group_id int(10),
  pcp_total decimal(7,2),
  others text,
  captain char(50),
  emergency_name char(100),
  emergency_phone char(100),
  note text,
  prev_years char(200),
  prev_max_direct decimal(7,2),
  unique index(contact_id),
  unique index(rider_sequential_id),
  unique index(rider_id),
  index(first_name),
  index(last_name),
  index(display_name),
  unique index(part_id),
  index(part_status),
  index(reg_level),
  index(fundr_min),
  index(total_is_public),
  index(team_name),
  index(reg_by_contact_id),
  index(group_id) ) character set utf8 collate utf8_unicode_ci;
set @prev_rider_sequential_id = 0;
insert into rider (
    contact_id,
    rider_sequential_id,
    first_name,
    last_name,
    display_name,
    part_id )
  select
    contact.id,
    @prev_rider_sequential_id := @prev_rider_sequential_id + 1
      as rider_sequential_id,
    first_name as first_name,
    trim(last_name) as last_name,
    coalesce(concat(
        trim(coalesce(nick_name,first_name)), ' ',
        trim(last_name)
      ), display_name) as display_name,
    max(part.id) as part_id
  from civicrm_participant part
  join civicrm_participant_status_type status on status.id = part.status_id
  join civicrm_contact contact on contact.id = part.contact_id
  join civicrm_event event on event.id = part.event_id
  where
    year(event.start_date) = @year and
    event.event_type_id = 1 and
    contact.is_deleted != 1 and
    part.is_test != 1 and
    part.role_id in (1,5,11) /* rider, non-attending fundraiser, team */ and
    status.is_counted = 1
  group by contact.id
  order by part.register_date, contact.id;
update rider set
  rider_id = (rider_sequential_id + 1000) * 100 + mod(contact_id, 100);


/* bring in PCP id */

drop temporary table if exists rider_page;
create temporary table rider_page (
  contact_id int(10),
  page_id int(10),
  unique index(contact_id) ) character set utf8 collate utf8_unicode_ci;
insert into rider_page select
  pcp.contact_id,
  max(pcp.id)
from civicrm_pcp pcp
join civicrm_contribution_page cpage on cpage.id = pcp.page_id and pcp.page_type = 'contribute'
where
  year(cpage.start_date) = @year and
  cpage.financial_type_id = 2 /* BATRS */
group by pcp.contact_id;

set @pcp_url_prefix = 'https://bikesnotbombs.org/civicrm/pcp/info?reset=1&id=';

update rider
join rider_page on rider_page.contact_id = rider.contact_id
set
  pcp_id = rider_page.page_id,
  pcp_url = concat(@pcp_url_prefix, rider_page.page_id);


/* bring in participation details */

update rider
join civicrm_participant part on part.id = rider.part_id
join civicrm_participant_status_type status on status.id = part.status_id
left join civicrm_value_bike_a_thon_16 bat on bat.entity_id = rider.part_id
left join civicrm_participant captain_part on
  captain_part.id = part.registered_by_id
set
  rider.reg_level = case
    when part.role_id in (11) then 'team'
    when part.fee_level like '%adult%' then 'adult'
    when part.fee_level like '%youth%' then 'youth'
    when part.fee_level like '%child%' then 'child'
    else null
    end,
  rider.reg_by_contact_id =
    coalesce(captain_part.contact_id, part.contact_id),
  rider.part_datetime = part.register_date,
  rider.part_status = status.label,
  rider.team_name = if(length(bat.team_65) < 2, NULL, bat.team_65),
  rider.total_is_public = bat.public_total_113,
  rider.route = bat.route_68,
  rider.emergency_name = bat.emergency_contact_name_93,
  rider.emergency_phone = bat.emergency_contact_phone_94;

update rider
join civicrm_contact rc on rc.id = rider.reg_by_contact_id
set reg_by_name =
    coalesce(concat(
        trim(coalesce(rc.nick_name, rc.first_name)), ' ',
        trim(rc.last_name)
      ), rc.display_name);

update rider set fundr_min =
  case reg_level
    when 'team'  then 0
    when 'adult' then 150
    when 'youth' then 75
    when 'child' then 0
    else 150
  end;


/* bring in drupal user */

drop temporary table if exists drupal_user;
create temporary table drupal_user (
  id int(8),
  name char(50),
  email char(50),
  unique index(id),
  unique index(name),
  index(email) ) character set utf8 collate utf8_unicode_ci;
set @s = concat('
  insert into drupal_user
  select uid, name, mail
  from ', @drupal_table, '.users');
prepare drupal_user_insert from @s;
execute drupal_user_insert;
deallocate prepare drupal_user_insert;

update rider
join civicrm_uf_match uf on uf.contact_id = rider.contact_id
join drupal_user du on du.id = uf.uf_id
set rider.drupal_user_name = du.name;


/* BAT fundraising thus far, grouped by contact */

drop temporary table if exists contact_total;
create temporary table contact_total (
  contact_id int(10),
  status char(50),
  total decimal(7,2),
  index(contact_id),
  index(status) ) character set utf8 collate utf8_unicode_ci;
insert into contact_total
  select
    soft.contact_id,
    status.label as status,
    sum(soft.amount) as total
  from civicrm_contribution_soft soft
  join civicrm_contribution contrib on contrib.id = soft.contribution_id
  join civicrm_option_value status on
    status.option_group_id = 11 and
    status.value = contrib.contribution_status_id
  where
    contrib.financial_type_id = 2 and
    status.value in ( 1, 6 ) and /* completed, overdue */
    contrib.is_test = 0 and
    year(contrib.receive_date) = @year
  group by soft.contact_id, status.label;


/* update fundraising details */

update rider
left join (
  select contact_id, sum(total) as total
  from contact_total
  group by contact_id
  ) total on total.contact_id = rider.contact_id
set rider.total = coalesce(total.total,0);

update rider
left join (
  select contact_id, sum(total) as total
  from contact_total
  where status = 'Overdue'
  group by contact_id
  ) total on total.contact_id = rider.contact_id
set rider.overdue_total = coalesce(total.total,0);


/* BAT fundraising thus far, grouped by PCP */

drop temporary table if exists pcp_contribs;
create temporary table pcp_contribs (
  pcp_id int(10) not null,
  contrib_id int(10) not null,
  index(pcp_id),
  index(contrib_id),
  unique index(pcp_id, contrib_id) );
insert into pcp_contribs select
  pcp.id,
  contrib.id
from civicrm_pcp pcp
join rider on rider.pcp_id = pcp.id
join civicrm_contribution_soft soft on soft.pcp_id = pcp.id
join civicrm_contribution contrib on contrib.id = soft.contribution_id
where
  contrib.contribution_status_id in ( 1, 6 ) /* completed, overdue */
group by pcp.id, contrib.id;

drop temporary table if exists pcp_total;
create temporary table pcp_total (
  pcp_id int(10) not null,
  total decimal(7,2) not null,
  unique index(pcp_id) );
insert into pcp_total select
  pcp_contribs.pcp_id,
  sum(contrib.total_amount)
from pcp_contribs
join civicrm_contribution contrib on contrib.id = pcp_contribs.contrib_id
group by pcp_contribs.pcp_id;

update rider
left join pcp_total on pcp_total.pcp_id = rider.pcp_id
set rider.pcp_total = coalesce(pcp_total.total,0);


/* Notes to be printed on check in sheet */

drop temporary table if exists benefactor;
create temporary table benefactor (
  contact_id int(10),
  names text,
  unique index(contact_id) );
insert into benefactor select
  rider.contact_id,
  group_concat(
    distinct
    concat_ws(' ', benefactor.first_name, benefactor.last_name)
    separator ', '
  )
from rider
join civicrm_contribution_soft soft on soft.contact_id = rider.contact_id
join civicrm_pcp pcp on pcp.id = soft.pcp_id
join civicrm_contact benefactor on benefactor.id = pcp.contact_id
where benefactor.id != rider.contact_id
group by rider.contact_id;

update rider
join benefactor on benefactor.contact_id = rider.contact_id
set note = concat(
  @note_header,
  'some of the money that ',
  benefactor.names,
  ' raised has been distributed to your total since you registered together. ',
  @note_footer_reg )
where total > pcp_total;


drop temporary table if exists beneficiary;
create temporary table beneficiary (
  contact_id int(10),
  names text,
  unique index(contact_id) );
insert into beneficiary select
  rider.contact_id,
  group_concat(
    distinct
    concat_ws(' ', beneficiary.first_name, beneficiary.last_name)
    separator ', '
  )
from rider
join civicrm_pcp pcp on pcp.contact_id = rider.contact_id
join civicrm_contribution_soft soft on soft.pcp_id = pcp.id
join civicrm_contact beneficiary on beneficiary.id = soft.contact_id
where beneficiary.id != rider.contact_id
group by rider.contact_id;

set @note_header = 'Note: ';
set @note_footer_reg =
  'If you have questions, please see the help desk, ideally together.';

update rider
join beneficiary on beneficiary.contact_id = rider.contact_id
set note = concat(
  @note_header,
  'the money you fundraised has been automatically distributed between you ',
  'and the following other riders: ',
  beneficiary.names,
  ' (due to the fact that you registered together and used only one ',
  'fundraising page). ',
  @note_footer_reg );


/* bring in summary of previous BAT years registered */

drop temporary table if exists prev_years_summary;
create temporary table prev_years_summary (
  contact_id int(10),
  prev_years char(200),
  unique index(contact_id) ) character set utf8 collate utf8_unicode_ci;
insert into prev_years_summary select
  contact_id,
  group_concat(
      year(event.start_date) order by event.start_date desc separator ', '
    ) as prev_years
from civicrm_participant part
join civicrm_event event on part.event_id = event.id
join civicrm_participant_status_type status on status.id = part.status_id
where
  event.event_type_id = 1 and
  part.is_test != 1 and
  part.role_id in (1,5,11) /* rider, non-attending fundraiser, team */ and
  status.is_counted = 1 and
  year(event.start_date) < @year
group by contact_id;

update rider
join prev_years_summary on prev_years_summary.contact_id = rider.contact_id
set rider.prev_years = prev_years_summary.prev_years;


/* bring in max previously (directly) raised */

drop temporary table if exists direct_fundraising_by_year;
create temporary table direct_fundraising_by_year (
  contact_id int(10),
  year int(4),
  direct_fundraising decimal(7,2),
  index(contact_id),
  unique index(contact_id, year),
  index(direct_fundraising) ) character set utf8 collate utf8_unicode_ci;
insert into direct_fundraising_by_year select
  soft.contact_id,
  year(contrib.receive_date) as year,
  sum(contrib.total_amount) as direct_fundraising
from civicrm_contribution_soft soft
join civicrm_contribution contrib on contrib.id = soft.contribution_id
where
  contrib.financial_type_id = 2 /* BATRS */ and
  contrib.contribution_status_id in ( 1, 6 ) and /* completed, overdue */
  contrib.is_test = 0
group by contact_id, year(contrib.receive_date);


drop temporary table if exists prev_max_direct;
create temporary table prev_max_direct (
  contact_id int(10),
  prev_max_direct decimal(7,2),
  unique index(contact_id) ) character set utf8 collate utf8_unicode_ci;
insert into prev_max_direct select
  contact_id,
  max(direct_fundraising)
from direct_fundraising_by_year
where year < @year
group by contact_id;

update rider
join prev_max_direct on prev_max_direct.contact_id = rider.contact_id
set rider.prev_max_direct = prev_max_direct.prev_max_direct;
