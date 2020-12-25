#!../lib/test-in-container-environs.sh
set -e

[ -d mirrorbrain ]

./environ.sh pg9-system2
./environ.sh ap9-system2
./environ.sh ap8-system2
./environ.sh ap7-system2
./environ.sh mb9 $(pwd)/mirrorbrain
./environ.sh rs9-system2

pg9*/start.sh

mb9*/configure_db.sh pg9
mb9*/configure_apache.sh ap9

ap9=$(ls -d ap9*)

# populate test data
for x in ap7 ap8 ap9; do
    xx=$(ls -d $x*/)
    mkdir -p $xx/dt/downloads/{folder1,folder2,folder3}
    echo $xx/dt/downloads/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    rs9*/configure_dir.sh $x $(pwd)/$xx/dt
done

mkdir -p ap9-system2/hashes

mb9*/mb.sh makehashes -v $PWD/ap9-system2/dt
rs9*/start.sh

# since all mirrors are https - only - we must use https as well
ap9*/configure_ssl.sh
ap9*/start.sh
ap9*/curl.sh downloads/ | grep folder1

for x in ap7 ap8; do
    $x*/configure_ssl.sh
    $x*/start.sh
    $x*/status.sh
    mb9*/mb.sh new $x --http https://"$($x-system2/print_address.sh)" --rsync rsync://$(id -un):$(id -un)@127.0.0.1:9090/$x  --region NA --country us
    SSL_CERT_FILE=$(pwd)/ca/ca.pem mb9*/mb.sh scan --enable $x
    $x-system2/curl.sh | grep downloads
done

ap9*/curl.sh /downloads/folder1/file1.dat

tail ap9*/dt/error_log | grep 'Chose server '
