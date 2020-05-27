#!../lib/test-in-container-environs.sh
set -e

[ -d mirrorbrain ]

./environ.sh pg9-system2
# main server supports both http and https
./environ.sh ap9-system2
ap9*/configure_add_https.sh

# this mirror will do only http
./environ.sh ap8-system2
# this mirror will do only https
./environ.sh ap7-system2
ap7*/configure_ssl.sh

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

mb9*/mb.sh makehashes $PWD/ap9-system2/dt -t $PWD/ap9-system2/hashes
rs9*/start.sh
rs9*/status.sh

ap9*/start.sh
ap9*/status.sh
ap9*/curl.sh downloads/ | grep folder1

for x in ap7 ap8; do
    $x*/start.sh
    $x*/status.sh
    [ $x != ap7 ] || mb9*/mb.sh new $x --http https://$($x*/print_address.sh) --rsync rsync://$(id -un):$(id -un)@127.0.0.1:9090/$x  --region NA --country us
    [ $x != ap8 ] || mb9*/mb.sh new $x --http  http://$($x*/print_address.sh) --rsync rsync://$(id -un):$(id -un)@127.0.0.1:9090/$x  --region NA --country us
    mb9*/mb.sh scan --enable $x
    $x-system2/curl.sh | grep downloads
done

# make sure we are redirected solely to http-only server ap8
ap9*/curl.sh /downloads/folder1/file1.dat | grep here | grep $(ap8*/print_address.sh)
ap9*/curl.sh /downloads/folder1/file1.dat | grep here | grep $(ap8*/print_address.sh)
ap9*/curl.sh /downloads/folder1/file1.dat | grep here | grep $(ap8*/print_address.sh)
ap9*/curl.sh /downloads/folder1/file1.dat | grep here | grep $(ap8*/print_address.sh)

# now make sure https requests are redirected to https-only server ap7
ap9*/curl_https.sh /downloads/folder1/file1.dat | grep here | grep $(ap7*/print_address.sh)
ap9*/curl_https.sh /downloads/folder1/file1.dat | grep here | grep $(ap7*/print_address.sh)
ap9*/curl_https.sh /downloads/folder1/file1.dat | grep here | grep $(ap7*/print_address.sh)
ap9*/curl_https.sh /downloads/folder1/file1.dat | grep here | grep $(ap7*/print_address.sh)

grep 'Found ' ap9*/dt/error_log
grep 'Chose server ' ap9*/dt/error_log
