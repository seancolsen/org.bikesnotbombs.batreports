<?php

/**
 * A custom contact search
 */
class CRM_Batreports_Form_Search_BATExport
extends CRM_Contact_Form_Search_Custom_Base
implements CRM_Contact_Form_Search_Interface {

  function __construct(&$formValues) {
    parent::__construct($formValues);
  }

  /**
   * Prepare a set of search fields
   *
   * @param CRM_Core_Form $form modifiable
   * @return void
   */
  function buildForm(&$form) {
    CRM_Utils_System::setTitle(ts('Bike-A-Thon export'));

    $form->add('text', 'year', ts('Year'));

    // Optionally define default search values
    $date = date_create('now');
    $form->setDefaults(array(
      'year' => date_format($date, 'Y'),
    ));

    /**
     * if you are using the standard template, this array tells the template what elements
     * are part of the search criteria
     */
    $form->assign('elements', array('year'));
  }

  /**
   * Get a list of summary data points
   *
   * @return mixed; NULL or array with keys:
   *  - summary: string
   *  - total: numeric
   */
  function summary() {
    return NULL;
    // return array(
    //   'summary' => 'This is a summary',
    //   'total' => 50.0,
    // );
  }

  /**
   * Get a list of displayable columns
   *
   * @return array, keys are printable column headers and values are SQL column names
   */
  function &columns() {
    // return by reference
    $columns = array(
      ts('pile') => 'pile',
      ts('cid') => 'cid',
      ts('num') => 'num',
      ts('last_name') => 'last_name',
      ts('first_name') => 'first_name',
      ts('email') => 'email',
      ts('phone') => 'phone',
      ts('address') => 'address',
      ts('status') => 'status',
      ts('reg_date') => 'reg_date',
      ts('reg_by_contact_id') => 'reg_by_contact_id',
      ts('reg_by_name') => 'reg_by_name',
      ts('drupal_user_name') => 'drupal_user_name',
      ts('route ') => 'route',
      ts('total_is_public') => 'total_is_public',
      ts('total') => 'total',
      ts('indiv_t') => 'indiv_t',
      ts('overdue') => 'overdue',
      ts('fmin') => 'fmin',
      ts('pcp_id') => 'pcp_id',
      ts('pcp_url') => 'pcp_url',
      ts('time_printed') => 'time_printed',
      ts('bat_age') => 'bat_age',
      ts('team_name') => 'team_name',
      ts('emergency_name') => 'emergency_name',
      ts('emergency_phone') => 'emergency_phone',
      ts('prev_years') => 'prev_years',
      ts('max_prev_indiv_t') => 'prev_max_direct',
      ts('note') => 'note'
    );
    return $columns;
  }

  /**
   * Construct a full SQL query which returns one page worth of results
   *
   * @param int $offset
   * @param int $rowcount
   * @param null $sort
   * @param bool $includeContactIDs
   * @param bool $justIDs
   * @return string, sql
   */
  function all($offset = 0, $rowcount = 0, $sort = NULL, $includeContactIDs = FALSE, $justIDs = FALSE) {
    // delegate to $this->sql(), $this->select(), $this->from(), $this->where(), etc.
    return $this->sql(
        $this->select(),
        $offset,
        $rowcount,
        $sort,
        $includeContactIDs,
        "group by rider.contact_id");
  }

  /**
   * Construct a SQL SELECT clause
   *
   * @return string, sql fragment with SELECT arguments
   */
  function select() {
    return "
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
    ";
  }

  /**
   * Construct a SQL FROM clause
   *
   * @return string, sql fragment with FROM and JOIN clauses
   */
  function from() {
    $sqlFile = __DIR__ . "/" . basename(__FILE__, '.php') . '.sql';
    $sql = file_get_contents($sqlFile);
    // TODO: replacements
    //    $state = CRM_Utils_Array::value('state_province_id',
    //      $this->_formValues
    //    );
    $queries = explode(";", $sql);
    foreach ($queries as $query) {
      if (!empty(trim($query))) {
        CRM_Core_DAO::executeQuery($query);
      }
    }

    return "
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
    ";
  }

  /**
   * Construct a SQL WHERE clause
   *
   * @param bool $includeContactIDs
   * @return string, sql fragment with conditional expressions
   */
  function where($includeContactIDs = FALSE) {
    return "rider.reg_level != 'team'";
  }

  /**
   * Determine the Smarty template for the search screen
   *
   * @return string, template path (findable through Smarty template path)
   */
  function templateFile() {
    return 'CRM/Contact/Form/Search/Custom.tpl';
  }

  /**
   * @param int $offset
   * @param int $rowcount
   * @param null $sort
   * @param bool $returnSQL
   *
   * @return string
   */
  public function contactIDs($offset = 0, $rowcount = 0, $sort = NULL, $returnSQL = FALSE) {
    $sql = $this->sql(
      'rider.contact_id as contact_id',
      $offset,
      $rowcount,
      $sort
    );

    if ($returnSQL) {
      return $sql;
    }

    return CRM_Core_DAO::composeQuery($sql, CRM_Core_DAO::$_nullArray);
  }

  /**
   * @return null|string
   */
  public function count() {
    return CRM_Core_DAO::singleValueQuery(
      $this->sql('count(distinct rider.contact_id) as total')
    );
  }

}
