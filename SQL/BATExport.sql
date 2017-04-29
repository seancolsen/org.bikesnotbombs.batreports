
/*

Ways of linking riders into groups
 team name (team group)
 people registered together (reg group)

Teams are either approved for combine fundraising, or not.

We know which teams are approved by checking the team name in the participation
record that the *team* contact has (not individual) when registered for BAT
with the role 'fundraising team'.

Some riders will be in a reg group AND a team group

Some team groups will fully contain reg groups (this data is okay)
However, if a reg group is not fully contained within a team, this is bad data.

We want each rider to be in one or zero groups. So if a rider is in a reg group
and a team group, we use the following logic to decide: if the team is approved
then the rider is in the team group. If the team is not approved, then the
rider is in the reg group.

*/

/* initializations */

set @year = 2017; /* TODO: set dynamically */
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
  unique index(team_name) );
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
  first_name char(50),
  last_name char(50),
  display_name char(50),
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
  indiv_total decimal(7,2),
  overdue_total decimal(7,2),
  total_is_public int(1),
  team_name char(100),
  group_id int(10),
  divvied_total decimal(7,2),
  smart_total decimal(7,2),
  others char(200),
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
  index(group_id) );
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
    trim(coalesce(nick_name,first_name)) as first_name,
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
  unique index(contact_id) );
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
  unique index(email) );
/* insert into drupal_user
  select
    uid,
    name,
    mail
  from liv_drup.users; */ /* TODO: get table name dynamically */

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
  index(status) );
insert into contact_total
  select
    soft.contact_id,
    status.label as status,
    sum(contrib.total_amount) as total
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
set rider.indiv_total = coalesce(total.total,0);

update rider
left join (
  select contact_id, sum(total) as total
  from contact_total
  where status = 'Overdue'
  group by contact_id
  ) total on total.contact_id = rider.contact_id
set rider.overdue_total = coalesce(total.total,0);



/* fundraising groups */

drop temporary table if exists fr_group;
create temporary table fr_group (
  id int(10) AUTO_INCREMENT not null,
  team_name char(50),
  reg_by_contact_id int(10),
  group_type enum('reg','team'),
  rider_count int(3),
  slacker_count int(3) comment '# of riders not meeting their own indiv min',
  fundr_min decimal(7,2),
  fundraising_rider_count int(3),
  total_fundraised decimal(8,2),
  has_team_page int(1),
  percent_of_min_raised decimal(6,1),
  percent_of_riders_fundraising decimal(4,1),
  min_is_met int(1),
  is_group_fundraising int(1),
  primary key (id),
  unique index(team_name),
  unique index(reg_by_contact_id),
  index(group_type),
  index(rider_count),
  index(slacker_count),
  index(fundraising_rider_count),
  index(total_fundraised),
  index(has_team_page),
  index(percent_of_min_raised),
  index(percent_of_riders_fundraising),
  index(min_is_met),
  index(is_group_fundraising) );

insert into fr_group (group_type, reg_by_contact_id)
  select
    'reg' as group_type,
    rider.reg_by_contact_id as reg_by_contact_id
  from rider
  group by rider.reg_by_contact_id
  having count(rider.contact_id) > 1;

insert into fr_group (group_type, team_name)
  select
    'team' as group_type,
    trim(rider.team_name) as team_name
  from rider
  where length(rider.team_name) > 1
  group by rider.team_name
  having count(rider.contact_id) > 1;

drop temporary table if exists fr_group2;
create temporary table fr_group2 like fr_group;
insert into fr_group2 select * from fr_group;

update rider
left join fr_group team_group on team_group.team_name = rider.team_name
left join fr_group2 reg_group on
  reg_group.reg_by_contact_id = rider.reg_by_contact_id
left join approved_team on approved_team.team_name = rider.team_name
set group_id = if( approved_team.team_name is not null,
  team_group.id,
  coalesce(reg_group.id, team_group.id ) );


/* calculate group stats based on riders
   using fr_group2 to circumvent inability to use 'group by' with 'update' */

truncate table fr_group2;
insert into fr_group2 (id, rider_count, slacker_count, fundr_min,
    fundraising_rider_count, total_fundraised)
  select
    group_id as id,
    count(*) as rider_count,
    sum(if(indiv_total < fundr_min, 1, 0)) as slacker_count,
    sum(fundr_min) as fundr_min,
    sum(if(indiv_total > 0, 1, 0)) as fundraising_rider_count,
    sum(indiv_total) as total_fundraised
  from rider
  where group_id is not null
  group by group_id;
update fr_group a
join fr_group2 b on a.id = b.id
set
  a.rider_count = b.rider_count,
  a.slacker_count = b.slacker_count,
  a.fundr_min = b.fundr_min,
  a.fundraising_rider_count = b.fundraising_rider_count,
  a.total_fundraised = b.total_fundraised;


update fr_group
set has_team_page = 0
where has_team_page is null;

update fr_group
left join approved_team on approved_team.team_name = fr_group.team_name
set
  percent_of_min_raised = 100 * coalesce(total_fundraised,0) / fundr_min,
  percent_of_riders_fundraising = 100 * fundraising_rider_count / rider_count,
  min_is_met = if(total_fundraised >= fundr_min, 1, 0),
  is_group_fundraising = if(
    approved_team.team_name is not null OR
      ( group_type = 'reg' AND fundraising_rider_count < 2 ),
    1, 0 );

update rider
join fr_group on fr_group.id = rider.group_id
set rider.divvied_total =
  fr_group.total_fundraised * (rider.fundr_min / fr_group.fundr_min)
where fr_group.is_group_fundraising = 1;

