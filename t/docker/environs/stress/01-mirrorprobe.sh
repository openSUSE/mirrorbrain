#!../../lib/test-in-container-environs.sh
set -ex

./environ.sh mb9 $(pwd)/mirrorbrain
./environ.sh pg9-system2
./environ.sh ap9-system2
./environ.sh ap8-system2
./environ.sh ap7-system2

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
     mb9*/mb.sh scan --enable $x
     $x-system2/curl.sh | grep downloads
done

# we set plenty duplicates - it makes little sence besides checking how mirrorprobe multithreading works
for n in {1..64}; do
    for x in ap7 ap8; do
        mb9*/mb.sh new $x-$n --http http://"$($x-system2/print_address.sh)" --region NA --country us
        mb9*/mb.sh scan --enable $x-$n
    done
done

pg9*/sql.sh mirrorbrain "update server set status_baseurl = 'f'"

mb9*/mirrorprobe.sh -L DEBUG -e

test " 130 |   130 | 130" == "$(pg9*/sql.sh -t -c "select sum(enabled::int), count(*), sum(status_baseurl::int) from server" mirrorbrain)"

mb9*/mb.sh scan -a -j 32

test " 130 |   130 | 130" == "$(pg9*/sql.sh -t -c "select sum(enabled::int), count(*), sum(status_baseurl::int) from server" mirrorbrain)"
test "260" == $(pg9*/sql.sh -t -c "select sum(success::int) from scan" mirrorbrain)
test "0" == $(pg9*/sql.sh -t -c "select sum(cast(not success as int)) from scan" mirrorbrain)
