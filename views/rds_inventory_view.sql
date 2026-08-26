-- =============================================================================
-- rds_inventory_view — reference SQL
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

CREATE OR REPLACE VIEW "${athena_database_name}".rds_inventory_view AS
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
   , MAX((CASE WHEN (major_rank = 2) THEN majorengineversion END)) "latest_major_version_N-1"
   , MAX((CASE WHEN (major_rank = 3) THEN majorengineversion END)) "latest_major_version_N-2"
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
   , MAX((CASE WHEN (minor_rank = 2) THEN engineversion END)) "latest_minor_version_N-1"
   , MAX((CASE WHEN (minor_rank = 3) THEN engineversion END)) "latest_minor_version_N-2"
   FROM
     ranked_minor_versions
   WHERE (minor_rank <= 3)
   GROUP BY engine, majorengineversion
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
, eos_data AS (
   SELECT
     engine
   , majorengineversion
   , MAX((CASE WHEN (lc.lifecyclesupportname = 'open-source-rds-standard-support') THEN CAST(CAST(lc.lifecyclesupportstartdate AS DATE) AS VARCHAR) END)) standard_support_start
   , MAX((CASE WHEN (lc.lifecyclesupportname = 'open-source-rds-standard-support') THEN CAST(CAST(lc.lifecyclesupportenddate AS DATE) AS VARCHAR) END)) standard_support_end
   , MAX((CASE WHEN (lc.lifecyclesupportname = 'open-source-rds-extended-support') THEN CAST(CAST(lc.lifecyclesupportstartdate AS DATE) AS VARCHAR) END)) extended_support_start
   , MAX((CASE WHEN (lc.lifecyclesupportname = 'open-source-rds-extended-support') THEN CAST(CAST(lc.lifecyclesupportenddate AS DATE) AS VARCHAR) END)) extended_support_end
   FROM
     ("${data_collection_database_name}".rds_db_major_engine_versions
   CROSS JOIN UNNEST(supportedenginelifecycles) t (lc))
   GROUP BY engine, majorengineversion
)
SELECT
  i.dbinstanceidentifier
, i.dbinstanceclass
, i.engine
, i.dbinstancestatus
, i.endpoint
, i.allocatedstorage
, i.instancecreatetime
, i.preferredbackupwindow
, i.backupretentionperiod
, i.dbsecuritygroups
, i.dbparametergroups
, i.preferredmaintenancewindow
, i.multiaz
, i.engineversion
, i.autominorversionupgrade
, i.licensemodel
, i.publiclyaccessible
, i.storageencrypted
, i.dbiresourceid
, i.cacertificateidentifier
, i.dbinstancearn
, i.performanceinsightsenabled
, i.databaseinsightsmode
, i.deletionprotection
, i.certificatedetails
, i.accountid
, i.maxallocatedstorage
, i.latestrestorabletime
, i.readreplicasourcedbinstanceidentifier
, (CASE WHEN i.taglist IS NULL OR i.taglist = '[]' THEN NULL ELSE array_join(transform(CAST(json_parse(i.taglist) AS ARRAY(ROW(Key varchar, Value varchar))), x -> concat(x.Key, ':', x.Value)), ', ') END) taglist
, org.name accountname
, i.collection_date
, i.region
, cm.dbclusteridentifier
, vs.majorengineversion current_major_version
, emaj.latest_major_version
, emaj."latest_major_version_N-1"
, emaj."latest_major_version_N-2"
, i.engineversion current_minor_version
, emin.latest_minor_version
, emin."latest_minor_version_N-1"
, emin."latest_minor_version_N-2"
, COALESCE(vs.engine_version_status, 'Unknown') engine_version_status
, (CASE WHEN (eos.standard_support_end IS NULL) THEN 'Standard Support' WHEN (CAST(eos.standard_support_end AS DATE) > current_date) THEN 'Standard Support' WHEN ((eos.extended_support_end IS NOT NULL) AND (CAST(eos.extended_support_end AS DATE) > current_date)) THEN 'Extended Support' ELSE 'End of Extended Support' END) rds_support_status
, eos.standard_support_start
, eos.standard_support_end
, eos.extended_support_start
, eos.extended_support_end
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
LEFT JOIN eos_data eos ON ((i.engine = eos.engine) AND (vs.majorengineversion = eos.majorengineversion)))