update rider
set rider.smart_total = coalesce(divvied_total, indiv_total);

drop temporary table if exists rider_2;
create temporary table rider_2 like rider;
insert into rider_2 select * from rider;

drop temporary table if exists others;
create temporary table others (
  contact_id int(10),
  others char(200),
  unique index(contact_id) );
insert into others
  select
    rider.contact_id,
    group_concat(concat_ws(' ', rider_2.first_name, rider_2.last_name)
      order by rider_2.first_name, rider_2.last_name separator ', ')
  from rider
  join rider_2 on rider_2.group_id = rider.group_id and
    rider_2.contact_id != rider.contact_id
  where
    rider.reg_level != 'team' and
    rider_2.reg_level != 'team'
  group by rider.contact_id;

update rider
join others on others.contact_id = rider.contact_id
set rider.others = others.others;

update rider
join rider_2 on
  rider_2.group_id = rider.group_id and
  rider_2.contact_id != rider.contact_id and
  rider_2.indiv_total > 0
set rider.captain = concat_ws(' ',rider_2.first_name, rider_2.last_name)
where rider.indiv_total = 0;

set @note_header = 'Note: ';
set @note_footer_reg =
  'If you have questions, please see the help desk, ideally together.';
set @note_footer_team =
  'If you have questions, please see the help desk.';

update rider
join fr_group on fr_group.id = rider.group_id
set note = concat(
  @note_header,
  'some of the money that ',
  rider.captain,
  ' raised has been distributed to your total since you registered together. ',
  @note_footer_reg )
where
  fr_group.group_type = 'reg' and
  rider.indiv_total < rider.smart_total;

update rider
join fr_group on fr_group.id = rider.group_id
set note = concat(
  @note_header,
  'the money you fundraised has been automatically distributed between you ',
  'and the following other riders: ',
  rider.others,
  ' (due to the fact that you registered together and used only one ',
  'fundraising page). ',
  @note_footer_reg )
where
  fr_group.group_type = 'reg' and
  rider.indiv_total > rider.smart_total;

update rider
join fr_group on fr_group.id = rider.group_id
set note = concat(
  @note_header,
  'because you are team fundraising with \"',
  fr_group.team_name,
  '\", your total has come from the distributed total of the entire team. ',
  @note_footer_team )
where
  fr_group.group_type = 'team' and
  rider.indiv_total < rider.smart_total;

update rider
join fr_group on fr_group.id = rider.group_id
set note = concat(
  @note_header,
  'the money you fundraised has been automatically distributed between you ',
  'and the other members of \"',
  fr_group.team_name,
  '\" (', rider.others, '). ',
  @note_footer_team )
where
  fr_group.group_type = 'team' and
  rider.indiv_total > rider.smart_total;


/* bring in summary of previous BAT years registered */

drop temporary table if exists prev_years_summary;
create temporary table prev_years_summary (
  contact_id int(10),
  prev_years char(200),
  unique index(contact_id) );
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
  index(direct_fundraising) );
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
  unique index(contact_id) );
insert into prev_max_direct select
  contact_id,
  max(direct_fundraising)
from direct_fundraising_by_year
where year < @year
group by contact_id;

update rider
join prev_max_direct on prev_max_direct.contact_id = rider.contact_id
set rider.prev_max_direct = prev_max_direct.prev_max_direct;



select
  case
    when rider.last_name rlike '^ *[A-B].*' then 'A-B'
    when rider.last_name rlike '^ *[C-D].*' then 'C-D'
    when rider.last_name rlike '^ *[E-G].*' then 'E-G'
    when rider.last_name rlike '^ *[H-K].*' then 'H-K'
    when rider.last_name rlike '^ *(L|M[A-E]).*' then 'L-Me'
    when rider.last_name rlike '^ *(M[F-Z]|[N-Q]).*' then 'Mf-Q'
    when rider.last_name rlike '^ *(R|S[A-M]).*' then 'R-Sm'
    when rider.last_name rlike '^ *(S[N-Z]|[T-Z]).*' then 'Sn-Z'
    else '??'
  end as pile,
  rider.contact_id as cid,
  rider.rider_id as num,
  rider.last_name as last_name,
  rider.first_name as first_name,
  group_concat(distinct email.email separator '\n') as email,
  group_concat(distinct phone.phone separator '\n') as phone,
  group_concat(distinct concat_ws(', ', street_address, supplemental_address_1,
          city, state.abbreviation, postal_code) separator '\n') as address,
  part_status as status,
  part_datetime as reg_date,
  reg_by_contact_id,
  reg_by_name,
  drupal_user_name,
  route,
  total_is_public,
  format(smart_total,2) as total,
  if(indiv_total = smart_total, '(same)', indiv_total) as indiv_t,
  format(overdue_total,2) as overdue,
  format(fundr_min,0) as fmin,
  pcp_id,
  pcp_url,
  now() as time_printed,
  timestampdiff(year, contact.birth_date, @this_bat) as bat_age,
  coalesce(team_name,'') as team_name,
  rider.emergency_name,
  rider.emergency_phone,
  rider.note,
  rider.prev_years,
  rider.prev_max_direct
from rider
join civicrm_contact contact on contact.id = rider.contact_id
left join civicrm_email email on
  email.contact_id = rider.contact_id and
  email.is_primary = 1
left join civicrm_phone phone on
  phone.contact_id = rider.contact_id and
  phone.is_primary = 1
left join civicrm_address address on
  address.contact_id = rider.contact_id and
  address.is_primary = 1
left join civicrm_state_province state on state.id = address.state_province_id
where
  rider.reg_level != 'team'
group by rider.contact_id


