DROP TABLE IF EXISTS filemetadata, mirrors CASCADE;
DROP MATERIALIZED VIEW IF EXISTS filemetadata_mirror_count;

CREATE TABLE filemetadata
(
    id integer GENERATED ALWAYS AS IDENTITY,
    path character varying NOT NULL,
    path_hash bytea GENERATED ALWAYS AS (digest((path)::text, 'sha256'::text)) STORED,
    mtime timestamp with time zone,
    size bigint,
    md5 bytea,
    sha1 bytea,
    sha256 bytea,
    sha1piecesize integer,
    sha1pieces bytea,
    btih bytea,
    pgp text,
    zblocksize smallint,
    zhashlens character varying(8),
    zsums bytea,
    created_at timestamp(6) with time zone NOT NULL DEFAULT now(),
    updated_at timestamp(6) with time zone NOT NULL DEFAULT now(),
    CONSTRAINT pk_filemetadata PRIMARY KEY (id)
);

CREATE INDEX idx_filemetadata_on_mtime_and_size
    ON filemetadata USING btree
    (mtime ASC NULLS LAST, size ASC NULLS LAST);

CREATE UNIQUE INDEX idx_filemetadata_on_path_unique
    ON filemetadata USING btree
    (path ASC NULLS LAST);

CREATE TABLE mirrors
(
    server_id smallint NOT NULL,
    filemetadata_id integer NOT NULL,
    CONSTRAINT fk_mirrors_filemetadata FOREIGN KEY (filemetadata_id)
        REFERENCES filemetadata (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE,
    CONSTRAINT fk_mirrors_servers FOREIGN KEY (server_id)
        REFERENCES server (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE
);

CREATE UNIQUE INDEX idx_mirrors_on_server_id_and_filemetadata_id
    ON mirrors USING btree
    (filemetadata_id ASC NULLS LAST, server_id ASC NULLS LAST);

CREATE INDEX idx_mirrors_server_id
    ON mirrors USING btree
    (server_id ASC NULLS LAST);

CREATE MATERIALIZED VIEW filemetadata_mirror_count AS
  SELECT
      filemetadata.id AS filemetadata_id,
      count(mirrors.filemetadata_id) AS count
    FROM filemetadata
    LEFT JOIN mirrors
      ON filemetadata.id = mirrors.filemetadata_id
    WHERE mtime < (now()-'3 months'::interval)
    GROUP BY filemetadata.id
    ORDER BY filemetadata.id
WITH DATA;

CREATE INDEX idx_filemetadata_mirror_count_id
  ON filemetadata_mirror_count
  USING btree(filemetadata_id);

CREATE INDEX idx_filemetadata_mirror_count_nonzero_count
  ON filemetadata_mirror_count
  USING btree(count)
  WHERE count > 0;

CREATE INDEX idx_filemetadata_mirror_count_zero_count
  ON filemetadata_mirror_count
  USING btree(count)
  WHERE count = 0;

CREATE OR REPLACE FUNCTION mb_cleanup_old_files()
    RETURNS integer
    LANGUAGE 'plpgsql'

AS $BODY$
  DECLARE
  BEGIN
  -- TODO:
  -- Learn how we can call it from a function
  -- PERFORM REFRESH materialized view filemetadata_mirror_count;
  DELETE FROM filemetadata
    WHERE id IN (
      SELECT filemetadata_id
        FROM filemetadata_mirror_count
        WHERE count = 0
  ) RETURNING *;
END $BODY$;
