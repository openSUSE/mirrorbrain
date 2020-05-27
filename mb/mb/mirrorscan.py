from sqlobject import *
from sqlobject.sqlbuilder import *
from enum import IntEnum
from datetime import datetime

import mb.conn

class ScanScheme(IntEnum):
    Http = 0,
    Ftp = 1,
    Rsync = 2

def isSsl(url):
    if url.startswith('https://'):
        return True
    if url.startswith('ftps://'):
        return True
    return False

def start_mirror_scan(conn, mirror_id, client_ident, scheme, is_probe, is_ssl, is_ipv6 = False):
    st = conn.ScanType.select(AND(conn.ScanType.q.serverID==mirror_id, conn.ScanType.q.isProbe==is_probe, conn.ScanType.q.isSsl==is_ssl, conn.ScanType.q.isIpv6==is_ipv6, conn.ScanType.q.scheme==int(scheme))).getOne(None)
    if st == None:
        st = conn.ScanType(serverID=mirror_id, isProbe=is_probe, isSsl=is_ssl, isIpv6=is_ipv6, scheme=int(scheme))

    return conn.Scan(scanTypeID=st.id, startedAt = datetime.now(), scannedBy=client_ident)

def finish_mirror_scan(conn, scan, success):
    rev = 0
    last_scan = conn.Scan.select(AND(conn.Scan.q.id != scan.id, conn.Scan.q.scanTypeID == scan.scanTypeID)).orderBy('-finished_at').limit(1).getOne(None)
    if last_scan is not None:
        if last_scan.success == success:
            rev = last_scan.revision
        else:
            rev = last_scan.revision + 1

    scan.set(revision = rev, success = success,  finishedAt = datetime.now())
