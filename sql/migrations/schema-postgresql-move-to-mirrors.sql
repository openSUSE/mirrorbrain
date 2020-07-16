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
   return_data integer;
BEGIN
  -- TODO:
  -- Learn how we can call it from a function
  -- PERFORM REFRESH materialized view filemetadata_mirror_count;
  WITH affected_rows AS (
    DELETE FROM filemetadata
      WHERE id IN (
        SELECT filemetadata_id
          FROM filemetadata_mirror_count
          WHERE count = 0
    ) RETURNING *
  )
  SELECT INTO return_data count(*)
    FROM affected_rows;
  RETURN return_data;
END $BODY$;

-- FUNCTION: public.mirr_add_byid(integer, integer)

DROP FUNCTION IF EXISTS public.mirr_add_byid(integer, integer);

CREATE OR REPLACE FUNCTION public.mb_mirror_add_file(
    arg_serverid integer,
    arg_fileid integer
  )
    RETURNS integer
    LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
   return_data integer;
BEGIN
  WITH affected_rows AS (
    INSERT INTO mirrors (filemetadata_id, server_id)
      VALUES (arg_fileid, arg_serverid)
      ON CONFLICT DO NOTHING
      RETURNING *
  )
  SELECT INTO return_data count(*)
    FROM affected_rows;
  RETURN return_data;
END;
$BODY$;

-- FUNCTION: public.mb_add_bypath(integer, text)

DROP FUNCTION IF EXISTS public.mirr_add_bypath(integer, text);

CREATE OR REPLACE FUNCTION public.mb_mirror_add_file(
    arg_serverid integer,
    arg_path text
  )
    RETURNS integer
    LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    fileid integer;
    return_data integer;
BEGIN
    SELECT INTO fileid id FROM filemetadata WHERE path = arg_path;

    -- There are three cases to handle, and we want to handle each of them
    -- with the minimal effort.
    -- In any case, we return a file id in the end.
    IF fileid IS NULL THEN
        RAISE DEBUG 'we do not know about the file "%".', arg_path;
    ELSE
        RAISE DEBUG 'update existing file entry (path: % id: %)', arg_path, fileid;
        SELECT into return_data mb_mirror_add_file(arg_serverid, fileid);
        RETURN return_data;
    END IF;

    RETURN 0;
END;
$BODY$;

-- FUNCTION: public.mirr_del_byid(integer, integer)

DROP FUNCTION IF EXISTS public.mirr_del_byid(integer, integer);

--
-- TODO: for consistency with the mb_mirror_add_file() function se should probably also add
--       mb_mirror_remove_file(integer, text)
CREATE OR REPLACE FUNCTION public.mb_mirror_remove_file(
    arg_serverid integer,
    arg_fileid integer
  )
    RETURNS integer
    LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
   return_data integer;
BEGIN
  WITH affected_rows AS (
    DELETE FROM mirrors WHERE server_id = arg_serverid AND filemetadata_id = arg_fileid RETURNING *
  )
  SELECT INTO return_data count(*)
    FROM affected_rows;
  RETURN return_data;
END;
$BODY$;


-- FUNCTION: public.mirr_get_name(integer)

DROP FUNCTION IF EXISTS public.mirr_get_name(integer);

CREATE OR REPLACE FUNCTION public.mb_mirror_identifier(
    arg_serverid integer
  )
    RETURNS text
    LANGUAGE 'sql'
AS $BODY$
  SELECT identifier FROM server WHERE id=arg_serverid
$BODY$;

-- FUNCTION: public.mirr_get_name(smallint[])

DROP FUNCTION IF EXISTS public.mirr_get_name(smallint[]);

CREATE OR REPLACE FUNCTION public.mb_mirror_identifier(
    ids smallint[]
  )
    RETURNS text[]
    LANGUAGE 'sql'
AS $BODY$
  SELECT array_agg(identifier::text) FROM server WHERE id = ANY(ids);
$BODY$;

-- FUNCTION: public.mirr_get_nfiles(integer)

DROP FUNCTION IF EXISTS public.mirr_get_nfiles(integer);

CREATE OR REPLACE FUNCTION public.mb_mirror_filecount(
	  arg_serverid integer
  )
    RETURNS bigint
    LANGUAGE 'sql'
AS $BODY$
  SELECT count(*) FROM mirrors WHERE server_id = arg_serverid;
$BODY$;

-- FUNCTION: public.mirr_get_nfiles(text)

DROP FUNCTION IF EXISTS public.mirr_get_nfiles(text);

CREATE OR REPLACE FUNCTION public.mb_mirror_filecount(
	  arg_server_identifier text
  )
    RETURNS bigint
    LANGUAGE 'sql'
AS $BODY$
  SELECT count(*) FROM mirrors WHERE (SELECT id FROM server WHERE identifier = arg_server_identifier) = server_id;
$BODY$;

-- FUNCTION: public.mirr_hasfile_byid(integer, integer)

DROP FUNCTION IF EXISTS public.mirr_hasfile_byid(integer, integer);

CREATE OR REPLACE FUNCTION public.mb_mirror_has_file(
    arg_serverid integer,
    arg_fileid integer
  )
    RETURNS boolean
    LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    result integer;
BEGIN
    SELECT INTO result 1 FROM mirrors WHERE filemetadata_id = arg_fileid AND server_id = arg_serverid;
    IF result > 0 THEN
        RETURN true;
    END IF;
    RETURN false;
END;
$BODY$;

-- FUNCTION: public.mirr_hasfile_byname(integer, text)

DROP FUNCTION IF EXISTS public.mirr_hasfile_byname(integer, text);

CREATE OR REPLACE FUNCTION public.mb_mirror_has_file(
    arg_serverid integer,
    arg_path text
  )
    RETURNS boolean
    LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    result integer;
    fileid integer;
BEGIN
    SELECT INTO fileid id FROM filemetadata WHERE path = arg_path;

    -- There are three cases to handle, and we want to handle each of them
    -- with the minimal effort.
    -- In any case, we return a file id in the end.
    IF fileid IS NULL THEN
        RAISE DEBUG 'we do not know about the file "%".', arg_path;
    ELSE
      SELECT INTO result 1 FROM mirrors WHERE filemetadata_id = fileid AND server_id = arg_serverid;
      IF result > 0 THEN
          RETURN true;
      END IF;
    END IF;
    RETURN false;
END;
$BODY$;

DROP VIEW IF EXISTS hexhash;
CREATE VIEW hexhash AS
  SELECT
    id,
    mtime,
    size,
    md5,
    encode(md5, 'hex') AS md5hex,
    sha1,
    encode(sha1, 'hex') AS sha1hex,
    sha256,
    encode(sha256, 'hex') AS sha256hex,
    sha1piecesize,
    sha1pieces,
    encode(sha1pieces, 'hex') AS sha1pieceshex,
    btih,
    encode(btih, 'hex') AS btihhex,
    pgp,
    zblocksize,
    zhashlens,
    zsums,
    encode(zsums, 'hex') AS zsumshex
  FROM filemetadata;
