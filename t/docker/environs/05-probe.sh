#!../lib/test-in-container-environs.sh
set -ex

[ -d mirrorbrain ]

./environ.sh pg9-system2
./environ.sh ap9-system2
./environ.sh ap8-system2
./environ.sh ap7-system2
./environ.sh mb9 $(pwd)/mirrorbrain

pg9*/start.sh

mb9*/configure_db.sh pg9
mb9*/configure_apache.sh ap9

ap9=$(ls -d ap9*)

# populate test data
for x in ap7 ap8 ap9; do
    xx=$(ls -d $x*/)
    mkdir -p $xx/dt/downloads/{folder1,folder2,folder3}
    echo $xx/dt/downloads/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

mkdir -p ap9-system2/hashes

mb9*/mb.sh makehashes $PWD/ap9-system2/dt -t $PWD/ap9-system2/hashes

ap9*/start.sh
ap9*/status.sh
# ap9*/curl.sh downloads/folder1/ | grep file1.dat
ap9*/curl.sh downloads/ | grep folder1

for x in ap7 ap8; do
    $x*/start.sh
    $x*/status.sh
    mb9*/mb.sh new $x --http http://"$($x-system2/print_address.sh)" --region NA --country us
    mb9*/mb.sh scan --client-ident mb$x --enable $x
    $x-system2/curl.sh | grep downloads
done

mb9*/mb.sh scan --enable --all -j 2 --client-ident mball

ap9*/curl.sh /downloads/folder1/file1.dat

pg9*/sql.sh mirrorbrain 'select identifier, enabled, status_baseurl from server'

# mb9*/mb.sh test ap7

pg9*/sql.sh mirrorbrain "select enabled, status_baseurl from server where identifier = 'ap7'"

mb9*/mirrorprobe.sh -L DEBUG --client-ident mprobe1 ap7

ap7*/stop.sh
! ap7*/status.sh
! ap7*/curl.sh

# mb9*/mb.sh test ap7 || :

mb9*/mirrorprobe.sh --client-ident mprobeF -L DEBUG ap7 || :
test f == $(pg9-system2/sql.sh -t -c "select scan.success from scan where scanned_by = 'mprobeF'" mirrorbrain)

pg9*/sql.sh mirrorbrain "select enabled, status_baseurl from server where identifier = 'ap7'"

ap9*/curl.sh /downloads/folder1/file1.dat

# only one mirror is available, because mirrorprobe must indicate that ap7 is down
grep 'classifying 1 mirror' ap9*/dt/error_log
grep 'classifying' ap9*/dt/error_log | grep -v 'classifying 2 mirrors'

# start ap7back and probe it
ap7*/start.sh
ap7*/status.sh
ap7*/curl.sh

# mb9*/mb.sh test ap7

mb9*/mirrorprobe.sh -e -L DEBUG --client-ident mprobeT ap7

test t == $(pg9-system2/sql.sh -t -c "select scan.success from scan where scanned_by = 'mprobeT'" mirrorbrain)

pg9*/sql.sh mirrorbrain "select enabled, status_baseurl from server where identifier = 'ap7'"
pg9*/sql.sh mirrorbrain "select scan.*, scan_type.* from scan join scan_type on scan_type_id = scan_type.id order by server_id, scan.id"

ap9*/curl.sh /downloads/folder1/file1.dat

# now two mirros should be available
grep 'classifying 2 mirrors' ap9*/dt/error_log
tail ap9*/dt/error_log | grep 'Chose server '

