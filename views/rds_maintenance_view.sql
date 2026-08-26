-- =============================================================================
-- rds_maintenance_view — reference SQL
--
-- Mirrors the deployed view embedded in dashboards/rds-dashboard.yaml (views: section),
-- which is the source of truth. Regenerate from there after any manifest change.
--
-- View-only architecture (no Analysis Lambda): reads CID inventory + reference
-- module tables directly. Variable/optional nested columns (dbclustermembers,
-- taglist) are stored as string and parsed at query time via
-- CAST(json_parse(...) AS ARRAY(ROW(...))) + UNNEST, per CID coding-standards Sec 1.8.
--
-- Parameters ${athena_database_name} / ${data_collection_database_name} are
-- resolved by cid-cmd at deploy time.
-- =============================================================================

CREATE OR REPLACE VIEW "${athena_database_name}".rds_maintenance_view AS
WITH
  cluster_members AS (
   SELECT DISTINCT
     c.accountid
   , c.region
   , c.dbclusteridentifier
   , m.dbinstanceidentifier
   FROM
     ("${data_collection_database_name}".inventory_rds_db_clusters_data c
   CROSS JOIN UNNEST(CAST(json_parse(c.dbclustermembers) AS ARRAY(ROW(dbinstanceidentifier varchar, isclusterwriter boolean, dbclusterparametergroupstatus varchar, promotiontier integer)))) t (m))
)
, version_status_lookup AS (
   SELECT DISTINCT
     engine
   , engineversion
   , majorengineversion
   , status engine_version_status
   FROM
     "${data_collection_database_name}".rds_db_engine_versions
)
, ranked_major_versions AS (
   SELECT DISTINCT
     engine
   , majorengineversion
   , DENSE_RANK() OVER (PARTITION BY engine ORDER BY CAST(SPLIT_PART(majorengineversion, '.', 1) AS INTEGER) DESC, CAST(COALESCE(NULLIF(SPLIT_PART(majorengineversion, '.', 2), ''), '0') AS INTEGER) DESC) major_rank
   FROM
     "${data_collection_database_name}".rds_db_engine_versions
   WHERE ((status = 'available') AND ((supportslimitlessdatabase = false) OR (supportslimitlessdatabase IS NULL)))
)
, engine_major_versions AS (
   SELECT
     engine
   , MAX((CASE WHEN (major_rank = 1) THEN majorengineversion END)) latest_major_version
   FROM
     ranked_major_versions
   WHERE (major_rank <= 3)
   GROUP BY engine
)
, ranked_minor_versions AS (
   SELECT DISTINCT
     engine
   , majorengineversion
   , engineversion
   , DENSE_RANK() OVER (PARTITION BY engine, majorengineversion ORDER BY CAST(REGEXP_EXTRACT(engineversion, '^(\d+)', 1) AS INTEGER) DESC, CAST(COALESCE(NULLIF(REGEXP_EXTRACT(engineversion, '^\d+\.(\d+)', 1), ''), '0') AS INTEGER) DESC, CAST(COALESCE(NULLIF(REGEXP_EXTRACT(engineversion, '^\d+\.\d+\.(\d+)', 1), ''), '0') AS INTEGER) DESC, engineversion DESC) minor_rank
   FROM
     "${data_collection_database_name}".rds_db_engine_versions
   WHERE ((supportslimitlessdatabase = false) OR (supportslimitlessdatabase IS NULL))
)
, engine_minor_versions AS (
   SELECT
     engine
   , majorengineversion
   , MAX((CASE WHEN (minor_rank = 1) THEN engineversion END)) latest_minor_version
   FROM
     ranked_minor_versions
   WHERE (minor_rank <= 3)
   GROUP BY engine, majorengineversion
)
SELECT
  i.dbinstanceidentifier
, i.engine
, i.dbinstancestatus
, i.multiaz
, i.engineversion
, i.autominorversionupgrade
, i.accountid
, org.name accountname
, i.collection_date
, i.region
, vs.majorengineversion current_major_version
, emaj.latest_major_version
, i.engineversion current_minor_version
, emin.latest_minor_version
, cm.dbclusteridentifier
, vs.engine_version_status
, m.action
, m.description
, m.currentapplydate
, m.autoappliedafterdate
, m.forcedapplydate
, m.optinstatus
, i.payer_id
, i.year
, i.month
, i.day
FROM
  (((((("${data_collection_database_name}".inventory_rds_db_instances_data i
LEFT JOIN cluster_members cm ON ((i.accountid = cm.accountid) AND (i.region = cm.region) AND (i.dbinstanceidentifier = cm.dbinstanceidentifier)))
LEFT JOIN "${data_collection_database_name}".organization_data org ON (i.accountid = org.id))
LEFT JOIN version_status_lookup vs ON ((i.engine = vs.engine) AND (i.engineversion = vs.engineversion)))
LEFT JOIN engine_major_versions emaj ON (i.engine = emaj.engine))
LEFT JOIN engine_minor_versions emin ON ((i.engine = emin.engine) AND (vs.majorengineversion = emin.majorengineversion)))
LEFT JOIN "${data_collection_database_name}".rds_maintenance_data m ON ((m.resourceidentifier = i.dbinstancearn) AND (m.accountid = i.accountid) AND (date(CAST(m.collection_date AS timestamp)) = date(CAST(i.collection_date AS timestamp))) AND (m.region = i.region) AND (m.payer_id = i.payer_id)))
